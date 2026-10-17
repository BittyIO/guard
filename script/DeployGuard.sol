// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {console2} from "forge-std/console2.sol";
import {BittyV1Guard} from "../src/BittyV1Guard.sol";
import {IBittyV1Guard, IMPLEMENTATION_VAULT, CFG_OWNER, CFG_GAS_WRAPPED} from "../src/interfaces/IBittyV1Guard.sol";
import {GUARD_BOOTSTRAP, GUARD_BOOTSTRAP_INITCODE} from "./GuardBootstrapInitCode.sol";
import {DeployScript} from "./BaseDeploy.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
}

/**
 * @title DeployGuard
 * @notice The one guard-deploying step, shared by the per-chain scripts.
 *
 * @dev The chain scripts differ only in WHICH assets and protocols they register - the deploy itself
 *      is identical everywhere, and must stay that way: the salt and the bootstrap are what put the
 *      guard at the same address on every chain, so a chain holding its own copy of either is a bug
 *      waiting to happen rather than a chain-specific choice. Keeping them here means a chain script
 *      states its registry and nothing else.
 *
 *      Every step is RE-RUNNABLE: create, upgrade and initialize are each skipped once done, so
 *      finishing an interrupted deploy is just running it again, and re-running a finished one
 *      reports that there is nothing left to do rather than reverting.
 */
abstract contract DeployGuard is DeployScript {
    ImmutableCreate2Factory internal constant IMMUTABLE_CREATE2 =
        ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 internal constant GUARD_SALT = 0x12ee2de7bf086388b1d560eb95e7191edfab9823345ab48359c214008f709d89;

    bytes32 internal constant GUARD_PROXY_INITCODE_HASH =
        0x477f8905cc00717c5d18e3e6a15f5e614214d1d59dddc9f22e2a37683ab653e0;

    address internal constant EXPECTED_GUARD = 0x000000000F5fcD35885BfE4c700042cE7cb39554;

    address[] private _assets;
    uint8[] private _assetCategories;
    address[] private _protocols;
    uint8[] private _protocolCategories;

    function _asset(string memory key, uint8 category) internal {
        _assets.push(getAddress(key));
        _assetCategories.push(category);
    }

    function _protocol(string memory key, uint8 category) internal {
        _protocols.push(getAddress(key));
        _protocolCategories.push(category);
    }

    function _deployGuard() internal returns (address guard) {
        address guardImpl = deployAtSaltZero(type(BittyV1Guard).creationCode);

        address bootstrap = deployAtSaltZero(GUARD_BOOTSTRAP_INITCODE);
        require(bootstrap == GUARD_BOOTSTRAP, "DeployGuard: bootstrap address drifted");
        bytes memory initCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(bootstrap, bytes("")));
        console2.log("proxy initCode hash (mine the salt against this):");
        console2.logBytes32(keccak256(initCode));

        require(
            keccak256(initCode) == GUARD_PROXY_INITCODE_HASH,
            "DeployGuard: proxy init code drifted - rebuild with the pinned toolchain or re-mine the salt"
        );

        guard = create2Address(address(IMMUTABLE_CREATE2), GUARD_SALT, initCode);
        require(guard == EXPECTED_GUARD, "DeployGuard: guard address drifted");
        if (guard.code.length == 0) IMMUTABLE_CREATE2.safeCreate2(GUARD_SALT, initCode);

        if (address(uint160(uint256(vm.load(guard, ERC1967Utils.IMPLEMENTATION_SLOT)))) != guardImpl) {
            UUPSUpgradeable(guard).upgradeToAndCall(guardImpl, "");
            console2.log("guard moved to implementation", guardImpl);
        }
        if (BittyV1Guard(guard).defaultAdmin() == address(0)) {
            BittyV1Guard(guard).initialize(_assets, _assetCategories, _protocols, _protocolCategories);
            console2.log("guard initialized with assets/protocols:", _assets.length, _protocols.length);
        }

        console2.log("guard implementation at ", guardImpl);
        console2.log("BittyV1Guard deployed at", guard);
        saveAddress("BITTY_GUARD", guard);
    }

    function _configure(address guardAddress) internal {
        IBittyV1Guard guard = IBittyV1Guard(guardAddress);
        address owner = getAddress("DEPLOYER");
        if (guard.getAddress(CFG_OWNER) != owner) {
            guard.setAddress(CFG_OWNER, owner);
            console2.log("CFG_OWNER set", owner);
        }
        address gasWrapped = getAddress("WETH");
        if (guard.getAddress(CFG_GAS_WRAPPED) != gasWrapped) {
            guard.setAddress(CFG_GAS_WRAPPED, gasWrapped);
            console2.log("CFG_GAS_WRAPPED set", gasWrapped);
        }
    }
}
