// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IBittyV1Guard, ASSET_BRIDGEABLE} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployScript} from "./BaseDeploy.sol";

/**
 * @notice Turns on Across bridging between Ethereum, Base, Arbitrum, BNB Chain and Robinhood Chain on
 *         the guard of the chain it runs against: marks the chain's bridged tokens bridgeable, and
 *         writes the route from each of them to every other chain Across serves for it, and marks
 *         every one of those chains EVM for the vault's every-EVM-chain recipients. Run it once
 *         per chain, by the holder of the guard's asset and config manager roles.
 *
 * @dev The guard is already initialized on these chains, so this cannot ride on the chain's guard
 *      script, which only registers assets at initialize. Re-runnable: an asset already bridgeable and
 *      a route already holding the value below are skipped, so a re-run sends nothing, and running it
 *      again on a chain set up before a chain was added only writes the routes to the new chain.
 *
 *      Tokens come in three kinds, and a route carries a token to the same kind on the other chain:
 *
 *        kind   Ethereum / Base / Arbitrum   BNB Chain                 Robinhood Chain
 *        ETH    WETH                         ETH (Binance-peg, ERC-20) WETH
 *        USD    USDC                         USDC (18 decimals)        USDG
 *        USDT   USDT                         USDT (18 decimals)        -
 *
 *      as Across routes them (app.across.to/api/available-routes). Across has no USDC route between
 *      BNB Chain and Robinhood Chain, and Robinhood has no USDT. A USD route between Robinhood and the
 *      others changes coin (USDG one side, USDC the other); both are stablecoins, so the loss
 *      allowance values them alike.
 *
 *      The native coin needs no row of its own: the adapter keys it by the SpokePool's wrapped native
 *      token, which is the ETH kind's token everywhere but BNB Chain, whose native coin, BNB, Across
 *      does not carry and so has no route. BNB Chain's ETH moves as the ERC-20 it is.
 *
 *      The chain the script runs on is checked against its deployments TOML and the tokens' own
 *      decimals, so the table cannot drift from the guard's assets unnoticed.
 *
 *      A route's value packs the output token, its decimals and the most the bridge may keep, in the
 *      layout of protocol-store's AcrossBridgeProtocol.packRoute.
 *
 *      TRON is a destination too, for USDT only: Across carries Ethereum, Base, Arbitrum and BNB Chain
 *      USDT to TRON's USDT (TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t, 6 decimals) and back. The way back is
 *      the TRON guard's to set (protocol-store tron/across.mjs routes --set). A route to TRON reaches
 *      a vault only through an adapter built with TRON's vault factory (protocol-store 1.1.1).
 */
