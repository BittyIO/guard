// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {BittyRegistry} from "../../src/BittyRegistry.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {AMMProtocolShouldNotBeAllRemoved} from "../../src/interfaces/IRegistry.sol";

contract BittyRegistryTest is Test {
    BittyRegistry public bittyRegistry;
    address public protocolOwner;
    address public ammProtocol;
    address public lendingProtocol;
    address public stakingProtocol;
    MockERC20 public mockWETH;
    MockERC20 public mockWBTC;
    MockERC20 public mockUSDT;
    MockERC20 public mockUSDC;
    address[] public assets;
    address[] public stableCoins;
    address[] public lendingProtocols;
    address[] public stakingProtocols;
    address[] public ammProtocols;

    function setUp() public {
        protocolOwner = makeAddr("protocolOwner");
        ammProtocol = makeAddr("ammProtocol");
        lendingProtocol = makeAddr("lendingProtocol");
        stakingProtocol = makeAddr("stakingProtocol");
        mockWETH = new MockERC20("WETH", "WETH", 18);
        mockWBTC = new MockERC20("WBTC", "WBTC", 8);
        mockUSDT = new MockERC20("USDT", "USDT", 6);
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        // `BittyRegistry` grants `DEFAULT_ADMIN_ROLE` to `tx.origin`; align origin with a fixed admin for stable tests.
        address deployAdmin = makeAddr("deployAdmin");
        vm.startPrank(deployAdmin, deployAdmin);
        bittyRegistry = new BittyRegistry();
        vm.stopPrank();
        vm.startPrank(deployAdmin);
        bittyRegistry.grantRole(bittyRegistry.ASSET_MANAGER_ROLE(), protocolOwner);
        bittyRegistry.grantRole(bittyRegistry.STABLE_COIN_MANAGER_ROLE(), protocolOwner);
        bittyRegistry.grantRole(bittyRegistry.LENDING_MANAGER_ROLE(), protocolOwner);
        bittyRegistry.grantRole(bittyRegistry.STAKING_MANAGER_ROLE(), protocolOwner);
        bittyRegistry.grantRole(bittyRegistry.AMM_MANAGER_ROLE(), protocolOwner);
        vm.stopPrank();
        assets = new address[](2);
        assets[0] = address(mockWETH);
        assets[1] = address(mockWBTC);
        stableCoins = new address[](2);
        stableCoins[0] = address(mockUSDT);
        stableCoins[1] = address(mockUSDC);
        lendingProtocols = new address[](1);
        lendingProtocols[0] = lendingProtocol;
        stakingProtocols = new address[](1);
        stakingProtocols[0] = stakingProtocol;
        ammProtocols = new address[](1);
        ammProtocols[0] = ammProtocol;
    }

    function test_AddRegisteredAssets() public {
        vm.prank(protocolOwner);
        bittyRegistry.addAssets(assets);
        assertTrue(bittyRegistry.isAssetRegistered(address(mockWETH)));
        assertTrue(bittyRegistry.isAssetRegistered(address(mockWBTC)));
    }

    function test_RemoveAssets() public {
        vm.prank(protocolOwner);
        bittyRegistry.removeAssets(assets);
        assertFalse(bittyRegistry.isAssetRegistered(address(mockWETH)));
        assertFalse(bittyRegistry.isAssetRegistered(address(mockWBTC)));
    }

    function test_AddStableCoins() public {
        vm.prank(protocolOwner);
        bittyRegistry.addStableCoins(stableCoins);
        assertTrue(bittyRegistry.isStableCoinRegistered(address(mockUSDT)));
        assertTrue(bittyRegistry.isStableCoinRegistered(address(mockUSDC)));
    }

    function test_RemoveStableCoins() public {
        vm.prank(protocolOwner);
        bittyRegistry.removeStableCoins(stableCoins);
        assertFalse(bittyRegistry.isStableCoinRegistered(address(mockUSDT)));
        assertFalse(bittyRegistry.isStableCoinRegistered(address(mockUSDC)));
    }

    function test_AddLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyRegistry.addLendingProtocols(lendingProtocols);
        assertTrue(bittyRegistry.isLendingProtocolRegistered(lendingProtocol));
    }

    function test_DeprecateLendingProtocols() public {
        vm.prank(protocolOwner);
        bittyRegistry.deprecateLendingProtocols(lendingProtocols);
        assertFalse(bittyRegistry.isLendingProtocolRegistered(lendingProtocol));
        assertTrue(bittyRegistry.isLendingProtocolDeprecated(lendingProtocol));
    }

    function test_AddStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyRegistry.addStakingProtocols(stakingProtocols);
        assertTrue(bittyRegistry.isStakingProtocolRegistered(stakingProtocol));
        assertFalse(bittyRegistry.isStakingProtocolDeprecated(stakingProtocol));
    }

    function test_DeprecateStakingProtocols() public {
        vm.prank(protocolOwner);
        bittyRegistry.deprecateStakingProtocols(stakingProtocols);
        assertFalse(bittyRegistry.isStakingProtocolRegistered(stakingProtocol));
        assertTrue(bittyRegistry.isStakingProtocolDeprecated(stakingProtocol));
    }

    function test_AddAMMProtocols() public {
        vm.prank(protocolOwner);
        bittyRegistry.addAMMProtocols(ammProtocols);
        assertTrue(bittyRegistry.isAMMProtocolRegistered(ammProtocol));
    }

    function test_RemoveAMMProtocolsFailedWhenAllRemoved() public {
        address[] memory ammProtocolAddresses = new address[](1);
        ammProtocolAddresses[0] = ammProtocol;
        vm.prank(protocolOwner);
        vm.expectRevert(AMMProtocolShouldNotBeAllRemoved.selector);
        bittyRegistry.removeAMMProtocols(ammProtocolAddresses);
    }

    function test_RemoveAMMProtocolsShouldBeFine() public {
        address[] memory ammProtocolAddresses = new address[](1);
        ammProtocolAddresses[0] = ammProtocol;
        address[] memory invalidAMMProtocols = new address[](1);
        address invalidAMMProtocol = makeAddr("InvalidAMMProtocol");
        invalidAMMProtocols[0] = invalidAMMProtocol;
        vm.prank(protocolOwner);
        bittyRegistry.addAMMProtocols(invalidAMMProtocols);
        vm.prank(protocolOwner);
        bittyRegistry.addAMMProtocols(ammProtocolAddresses);
        vm.prank(protocolOwner);
        bittyRegistry.removeAMMProtocols(invalidAMMProtocols);
        assertTrue(bittyRegistry.isAMMProtocolRegistered(ammProtocol));
        assertFalse(bittyRegistry.isAMMProtocolRegistered(invalidAMMProtocol));
    }

    function test_AddRegisteredNeedToRemoveDeprecated() public {
        vm.prank(protocolOwner);
        bittyRegistry.addLendingProtocols(lendingProtocols);
        assertTrue(bittyRegistry.isLendingProtocolRegistered(lendingProtocol));
        vm.prank(protocolOwner);
        bittyRegistry.deprecateLendingProtocols(lendingProtocols);
        assertFalse(bittyRegistry.isLendingProtocolRegistered(lendingProtocol));
        assertTrue(bittyRegistry.isLendingProtocolDeprecated(lendingProtocol));
        vm.prank(protocolOwner);
        bittyRegistry.addLendingProtocols(lendingProtocols);
        assertTrue(bittyRegistry.isLendingProtocolRegistered(lendingProtocol));
        assertFalse(bittyRegistry.isLendingProtocolDeprecated(lendingProtocol));
    }

    function test_GetBittyRegistryInitCode() public pure {
        bytes memory bytecode = type(BittyRegistry).creationCode;
        console.logBytes32(keccak256(bytecode));
    }
}
