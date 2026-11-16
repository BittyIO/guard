// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ASSET_STABLE_COIN, ASSET_CRYPTO, ASSET_AMM_LIQUID} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

/**
 * @notice The guard's registry for BNB Smart Chain (id 56; Foundry names it `bsc`).
 *
 * @dev The native coin is BNB, 18 decimals like ETH, so the guard is the EVM build unchanged and lands
 *      at the same address as everywhere else: both CREATE2 factories {DeployGuard} goes through are
 *      on BNB Chain. What differs is the gas-wrapped token, WBNB rather than WETH ({_gasWrappedKey}),
 *      and ETH being an asset of its own here (Binance-Peg ETH) instead of the gas coin.
 *
 *      Every token is 18 decimals on this chain, the stable coins too. Nothing in the guard assumes
 *      otherwise (it reads decimals() from the token), but anything off-chain pricing USDT/USDC at 6
 *      decimals would be wrong by 10^12 here.
 *
 *      No protocols at initialize, as on Arbitrum: adapters are registered once protocol-store has
 *      been deployed to this chain.
 *
 *      Run:  forge script script/BittyV1GuardBsc.s.sol:Deploy --rpc-url bsc --broadcast -vvvv
 */
contract Deploy is DeployGuard {
    function deploy() public override {
        _asset("WBNB", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("BTCB", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("ETH", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("USDT", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);
        _asset("USDC", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);

        address guard = _deployGuard();
        _configure(guard);
    }

    function _gasWrappedKey() internal pure override returns (string memory) {
        return "WBNB";
    }
}
