// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {CFG_OWNER} from "../../src/interfaces/IBittyV1Guard.sol";

/**
 * @title TimelockHandover
 * @notice Moves every Bitty-level power on one chain from the deployer EOA to a TimelockController
 *         that the same deployer drives: it proposes, executes and cancels, but every call now waits
 *         the timelock's delay before it can run. Shared by {GovernanceHandover} (the broadcast) and
 *         the fork test, so what is tested is what is sent.
 *
 * @dev The powers moved, all of which the deployer holds directly today:
 *        - CFG_OWNER, the owner of the vault factory, the forwarder and the auto-yield keeper. The
 *          forwarder is the one vaults trust to name their caller, so its upgrade is the widest power
 *          of all; this switch takes effect at once.
 *        - the guard's four manager roles, granted to the timelock and then renounced by the deployer.
 *        - the guard admin (upgrades the guard, grants roles): begun here, and finished only after the
 *          guard's own 7-day admin-transfer wait, when the timelock calls acceptDefaultAdminTransfer().
 *
 *      Until that acceptance the deployer is STILL the guard admin and could undo all of the above, so
 *      the handover is complete only once {_checkHandover} passes with the admin on the timelock.
 *
 *      The timelock is its own admin (constructor admin = address(0)), so its delay and its roles can
 *      only be changed by a call that itself waited the delay.
 */
