// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ASSET_STABLE_COIN, ASSET_CRYPTO, ASSET_AMM_LIQUID} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

/**
 * @notice The guard's registry for Arbitrum One.
 *
 * @dev No staking entry: Arbitrum has neither Sky nor a native Lido deployment, so there is no
 *      PROTOCOL_STAKING adapter to register. Everything else — the salt, the bootstrap, the deploy
 *      itself — lives in {DeployGuard} and is identical on every chain, which is what keeps the
 *      guard at one address everywhere.
 *
 *      The three protocol keys come from protocol-store's DeployArbitrum run and must be filled
 *      into deployments/arbitrum.toml first; see the note in that file.
 */
contract Deploy is DeployGuard {
    function deploy() public override {
        _asset("WETH", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("WBTC", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("USDT", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);
        _asset("USDC", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);

        _deployGuard();
    }
}
