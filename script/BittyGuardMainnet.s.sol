// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BittyGuard} from "../src/BittyGuard.sol";
import {DeployScript} from "./BaseDeploy.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deploymentAddress);
    function findCreate2Address(bytes32 salt, bytes calldata initCode) external view returns (address deploymentAddress);
    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address deploymentAddress);
}

contract Deploy is DeployScript {
    ImmutableCreate2Factory immutable factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 salt = 0x0000000000000000000000000000000000000000f6d2101661ce480001552144;

    function deploy() public override {
        bytes memory initCode = type(BittyGuard).creationCode;

        address bittyGuardAddress = factory.safeCreate2(salt, initCode);
        BittyGuard bittyGuard = BittyGuard(bittyGuardAddress);

        address[] memory assets = new address[](2);
        assets[0] = getAddress("WETH");
        assets[1] = getAddress("WBTC");

        address[] memory stableCoins = new address[](2);
        stableCoins[0] = getAddress("USDT");
        stableCoins[1] = getAddress("USDC");

        bittyGuard.initialize(
            assets, stableCoins, new address[](0), new address[](0), new address[](0), new address[](0)
        );

        console2.log("BittyGuard deployed at", address(bittyGuard));

        saveAddress("BITTY_GUARD", address(bittyGuard));
    }
}
