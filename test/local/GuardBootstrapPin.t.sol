// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BittyV1GuardBootstrap} from "../../src/BittyV1GuardBootstrap.sol";
import {DeployGuard} from "../../script/DeployGuard.sol";
import {GUARD_BOOTSTRAP, GUARD_BOOTSTRAP_INITCODE} from "../../script/GuardBootstrapInitCode.sol";

/**
 *  @dev Reads DeployGuard's pinned constants, so the test checks the values the deploy really uses.
 */
contract DeployGuardConstants is DeployGuard {
    function proxyInitCodeHash() external pure returns (bytes32) {
        return GUARD_PROXY_INITCODE_HASH;
    }

    function salt() external pure returns (bytes32) {
        return GUARD_SALT;
    }

    function expectedGuard() external pure returns (address) {
        return EXPECTED_GUARD;
    }
}

/**
 * @dev The guard bootstrap is deployed from pinned bytes, not compiled, so that its metadata hash - and
 *      with it the guard's address - cannot move. These tests hold the pin to two things: that it
 *      still lands the guard where it lives, and that its code is still what the source compiles to.
 */
contract GuardBootstrapPinTest is Test {
    address constant SIMPLE_CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant IMMUTABLE_CREATE2 = 0x0000000000FFe8B47B3e2130213B802212439497;

    function test_pinnedBootstrapLandsTheLiveGuard() public {
        DeployGuardConstants c = new DeployGuardConstants();

        assertEq(
            vm.computeCreate2Address(bytes32(0), keccak256(GUARD_BOOTSTRAP_INITCODE), SIMPLE_CREATE2), GUARD_BOOTSTRAP
        );

        bytes memory proxyInit =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(GUARD_BOOTSTRAP, bytes("")));
        assertEq(keccak256(proxyInit), c.proxyInitCodeHash(), "proxy init code");
        assertEq(vm.computeCreate2Address(c.salt(), keccak256(proxyInit), IMMUTABLE_CREATE2), c.expectedGuard());
    }

    /**
     * @dev Only the trailing CBOR metadata may differ: an edit that changes what the bootstrap DOES
     *      fails here, and needs a deliberate new bootstrap, salt and guard address.
     */
    function test_pinnedBootstrapMatchesTheSourceButForMetadata() public pure {
        assertEq(_stripMetadata(GUARD_BOOTSTRAP_INITCODE), _stripMetadata(type(BittyV1GuardBootstrap).creationCode));
    }

    /**
     * @dev Drops solc's trailing CBOR blob, whose length is the code's last two bytes.
     */
    function _stripMetadata(bytes memory code) private pure returns (bytes memory out) {
        uint256 n = code.length;
        uint256 cbor = (uint256(uint8(code[n - 2])) << 8) | uint8(code[n - 1]);
        out = new bytes(n - cbor - 2);
        for (uint256 i; i < out.length; ++i) {
            out[i] = code[i];
        }
    }
}
