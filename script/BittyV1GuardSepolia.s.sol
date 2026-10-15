// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ASSET_STABLE_COIN, ASSET_CRYPTO, ASSET_AMM_LIQUID} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

contract Deploy is DeployGuard {
    function deploy() public override {
        _asset("WETH", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("WBTC", ASSET_CRYPTO);
        _asset("USDT", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);
        _asset("USDC", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);

        _deployGuard();
    }
}
