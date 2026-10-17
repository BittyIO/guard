// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {BittyV1Guard} from "../src/BittyV1Guard.sol";
import {CFG_OWNER, CFG_GAS_WRAPPED} from "../src/interfaces/IBittyV1Guard.sol";
import {DeployGuard} from "./DeployGuard.sol";

/**
 * @title DeployNewVersion
 * @notice Upgrade the live guard to the implementation this tree builds - the upgrade path only. It
 *         never creates, initializes or registers anything: a chain without a guard runs its own
 *         BittyV1Guard<Chain>.s.sol instead.
 *
 * @dev The proxy keeps all of its storage across an upgrade - assets, protocols, config and roles stay
 *      exactly as they were - so nothing is registered again. What a new version adds (e.g. 1.0.1's
 *      price feeds) starts empty and is set separately, per chain.
 *
 *      Re-runnable: an implementation already deployed is reused, and a proxy already on it is
 *      reported and left alone. A build whose `guardVersion()` is not above the live one is refused,
 *      so a stale tree can never downgrade the guard.
 *
 *      The upgrade is sent only when the broadcaster holds DEFAULT_ADMIN_ROLE. Otherwise the script
 *      prints the transaction for whoever does (a Safe, once admin moves there) to submit.
 *
 *      Then, upgraded or not, it fills in CFG_OWNER and CFG_GAS_WRAPPED from deployments/<chain>.toml
 *      where the guard has none. Only where unset: a value already there may have been moved on
 *      purpose (the owner to a Safe), and an upgrade must never quietly hand it back to the deploy key.
 *
 *      Run:  forge script script/DeployNewVersion.s.sol:DeployNewVersion --rpc-url <chain> --broadcast
 */
contract DeployNewVersion is DeployGuard {
    function deploy() public override {
        BittyV1Guard guard = BittyV1Guard(EXPECTED_GUARD);
        require(address(guard).code.length > 0, "DeployNewVersion: no guard on this chain - run its deploy script");
        (, address sender,) = vm.readCallers();

        _upgrade(guard, sender);
        _fillConfig(guard, sender, CFG_OWNER, "CFG_OWNER", getAddress("DEPLOYER"));
        _fillConfig(guard, sender, CFG_GAS_WRAPPED, "CFG_GAS_WRAPPED", getAddress("WETH"));
    }

    function _upgrade(BittyV1Guard guard, address sender) private {
        address impl = deployAtSaltZero(type(BittyV1Guard).creationCode);
        address current = address(uint160(uint256(vm.load(address(guard), ERC1967Utils.IMPLEMENTATION_SLOT))));
        console2.log("guard                 ", address(guard));
        console2.log("live implementation   ", current, guard.versionName());
        console2.log("built implementation  ", impl, BittyV1Guard(impl).versionName());
        if (current == impl) {
            console2.log("guard already on this implementation: nothing to do");
            return;
        }
        require(
            BittyV1Guard(impl).guardVersion() > guard.guardVersion(),
            "DeployNewVersion: built version is not above the live one"
        );

        address admin = guard.defaultAdmin();
        if (sender != admin) {
            console2.log("broadcaster is not the guard admin; submit this from", admin);
            console2.log("  to:  ", address(guard));
            console2.log("  data:");
            console2.logBytes(abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (impl, "")));
            return;
        }

        address owner = guard.getAddress(CFG_OWNER);
        address gasWrapped = guard.getAddress(CFG_GAS_WRAPPED);
        UUPSUpgradeable(address(guard)).upgradeToAndCall(impl, "");

        require(
            address(uint160(uint256(vm.load(address(guard), ERC1967Utils.IMPLEMENTATION_SLOT)))) == impl,
            "DeployNewVersion: proxy not on the new implementation"
        );
        require(guard.guardVersion() == BittyV1Guard(impl).guardVersion(), "DeployNewVersion: version mismatch");
        require(guard.defaultAdmin() == admin, "DeployNewVersion: admin changed");
        require(guard.getAddress(CFG_OWNER) == owner, "DeployNewVersion: CFG_OWNER changed");
        require(guard.getAddress(CFG_GAS_WRAPPED) == gasWrapped, "DeployNewVersion: CFG_GAS_WRAPPED changed");
        console2.log("guard upgraded to", guard.versionName());
    }

    /**
     * @dev Sets `key` to `value` only when the guard has nothing there; a value already set is reported
     *      and kept, even when it differs from the config file.
     */
    function _fillConfig(BittyV1Guard guard, address sender, bytes32 key, string memory name, address value) private {
        address live = guard.getAddress(key);
        if (live != address(0)) {
            console2.log(string.concat(name, " already set, kept:"), live);
            return;
        }
        if (!guard.hasRole(guard.CONFIG_MANAGER_ROLE(), sender)) {
            console2.log(
                string.concat(name, " unset; broadcaster lacks CONFIG_MANAGER_ROLE. Submit to"), address(guard)
            );
            console2.logBytes(abi.encodeCall(guard.setAddress, (key, value)));
            return;
        }
        guard.setAddress(key, value);
        console2.log(string.concat(name, " set"), value);
    }
}
