// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {DeployScript} from "./BaseDeploy.sol";
import {TimelockHandover} from "./governance/TimelockHandover.sol";

/**
 * @title GovernanceHandover
 * @notice Puts the deployer behind a timelock on one chain (see {TimelockHandover}). Sepolia only for
 *         now, with a one-minute delay; any other chain reverts.
 *
 *      Run (the sender must be the deployer, the current guard admin):
 *        forge script script/GovernanceHandover.s.sol:GovernanceHandover --sig "deploy(string)" sepolia \
 *          --private-key $PK --broadcast
 *
 *      Then, 7 days later, the timelock accepts the guard admin:
 *        script/governance/timelock.sh accept-admin sepolia
 *      and script/governance/check.sh sepolia prints PASS.
 *
 *      The timelock address is written to deployments/sepolia.toml as GOVERNANCE_TIMELOCK.
 */
contract GovernanceHandover is DeployScript, TimelockHandover {
    function deploy() public override {
        (, address sender,) = vm.readCallers();
        address timelock = _handover(sender);
        saveAddress("GOVERNANCE_TIMELOCK", timelock);
    }
}
