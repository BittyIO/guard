// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ASSET_STABLE_COIN, ASSET_CRYPTO, PROTOCOL_AMM} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

// Asset categories are a bitmask, and this bit marks an asset the vault may market-swap through the
// AMM on either leg. Owner-curated data on the other chains (set after the fact); here it is known
// at deploy time - every core asset has a Uniswap pool - so it is registered in the same step.
uint8 constant ASSET_AMM_LIQUID = 4;

/**
 * @notice Robinhood Chain (Arbitrum Orbit L2, id 4663).
 *
 * @dev The registry is small on purpose. Uniswap V3 is the only venue with an adapter here; there is
 *      no Aave, CoW, Lido or Sky on this chain (Morpho is the lending venue, and no adapter exists for
 *      it yet). Two stable coins: the bridged USDC and USDG, Robinhood's preferred dollar. Stock tokens
 *      are the chain's reason to exist and are registered by the owner as they are listed, not here -
 *      the on-chain registry moves faster than a deploy script.
 *
 *      Order: protocol-store's DeployRobinhood first (UNI below is its output), then this, then the
 *      vault's Deploy - which asserts the CFG_OWNER / CFG_GAS_WRAPPED this script sets.
 *
 *      Run:  forge script script/BittyV1GuardRobinhood.s.sol:Deploy --rpc-url robinhood --broadcast -vvvv
 */
contract Deploy is DeployGuard {
    function deploy() public override {
        _asset("WETH", ASSET_CRYPTO | ASSET_AMM_LIQUID);
        _asset("USDC", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);
        _asset("USDG", ASSET_STABLE_COIN | ASSET_AMM_LIQUID);
        _protocol("UNI", PROTOCOL_AMM);
        address guard = _deployGuard();
        _configure(guard);
    }
}
