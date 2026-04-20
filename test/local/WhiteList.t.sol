// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import "forge-std/console.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {WhiteList} from "../../src/WhiteList.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {AMMProviderShouldNotBeAllRemoved} from "../../src/interfaces/IWhiteList.sol";

contract WhiteListTest is Test {
    WhiteList public whiteList;
    address public protocolOwner;
    address public ammProvider;
    address public lendingProvider;
    address public stakingProvider;
    address public intentProvider;
    MockERC20 public mockWETH;
    MockERC20 public mockWBTC;
    MockERC20 public mockUSDT;
    MockERC20 public mockUSDC;
    address[] public assets;
    address[] public stableCoins;
    address[] public lendingProviders;
    address[] public stakingProviders;
    address[] public ammProviders;
    address[] public intentProviders;

    function setUp() public {
        protocolOwner = makeAddr("protocolOwner");
        ammProvider = makeAddr("ammProvider");
        lendingProvider = makeAddr("lendingProvider");
        stakingProvider = makeAddr("stakingProvider");
        intentProvider = makeAddr("intentProvider");
        mockWETH = new MockERC20("WETH", "WETH", 18);
        mockWBTC = new MockERC20("WBTC", "WBTC", 8);
        mockUSDT = new MockERC20("USDT", "USDT", 6);
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        // `WhiteList` grants `DEFAULT_ADMIN_ROLE` to `tx.origin`; align origin with a fixed admin for stable tests.
        address deployAdmin = makeAddr("deployAdmin");
        vm.startPrank(deployAdmin, deployAdmin);
        whiteList = new WhiteList();
        vm.stopPrank();
        vm.startPrank(deployAdmin);
        whiteList.grantRole(whiteList.ASSET_MANAGER_ROLE(), protocolOwner);
        whiteList.grantRole(whiteList.STABLE_COIN_MANAGER_ROLE(), protocolOwner);
        whiteList.grantRole(whiteList.LENDING_MANAGER_ROLE(), protocolOwner);
        whiteList.grantRole(whiteList.STAKING_MANAGER_ROLE(), protocolOwner);
        whiteList.grantRole(whiteList.AMM_MANAGER_ROLE(), protocolOwner);
        whiteList.grantRole(whiteList.INTENT_MANAGER_ROLE(), protocolOwner);
        vm.stopPrank();
        assets = new address[](2);
        assets[0] = address(mockWETH);
        assets[1] = address(mockWBTC);
        stableCoins = new address[](2);
        stableCoins[0] = address(mockUSDT);
        stableCoins[1] = address(mockUSDC);
        lendingProviders = new address[](1);
        lendingProviders[0] = lendingProvider;
        stakingProviders = new address[](1);
        stakingProviders[0] = stakingProvider;
        ammProviders = new address[](1);
        ammProviders[0] = ammProvider;
        intentProviders = new address[](1);
        intentProviders[0] = intentProvider;
    }

    function test_AddWhiteListedAssets() public {
        vm.prank(protocolOwner);
        whiteList.addAssets(assets);
        assertTrue(whiteList.isAssetWhiteListed(address(mockWETH)));
        assertTrue(whiteList.isAssetWhiteListed(address(mockWBTC)));
    }

    function test_RemoveAssets() public {
        vm.prank(protocolOwner);
        whiteList.removeAssets(assets);
        assertFalse(whiteList.isAssetWhiteListed(address(mockWETH)));
        assertFalse(whiteList.isAssetWhiteListed(address(mockWBTC)));
    }

    function test_AddStableCoins() public {
        vm.prank(protocolOwner);
        whiteList.addStableCoins(stableCoins);
        assertTrue(whiteList.isStableCoinWhiteListed(address(mockUSDT)));
        assertTrue(whiteList.isStableCoinWhiteListed(address(mockUSDC)));
    }

    function test_RemoveStableCoins() public {
        vm.prank(protocolOwner);
        whiteList.removeStableCoins(stableCoins);
        assertFalse(whiteList.isStableCoinWhiteListed(address(mockUSDT)));
        assertFalse(whiteList.isStableCoinWhiteListed(address(mockUSDC)));
    }

    function test_AddLendingProviders() public {
        vm.prank(protocolOwner);
        whiteList.addLendingProviders(lendingProviders);
        assertTrue(whiteList.isLendingProviderWhiteListed(lendingProvider));
    }

    function test_DeprecateLendingProviders() public {
        vm.prank(protocolOwner);
        whiteList.deprecateLendingProviders(lendingProviders);
        assertFalse(whiteList.isLendingProviderWhiteListed(lendingProvider));
        assertTrue(whiteList.isLendingProviderDeprecated(lendingProvider));
    }

    function test_AddStakingProviders() public {
        vm.prank(protocolOwner);
        whiteList.addStakingProviders(stakingProviders);
        assertTrue(whiteList.isStakingProviderWhiteListed(stakingProvider));
        assertFalse(whiteList.isStakingProviderDeprecated(stakingProvider));
    }

    function test_DeprecateStakingProviders() public {
        vm.prank(protocolOwner);
        whiteList.deprecateStakingProviders(stakingProviders);
        assertFalse(whiteList.isStakingProviderWhiteListed(stakingProvider));
        assertTrue(whiteList.isStakingProviderDeprecated(stakingProvider));
    }

    function test_AddAMMProviders() public {
        vm.prank(protocolOwner);
        whiteList.addAMMProviders(ammProviders);
        assertTrue(whiteList.isAMMProviderWhiteListed(ammProvider));
    }

    function test_AddIntentProviders() public {
        vm.prank(protocolOwner);
        whiteList.addIntentProviders(intentProviders);
        assertTrue(whiteList.isIntentProviderWhiteListed(intentProvider));
    }

    function test_DeprecateIntentProviders() public {
        vm.prank(protocolOwner);
        whiteList.addIntentProviders(intentProviders);
        assertTrue(whiteList.isIntentProviderWhiteListed(intentProvider));
        vm.prank(protocolOwner);
        whiteList.deprecateIntentProviders(intentProviders);
        assertFalse(whiteList.isIntentProviderWhiteListed(intentProvider));
        assertTrue(whiteList.isIntentProviderDeprecated(intentProvider));
    }

    function test_RemoveAMMProvidersFailedWhenAllRemoved() public {
        address[] memory ammProviderAddresses = new address[](1);
        ammProviderAddresses[0] = ammProvider;
        vm.prank(protocolOwner);
        vm.expectRevert(AMMProviderShouldNotBeAllRemoved.selector);
        whiteList.removeAMMProviders(ammProviderAddresses);
    }

    function test_RemoveAMMProvidersShouldBeFine() public {
        address[] memory ammProviderAddresses = new address[](1);
        ammProviderAddresses[0] = ammProvider;
        address[] memory invalidAMMProviders = new address[](1);
        address invalidAMMProvider = makeAddr("InvalidAMMProvider");
        invalidAMMProviders[0] = invalidAMMProvider;
        vm.prank(protocolOwner);
        whiteList.addAMMProviders(invalidAMMProviders);
        vm.prank(protocolOwner);
        whiteList.addAMMProviders(ammProviderAddresses);
        vm.prank(protocolOwner);
        whiteList.removeAMMProviders(invalidAMMProviders);
        assertTrue(whiteList.isAMMProviderWhiteListed(ammProvider));
        assertFalse(whiteList.isAMMProviderWhiteListed(invalidAMMProvider));
    }

    function test_AddWhiteListedNeedToRemoveDeprecated() public {
        vm.prank(protocolOwner);
        whiteList.addLendingProviders(lendingProviders);
        assertTrue(whiteList.isLendingProviderWhiteListed(lendingProvider));
        vm.prank(protocolOwner);
        whiteList.deprecateLendingProviders(lendingProviders);
        assertFalse(whiteList.isLendingProviderWhiteListed(lendingProvider));
        assertTrue(whiteList.isLendingProviderDeprecated(lendingProvider));
        vm.prank(protocolOwner);
        whiteList.addLendingProviders(lendingProviders);
        assertTrue(whiteList.isLendingProviderWhiteListed(lendingProvider));
        assertFalse(whiteList.isLendingProviderDeprecated(lendingProvider));
    }

    function test_AddIntentProvidersClearsDeprecatedFlag() public {
        vm.prank(protocolOwner);
        whiteList.addIntentProviders(intentProviders);
        assertTrue(whiteList.isIntentProviderWhiteListed(intentProvider));
        assertFalse(whiteList.isIntentProviderDeprecated(intentProvider));
        vm.prank(protocolOwner);
        whiteList.deprecateIntentProviders(intentProviders);
        assertFalse(whiteList.isIntentProviderWhiteListed(intentProvider));
        assertTrue(whiteList.isIntentProviderDeprecated(intentProvider));
        vm.prank(protocolOwner);
        whiteList.addIntentProviders(intentProviders);
        assertTrue(whiteList.isIntentProviderWhiteListed(intentProvider));
        assertFalse(whiteList.isIntentProviderDeprecated(intentProvider));
    }

    function test_GetWhiteListInitCode() public pure {
        bytes memory bytecode = type(WhiteList).creationCode;
        console.logBytes32(keccak256(bytecode));
    }
}
