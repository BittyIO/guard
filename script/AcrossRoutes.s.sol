// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {console2} from "forge-std/console2.sol";
import {IBittyV1Guard, ASSET_BRIDGEABLE} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployScript} from "./BaseDeploy.sol";

/**
 * @notice Turns on Across bridging between Ethereum, Base and Arbitrum on the guard of the chain it
 *         runs against: marks WETH, USDC and USDT bridgeable, and writes the route from each of them
 *         to each of the other two chains. Run it once per chain, by the holder of the guard's asset
 *         and config manager roles.
 *
 * @dev The guard is already initialized on these chains, so this cannot ride on the chain's guard
 *      script, which only registers assets at initialize. Re-runnable: an asset already bridgeable and
 *      a route already holding the value below are skipped, so a re-run sends nothing.
 *
 *      The table is the three chains' tokens as Across routes them (app.across.to/api/available-
 *      routes), checked against each chain's deployments TOML for the chain the script runs on. The
 *      native coin needs no row of its own: the adapter keys it by the SpokePool's wrapped native
 *      token, which is WETH on all three.
 *
 *      A route's value packs the output token, its decimals and the most the bridge may keep, in the
 *      layout of protocol-store's AcrossBridgeProtocol.packRoute.
 */
contract AcrossRoutes is DeployScript {
    bytes32 internal constant ROUTE_KEY = keccak256("bitty.bridge.across.route");

    /// @dev 1%: Across's live cost for $100 is 0.01-0.06% between these chains, and about 1% only near
    ///      $5, so this refuses only bridges too small to be worth their gas. Max 300 (the adapter's cap).
    uint16 internal constant MAX_COST_BPS = 100;

    uint256 internal constant N_CHAINS = 3;
    uint256 internal constant N_TOKENS = 3;
    string[N_TOKENS] internal KEYS = ["WETH", "USDC", "USDT"];
    uint8[N_TOKENS] internal DECIMALS = [18, 6, 6];
    uint256[N_CHAINS] internal CHAINS = [1, 8453, 42161];

    function _token(uint256 chainId, uint256 i) internal pure returns (address) {
        if (chainId == 1) {
            return [
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                0xdAC17F958D2ee523a2206206994597C13D831ec7
            ][i];
        }
        if (chainId == 8453) {
            return [
                0x4200000000000000000000000000000000000006,
                0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2
            ][i];
        }
        if (chainId == 42161) {
            return [
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
            ][i];
        }
        revert("AcrossRoutes: chain not in the table");
    }

    function routeKey(address inputToken, uint256 destinationChainId) public pure returns (bytes32) {
        return keccak256(abi.encode(ROUTE_KEY, inputToken, destinationChainId));
    }

    function packRoute(address outputToken, uint8 outputDecimals, uint16 maxCostBps) public pure returns (uint256) {
        return uint256(uint160(outputToken)) | (uint256(outputDecimals) << 160) | (uint256(maxCostBps) << 168);
    }

    function deploy() public override {
        IBittyV1Guard guard = IBittyV1Guard(getAddress("BITTY_GUARD"));
        uint256 here = block.chainid;

        address[] memory assets = new address[](N_TOKENS);
        uint8[] memory categories = new uint8[](N_TOKENS);
        uint256 n;
        for (uint256 i = 0; i < N_TOKENS; i++) {
            address token = _token(here, i);
            require(getAddress(KEYS[i]) == token, string.concat("AcrossRoutes: TOML disagrees on ", KEYS[i]));
            uint8 category = guard.assetCategory(token);
            require(category != 0, string.concat("AcrossRoutes: not a guard asset: ", KEYS[i]));
            if (category & ASSET_BRIDGEABLE != 0) continue;
            assets[n] = token;
            categories[n] = category | ASSET_BRIDGEABLE;
            console2.log(string.concat("bridgeable: ", KEYS[i]), category, "->", categories[n]);
            n++;
        }
        if (n != 0) {
            assembly {
                mstore(assets, n)
                mstore(categories, n)
            }
            guard.addAssets(assets, categories);
        }

        for (uint256 c = 0; c < N_CHAINS; c++) {
            uint256 there = CHAINS[c];
            if (there == here) continue;
            for (uint256 i = 0; i < N_TOKENS; i++) {
                bytes32 key = routeKey(_token(here, i), there);
                uint256 value = packRoute(_token(there, i), DECIMALS[i], MAX_COST_BPS);
                if (guard.getUint(key) == value) continue;
                guard.setUint(key, value);
                console2.log(string.concat("route ", KEYS[i], " ->"), there);
                console2.logBytes32(key);
                console2.log("  value", value);
            }
        }
    }
}
