// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {
    ASSET_STABLE_COIN,
    ASSET_CRYPTO,
    PROTOCOL_LENDING,
    PROTOCOL_STAKING,
    PROTOCOL_AMM,
    PROTOCOL_INTENT,
    IMPLEMENTATION_VAULT,
    IBittyV1Guard
} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";
import {console2} from "forge-std/console2.sol";

contract Deploy is DeployGuard {
    // Config keys the vault stack reads FROM the guard — the single source of truth for the protocol
    // owner and the wrapped-native (gas) token. keccak of the same strings the vault's Constants use.
    bytes32 private constant CFG_OWNER = keccak256("bitty.owner");
    bytes32 private constant CFG_GAS_WRAPPED = keccak256("bitty.gasWrapped");

    function deploy() public override {
        _asset("WETH", ASSET_CRYPTO);
        _asset("WBTC", ASSET_CRYPTO);
        _asset("USDT", ASSET_STABLE_COIN);
        _asset("USDC", ASSET_STABLE_COIN);

        _protocol("AAVE", PROTOCOL_LENDING);
        _protocol("LIDO", PROTOCOL_STAKING);
        _protocol("SKY", PROTOCOL_STAKING);
        _protocol("UNI", PROTOCOL_AMM);
        _protocol("COW", PROTOCOL_INTENT);

        _deployGuard();
        _configure();
    }

    /**
     * @dev Configure the guard so the vault deploy's prerequisites are met in one place: the protocol
     *      OWNER and the wrapped-native gas token (CFG_OWNER / CFG_GAS_WRAPPED, both asserted by the
     *      vault Deploy), plus the vault implementation (deterministic, same address on every chain).
     *      Every set is idempotent — re-running skips whatever already matches — and setImplementation
     *      only records the address (no code read), so registering the impl before the vault stack is
     *      deployed on this chain is safe; the vault Deploy's own setImplementation then no-ops.
     *
     *      Requires the deployer to hold the guard's CONFIG_MANAGER_ROLE and IMPLEMENTATION_MANAGER_ROLE
     *      — granted to the initializer in {DeployGuard-_deployGuard}, i.e. this same sender.
     */
    function _configure() private {
        IBittyV1Guard guard = IBittyV1Guard(getAddress("BITTY_GUARD"));

        address owner = getAddress("OWNER");
        if (guard.getAddress(CFG_OWNER) != owner) {
            guard.setAddress(CFG_OWNER, owner);
            console2.log("CFG_OWNER set", owner);
        }

        address gasWrapped = getAddress("WETH");
        if (guard.getAddress(CFG_GAS_WRAPPED) != gasWrapped) {
            guard.setAddress(CFG_GAS_WRAPPED, gasWrapped);
            console2.log("CFG_GAS_WRAPPED set", gasWrapped);
        }

        address vaultImpl = getAddress("VAULT_IMPL");
        if (guard.latestImplementation(IMPLEMENTATION_VAULT) != vaultImpl) {
            guard.setImplementation(vaultImpl, IMPLEMENTATION_VAULT);
            console2.log("vault implementation registered", vaultImpl);
        }
    }
}