abstract contract TimelockHandover {
    BittyV1Guard internal constant GUARD = BittyV1Guard(0x000000000F5fcD35885BfE4c700042cE7cb39554);
    address internal constant HANDOVER_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    /// @dev Sepolia only, to rehearse the flow quickly. Mainnet chains get their own, much longer delay.
    uint256 internal constant SEPOLIA_TIMELOCK_DELAY = 1 minutes;

    error HandoverChainHasNoDelay(uint256 chainId);

    /**
     * @dev The delay for this chain. Any chain without one reverts, so a run against a mainnet cannot
     *      hand it a one-minute timelock by mistake.
     */
    function _timelockDelay() internal view returns (uint256) {
        if (block.chainid == SEPOLIA_CHAIN_ID) return SEPOLIA_TIMELOCK_DELAY;
        revert HandoverChainHasNoDelay(block.chainid);
    }

    function _managerRoles() internal view returns (bytes32[4] memory) {
        return [
            GUARD.ASSET_MANAGER_ROLE(),
            GUARD.PROTOCOL_MANAGER_ROLE(),
            GUARD.IMPLEMENTATION_MANAGER_ROLE(),
            GUARD.CONFIG_MANAGER_ROLE()
        ];
    }

    /**
     * @dev The timelock's init code: the deployer alone proposes (which also makes it a canceller) and
     *      executes, and no admin. Deployed by CREATE2 at salt 0, so the address follows from the
     *      deployer and the delay alone and is the same on every chain given the same two.
     */
    function _timelockInitCode(address deployer, uint256 delay) internal pure returns (bytes memory) {
        address[] memory members = new address[](1);
        members[0] = deployer;
        return abi.encodePacked(type(TimelockController).creationCode, abi.encode(delay, members, members, address(0)));
    }

    function _timelockAddress(address deployer, uint256 delay) internal pure returns (address) {
        bytes32 h = keccak256(
            abi.encodePacked(bytes1(0xff), HANDOVER_CREATE2, bytes32(0), keccak256(_timelockInitCode(deployer, delay)))
        );
        return address(uint160(uint256(h)));
    }

    /**
     * @dev Every step is skipped when already done, so an interrupted run is finished by running it
     *      again, and a run after the admin has been accepted changes nothing. All calls must come from
     *      `deployer`.
     */
    function _handover(address deployer) internal returns (address timelock) {
        uint256 delay = _timelockDelay();
        timelock = _timelockAddress(deployer, delay);
        address admin = GUARD.defaultAdmin();
        require(
            admin == deployer || admin == timelock,
            "TimelockHandover: the guard admin is neither the deployer nor the timelock"
        );

        // 1. the timelock
        if (timelock.code.length == 0) {
            (bool ok, bytes memory ret) =
                HANDOVER_CREATE2.call(abi.encodePacked(bytes32(0), _timelockInitCode(deployer, delay)));
            require(
                ok && ret.length == 20 && address(bytes20(ret)) == timelock, "TimelockHandover: timelock deploy failed"
            );
            console2.log("timelock deployed      ", timelock);
        } else {
            console2.log("timelock already at    ", timelock);
        }

        bytes32[4] memory roles = _managerRoles();

        // 2. CFG_OWNER: factory, forwarder and keeper owner, switched at once. Needs CONFIG_MANAGER_ROLE,
        //    so it runs before step 5 renounces it.
        if (GUARD.getAddress(CFG_OWNER) != timelock) {
            GUARD.setAddress(CFG_OWNER, timelock);
            console2.log("CFG_OWNER              -> timelock");
        }

        // 3. the four manager roles, to the timelock (needs the guard admin)
        for (uint256 i; i < roles.length; ++i) {
            if (!GUARD.hasRole(roles[i], timelock)) {
                GUARD.grantRole(roles[i], timelock);
                console2.log("role granted to timelock", uint256(roles[i]));
            }
        }

        // 4. the guard admin: begun now, accepted by the timelock after the guard's 7-day wait
        if (admin == deployer) {
            (address pending,) = GUARD.pendingDefaultAdmin();
            if (pending != timelock) {
                GUARD.beginDefaultAdminTransfer(timelock);
                console2.log("guard admin transfer   begun; the timelock accepts it after 7 days");
            }
        }

        // 5. the deployer gives up its four manager roles
        for (uint256 i; i < roles.length; ++i) {
            if (GUARD.hasRole(roles[i], deployer)) {
                GUARD.renounceRole(roles[i], deployer);
                console2.log("role renounced by deployer", uint256(roles[i]));
            }
        }

        _checkHandover(deployer, timelock);
    }

    /**
     * @dev The end state. Returns true once the guard admin has been accepted by the timelock (the
     *      handover is complete); false while the transfer is still pending (the deployer is still
     *      admin). Anything else reverts.
     */
    function _checkHandover(address deployer, address timelock) internal view returns (bool complete) {
        TimelockController t = TimelockController(payable(timelock));
        require(t.getMinDelay() == _timelockDelay(), "check: timelock delay");
        require(t.hasRole(t.PROPOSER_ROLE(), deployer), "check: deployer cannot propose");
        require(t.hasRole(t.EXECUTOR_ROLE(), deployer), "check: deployer cannot execute");
        require(t.hasRole(t.CANCELLER_ROLE(), deployer), "check: deployer cannot cancel");
        require(!t.hasRole(t.DEFAULT_ADMIN_ROLE(), deployer), "check: deployer administers the timelock");
        require(t.hasRole(t.DEFAULT_ADMIN_ROLE(), timelock), "check: timelock is not its own admin");

        require(GUARD.getAddress(CFG_OWNER) == timelock, "check: CFG_OWNER is not the timelock");
        bytes32[4] memory roles = _managerRoles();
        for (uint256 i; i < roles.length; ++i) {
            require(GUARD.hasRole(roles[i], timelock), "check: timelock is missing a manager role");
            require(!GUARD.hasRole(roles[i], deployer), "check: deployer still holds a manager role");
        }

        if (GUARD.defaultAdmin() == timelock) {
            console2.log("handover COMPLETE: the timelock is the guard admin");
            return true;
        }
        (address pending, uint48 acceptFrom) = GUARD.pendingDefaultAdmin();
        require(
            GUARD.defaultAdmin() == deployer && pending == timelock,
            "check: admin transfer to the timelock is not pending"
        );
        console2.log(
            "handover PENDING: the deployer is still the guard admin until the timelock accepts, from", acceptFrom
        );
        return false;
    }
}
