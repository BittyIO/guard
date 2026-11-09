// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

error Create2Failed();

/**
 * @title BittyTronCreate2Deployer
 * @notice TRON's stand-in for the EVM's canonical CREATE2 deployer (0x4e59…956C), which does not
 *         exist there: deploys `initCode` at the address CREATE2 gives `salt` and `initCode` here.
 * @dev The guard is the first Bitty contract on a TRON network, so this is deployed by the guard's
 *      TRON deploy (`tron/deploy.mjs`), and every later Bitty deploy on that network reuses it.
 *
 *      Permissionless, like the original. That is safe for the same reason it is on the EVM: every
 *      address is a pure function of the init code, so whoever sends a deployment can only put the
 *      exact contract the deploy expects there - the bootstraps then gate their one upgrade on the
 *      DEPLOYER themselves. A typed function rather than the original's raw calldata, so TronWeb can
 *      call it through an ABI.
 *
 *      Its own address is NOT reproducible across TRON networks: a top-level deployment's address is
 *      derived from the transaction, not a nonce. Every address below it is, given this one.
 */
contract BittyTronCreate2Deployer {
    event Deployed(address indexed deployed, bytes32 indexed salt);

    function deploy(bytes32 salt, bytes calldata initCode) external payable returns (address deployed) {
        bytes memory code = initCode;
        assembly ("memory-safe") {
            deployed := create2(callvalue(), add(code, 0x20), mload(code), salt)
        }
        if (deployed == address(0)) revert Create2Failed();
        emit Deployed(deployed, salt);
    }
}
