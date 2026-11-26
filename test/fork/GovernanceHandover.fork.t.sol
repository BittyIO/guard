// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {CFG_OWNER} from "../../src/interfaces/IBittyV1Guard.sol";
import {TimelockHandover} from "../../script/governance/TimelockHandover.sol";

interface IOwned {
    function owner() external view returns (address);
}

/**
 * The Sepolia handover rehearsed on the live guard, with the same {TimelockHandover} code the script
 * broadcasts: the deployer ends up driving a one-minute timelock, holds nothing on the guard directly,
 * and every guard call waits the delay.
 */
contract GovernanceHandoverForkTest is Test, TimelockHandover {
    address constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;
    address constant FORWARDER = 0xD6013C5e339cd3546c0c7E86c306554a63FbAa6F;
    bytes32 constant SOME_KEY = keccak256("bitty.test.handover");

    TimelockController tl;

    function setUp() public {
        vm.createSelectFork("https://ethereum-sepolia-rpc.publicnode.com");
        vm.rollFork(block.number - 5);
        require(GUARD.defaultAdmin() == DEPLOYER, "fork: the Sepolia guard admin is no longer the deployer");
        vm.startPrank(DEPLOYER, DEPLOYER);
        tl = TimelockController(payable(_handover(DEPLOYER)));
        vm.stopPrank();
    }

    function _schedule(address to, bytes memory data, bytes32 salt) internal returns (bytes32 id) {
        id = tl.hashOperation(to, 0, data, bytes32(0), salt);
        vm.prank(DEPLOYER);
        tl.schedule(to, 0, data, bytes32(0), salt, 1 minutes);
    }

    function _execute(address to, bytes memory data, bytes32 salt) internal {
        vm.prank(DEPLOYER);
        tl.execute(to, 0, data, bytes32(0), salt);
    }

    function _acceptAdmin() internal {
        (, uint48 acceptFrom) = GUARD.pendingDefaultAdmin();
        vm.warp(acceptFrom + 1);
        bytes memory data = abi.encodeCall(GUARD.acceptDefaultAdminTransfer, ());
        _schedule(address(GUARD), data, 0);
        vm.warp(block.timestamp + 1 minutes);
        _execute(address(GUARD), data, 0);
    }

    function test_handoverMovesEveryDirectPower() public view {
        assertEq(tl.getMinDelay(), 1 minutes);
        assertEq(GUARD.getAddress(CFG_OWNER), address(tl));
        assertEq(IOwned(FORWARDER).owner(), address(tl), "the forwarder follows CFG_OWNER");
        bytes32[4] memory roles = _managerRoles();
        for (uint256 i; i < roles.length; ++i) {
            assertTrue(GUARD.hasRole(roles[i], address(tl)));
            assertFalse(GUARD.hasRole(roles[i], DEPLOYER));
        }
        (address pending,) = GUARD.pendingDefaultAdmin();
        assertEq(pending, address(tl));
        assertFalse(_checkHandover(DEPLOYER, address(tl)), "pending until the timelock accepts");
    }

    function test_deployerCannotCallTheGuardDirectly() public {
        bytes32 role = GUARD.CONFIG_MANAGER_ROLE();
        vm.prank(DEPLOYER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, DEPLOYER, role)
        );
        GUARD.setUint(SOME_KEY, 1);
    }

    function test_acceptAdminCompletesTheHandover() public {
        _acceptAdmin();
        assertEq(GUARD.defaultAdmin(), address(tl));
        assertTrue(_checkHandover(DEPLOYER, address(tl)));

        // the deployer can no longer grant itself a role back
        bytes32 role = GUARD.CONFIG_MANAGER_ROLE();
        vm.prank(DEPLOYER);
        vm.expectRevert();
        GUARD.grantRole(role, DEPLOYER);
    }

    function test_guardCallWaitsTheDelay() public {
        bytes memory data = abi.encodeCall(GUARD.setUint, (SOME_KEY, 7));
        bytes32 id = _schedule(address(GUARD), data, 0);

        vm.warp(block.timestamp + 1 minutes - 1);
        vm.prank(DEPLOYER);
        vm.expectRevert(); // TimelockUnexpectedOperationState: not ready yet
        tl.execute(address(GUARD), 0, data, bytes32(0), 0);

        vm.warp(block.timestamp + 1);
        assertTrue(tl.isOperationReady(id));
        _execute(address(GUARD), data, 0);
        assertEq(GUARD.getUint(SOME_KEY), 7);
    }

    function test_scheduleBelowTheDelayReverts() public {
        bytes memory data = abi.encodeCall(GUARD.setUint, (SOME_KEY, 7));
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, 59, 60));
        tl.schedule(address(GUARD), 0, data, bytes32(0), 0, 59);
    }

    function test_onlyTheDeployerProposesAndExecutes() public {
        address stranger = makeAddr("stranger");
        bytes memory data = abi.encodeCall(GUARD.setUint, (SOME_KEY, 7));
        vm.prank(stranger);
        vm.expectRevert();
        tl.schedule(address(GUARD), 0, data, bytes32(0), 0, 1 minutes);

        _schedule(address(GUARD), data, 0);
        vm.warp(block.timestamp + 1 minutes);
        vm.prank(stranger);
        vm.expectRevert();
        tl.execute(address(GUARD), 0, data, bytes32(0), 0);
    }

    function test_deployerCanCancel() public {
        bytes memory data = abi.encodeCall(GUARD.setUint, (SOME_KEY, 7));
        bytes32 id = _schedule(address(GUARD), data, 0);
        vm.prank(DEPLOYER);
        tl.cancel(id);
        vm.warp(block.timestamp + 1 minutes);
        vm.prank(DEPLOYER);
        vm.expectRevert();
        tl.execute(address(GUARD), 0, data, bytes32(0), 0);
    }

    function test_delayChangesOnlyThroughTheTimelock() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, DEPLOYER));
        tl.updateDelay(0);
    }

    function test_guardUpgradeGoesThroughTheTimelock() public {
        _acceptAdmin();
        vm.prank(DEPLOYER);
        vm.expectRevert();
        GUARD.upgradeToAndCall(address(0xdead), "");
    }

    function test_rerunChangesNothing() public {
        vm.startPrank(DEPLOYER, DEPLOYER);
        assertEq(_handover(DEPLOYER), address(tl));
        vm.stopPrank();
        _acceptAdmin();
        vm.startPrank(DEPLOYER, DEPLOYER);
        assertEq(_handover(DEPLOYER), address(tl), "a run after the acceptance is a no-op");
        vm.stopPrank();
    }

    function test_otherChainsHaveNoDelay() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(HandoverChainHasNoDelay.selector, 1));
        this.delay();
    }

    function delay() external view returns (uint256) {
        return _timelockDelay();
    }
}