contract AcrossRoutes is DeployScript {
    bytes32 internal constant ROUTE_KEY = keccak256("bitty.bridge.across.route");

    /// @dev 1%: Across's live cost for $100 is 0.01-0.08% between these chains, and about 1% only near
    ///      $5, so this refuses only bridges too small to be worth their gas. Max 300 (the adapter's cap).
    uint16 internal constant MAX_COST_BPS = 100;

    /// @dev Into TRON Across charges a flat ~6.2 USDT (quoted 2026-11-25 from BNB Chain: 30 USDT ->
    ///      23.8, 100 -> 93.8), which {MAX_FLAT_COST_TO_TRON} covers, so the share only has to bound
    ///      what a bad quote could keep on a large transfer: 1% (chosen 2026-11-25; 3% before the
    ///      flat cost). An adapter before 1.2.2 reads no flat cost, so through one 1% refuses
    ///      anything under ~620 USDT.
    uint16 internal constant MAX_COST_BPS_TO_TRON = 100;
    /// @dev ...and a flat 8 USDT on top (in TRON USDT's 6 decimals), so a 10 or 100 USDT transfer
    ///      can go: Across's ~6.2 USDT is per transfer, not per amount. Only protocol-store's Across
    ///      adapter from 1.2.2 reads it (capped there at 10 USDT); older ones ignore those bits.
    uint64 internal constant MAX_FLAT_COST_TO_TRON = 8e6;
    uint256 internal constant TRON_CHAIN_ID = 728126428;
    /// @dev TRON USDT, TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t: the 20 bytes behind the T… address.
    address internal constant TRON_USDT = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;
    uint256 internal constant KIND_USDT = 2;
    /// @dev The guard key that marks a chain EVM (value 1) for the vault's every-EVM-chain whitelisted
    ///      recipients: keccak256(abi.encode(EVM_CHAIN_KEY, chainId)), as the vault (1.2.1 on) reads
    ///      it. Every chain in {CHAINS} is EVM; TRON and Solana are never marked.
    bytes32 internal constant EVM_CHAIN_KEY = keccak256("bitty.chain.evm");

    uint256 internal constant N_CHAINS = 5;
    uint256 internal constant N_KINDS = 3;
    string[N_KINDS] internal KINDS = ["ETH", "USD", "USDT"];
    uint256[N_CHAINS] internal CHAINS = [1, 8453, 42161, 56, 4663];

    struct Token {
        address token;
        uint8 decimals;
        string key; // its key in the chain's deployments TOML
    }

    function _token(uint256 chainId, uint256 kind) internal pure returns (Token memory) {
        if (chainId == 1) {
            if (kind == 0) return Token(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 18, "WETH");
            if (kind == 1) return Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6, "USDC");
            return Token(0xdAC17F958D2ee523a2206206994597C13D831ec7, 6, "USDT");
        }
        if (chainId == 8453) {
            if (kind == 0) return Token(0x4200000000000000000000000000000000000006, 18, "WETH");
            if (kind == 1) return Token(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 6, "USDC");
            return Token(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, 6, "USDT");
        }
        if (chainId == 42161) {
            if (kind == 0) return Token(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 18, "WETH");
            if (kind == 1) return Token(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 6, "USDC");
            return Token(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 6, "USDT");
        }
        if (chainId == 56) {
            if (kind == 0) return Token(0x2170Ed0880ac9A755fd29B2688956BD959F933F8, 18, "ETH");
            if (kind == 1) return Token(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, 18, "USDC");
            return Token(0x55d398326f99059fF775485246999027B3197955, 18, "USDT");
        }
        if (chainId == 4663) {
            if (kind == 0) return Token(0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73, 18, "WETH");
            if (kind == 1) return Token(0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168, 6, "USDG");
            return Token(address(0), 0, "");
        }
        revert("AcrossRoutes: chain not in the table");
    }

    /// @dev Pairs Across does not serve for a kind both chains hold.
    function _served(uint256 from, uint256 to, uint256 kind) internal pure returns (bool) {
        if (kind == 1 && ((from == 56 && to == 4663) || (from == 4663 && to == 56))) return false;
        return true;
    }

    function routeKey(address inputToken, uint256 destinationChainId) public pure returns (bytes32) {
        return keccak256(abi.encode(ROUTE_KEY, inputToken, destinationChainId));
    }

    function packRoute(address outputToken, uint8 outputDecimals, uint16 maxCostBps) public pure returns (uint256) {
        return packRoute(outputToken, outputDecimals, maxCostBps, 0);
    }

    /// @dev Bits 184-247: a flat cost on top of the basis points, in the output token's smallest
    ///      units, as protocol-store's AcrossBridgeProtocol (1.2.2 on) packs and reads it.
    function packRoute(address outputToken, uint8 outputDecimals, uint16 maxCostBps, uint64 maxFlatCost)
        public
        pure
        returns (uint256)
    {
        return uint256(uint160(outputToken)) | (uint256(outputDecimals) << 160) | (uint256(maxCostBps) << 168)
            | (uint256(maxFlatCost) << 184);
    }

    function deploy() public override {
        IBittyV1Guard guard = IBittyV1Guard(getAddress("BITTY_GUARD"));
        uint256 here = block.chainid;

        address[] memory assets = new address[](N_KINDS);
        uint8[] memory categories = new uint8[](N_KINDS);
        uint256 n;
        for (uint256 k = 0; k < N_KINDS; k++) {
            Token memory t = _token(here, k);
            if (t.token == address(0)) continue;
            require(getAddress(t.key) == t.token, string.concat("AcrossRoutes: TOML disagrees on ", t.key));
            require(
                IERC20Metadata(t.token).decimals() == t.decimals, string.concat("AcrossRoutes: decimals of ", t.key)
            );
            uint8 category = guard.assetCategory(t.token);
            require(category != 0, string.concat("AcrossRoutes: not a guard asset: ", t.key));
            if (category & ASSET_BRIDGEABLE != 0) continue;
            assets[n] = t.token;
            categories[n] = category | ASSET_BRIDGEABLE;
            console2.log(string.concat("bridgeable: ", t.key), category, "->", categories[n]);
            n++;
        }
        if (n != 0) {
            assembly {
                mstore(assets, n)
                mstore(categories, n)
            }
            guard.addAssets(assets, categories);
        }

        uint256 routes;
        for (uint256 c = 0; c < N_CHAINS; c++) {
            uint256 there = CHAINS[c];
            if (there == here) continue;
            for (uint256 k = 0; k < N_KINDS; k++) {
                Token memory from = _token(here, k);
                Token memory to = _token(there, k);
                if (from.token == address(0) || to.token == address(0) || !_served(here, there, k)) continue;
                routes++;
                bytes32 key = routeKey(from.token, there);
                uint256 value = packRoute(to.token, to.decimals, MAX_COST_BPS);
                if (guard.getUint(key) == value) continue;
                guard.setUint(key, value);
                console2.log(string.concat("route ", from.key, " -> ", to.key, " on"), there);
            }
        }
        // USDT to TRON, from every chain here that holds USDT (Robinhood holds none).
        Token memory usdt = _token(here, KIND_USDT);
        if (usdt.token != address(0)) {
            routes++;
            bytes32 key = routeKey(usdt.token, TRON_CHAIN_ID);
            uint256 value = packRoute(TRON_USDT, 6, MAX_COST_BPS_TO_TRON, MAX_FLAT_COST_TO_TRON);
            if (guard.getUint(key) != value) {
                guard.setUint(key, value);
                console2.log(string.concat("route ", usdt.key, " -> USDT on TRON"), TRON_CHAIN_ID);
            }
        }
        console2.log("routes from this chain:", routes);

        // Every chain here is EVM, this one included, so a vault's every-EVM-chain recipient may be
        // bridged to any of them. Anything but 1 is rewritten, so a wrong value is fixed too.
        for (uint256 c = 0; c < N_CHAINS; c++) {
            bytes32 key = keccak256(abi.encode(EVM_CHAIN_KEY, CHAINS[c]));
            if (guard.getUint(key) == 1) continue;
            guard.setUint(key, 1);
            console2.log("EVM chain marked:", CHAINS[c]);
        }
    }
}
