// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {PriceFeed, MarketTradeInfo, ASSET_STABLE_COIN} from "../../src/interfaces/IBittyV1Guard.sol";

/**
 * The 1.0.1 → 1.0.2 upgrade rehearsed on the live guard of each chain: everything 1.0.1 answers must
 * answer the same after it, and removal must then keep an asset sellable but not buyable (audit I-05)
 * on real state. A chain whose guard is not at 1.0.1 is skipped, as there is nothing to rehearse there.
 *
 * Forked a few blocks behind head: public RPCs balance across nodes, and a node that has not yet seen
 * the head block another one just reported fails the fork with "block not found".
 */
contract UpgradeToV102ForkTest is Test {
    BittyV1Guard constant GUARD = BittyV1Guard(0x000000000F5fcD35885BfE4c700042cE7cb39554);
    uint256 constant BLOCKS_BEHIND_HEAD = 5;
    /**
     * @dev Arbitrum and Robinhood Chain (an Arbitrum Orbit L2) make a block about every quarter second,
     *      and their public nodes prune state that recent, failing with "historical state is not
     *      available". Forked at head instead.
     */
    uint256 constant ORBIT_BLOCKS_BEHIND_HEAD = 0;

    struct Snapshot {
        address[] protocols;
        address[] deprecated;
        uint8[] protocolCategories;
        uint8[] assetCategories;
        bool[] assetRegistered;
        PriceFeed[] priceFeeds;
        address latestVault;
        address gasWrapped;
        address owner;
        address admin;
        address sequencerUptimeFeed;
    }

    function _snapshot(address[] memory assets) internal view returns (Snapshot memory s) {
        s.protocols = GUARD.getProtocols();
        s.deprecated = GUARD.getDeprecatedProtocols();
        s.protocolCategories = new uint8[](s.protocols.length);
        for (uint256 i; i < s.protocols.length; ++i) {
            s.protocolCategories[i] = GUARD.protocolCategory(s.protocols[i]);
        }
        s.assetCategories = new uint8[](assets.length);
        s.assetRegistered = new bool[](assets.length);
        s.priceFeeds = new PriceFeed[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            s.assetCategories[i] = GUARD.assetCategory(assets[i]);
            s.assetRegistered[i] = GUARD.isAssetRegistered(assets[i]);
            s.priceFeeds[i] = GUARD.priceFeed(assets[i]);
        }
        s.latestVault = GUARD.latestImplementation(1);
        s.gasWrapped = GUARD.getAddress(keccak256("bitty.gasWrapped"));
        s.owner = GUARD.getAddress(keccak256("bitty.owner"));
        s.admin = GUARD.defaultAdmin();
        s.sequencerUptimeFeed = GUARD.sequencerUptimeFeed();
    }

    /**
     * @param assets Registered assets to snapshot; `assets[0]` must be a non-stablecoin and
     *        `assets[assets.length - 1]` a stablecoin, both registered.
     */
    function _rehearse(string memory rpc, address[] memory assets) internal {
        _rehearse(rpc, assets, BLOCKS_BEHIND_HEAD);
    }

    function _rehearse(string memory rpc, address[] memory assets, uint256 blocksBehind) internal {
        vm.createSelectFork(rpc);
        if (blocksBehind != 0) vm.rollFork(block.number - blocksBehind);
        if (keccak256(bytes(GUARD.versionName())) != keccak256("1.0.1")) vm.skip(true);
        Snapshot memory before = _snapshot(assets);

        BittyV1Guard next = new BittyV1Guard();
        vm.prank(before.admin);
        UUPSUpgradeable(address(GUARD)).upgradeToAndCall(address(next), "");

        assertEq(GUARD.versionName(), "1.0.2");
        Snapshot memory afterwards = _snapshot(assets);
        assertEq(keccak256(abi.encode(afterwards)), keccak256(abi.encode(before)), "1.0.1 state reads the same");
        for (uint256 i; i < assets.length; ++i) {
            assertEq(GUARD.removedAssetCategory(assets[i]), 0, "the new slot starts empty");
        }

        _rehearseRemoval(before, assets);
    }

    function _rehearseRemoval(Snapshot memory before, address[] memory assets) internal {
        address crypto = assets[0];
        address stable = assets[assets.length - 1];
        uint8 cryptoCategory = before.assetCategories[0];
        uint8 stableCategory = before.assetCategories[assets.length - 1];
        assertTrue(cryptoCategory != 0 && cryptoCategory & ASSET_STABLE_COIN == 0, "assets[0] is a live non-stable");
        assertTrue(stableCategory & ASSET_STABLE_COIN != 0, "the last asset is a live stablecoin");

        vm.startPrank(before.admin);
        GUARD.grantRole(GUARD.ASSET_MANAGER_ROLE(), address(this));
        vm.stopPrank();

        GUARD.removeAssets(_one(crypto));
        assertFalse(GUARD.isAssetRegistered(crypto));
        assertEq(GUARD.assetCategory(crypto), 0);
        assertEq(GUARD.removedAssetCategory(crypto), cryptoCategory);

        MarketTradeInfo memory sell = GUARD.marketTradeInfo(address(0), crypto, stable);
        assertEq(sell.sellCategory, cryptoCategory, "a removed asset is reported for the sold leg");
        assertEq(sell.sellFeed.feed, before.priceFeeds[0].feed, "with the feed it already had");
        MarketTradeInfo memory buy = GUARD.marketTradeInfo(address(0), stable, crypto);
        assertEq(buy.buyCategory, 0, "and never for the bought leg");

        GUARD.removeAssets(_one(stable));
        assertEq(GUARD.removedAssetCategory(stable), stableCategory & ~ASSET_STABLE_COIN, "no longer a dollar");
    }

    function _one(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    function test_ethereum() public {
        address[] memory assets = new address[](4);
        assets[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        assets[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        assets[2] = 0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c; // AAPLon
        assets[3] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        _rehearse("https://ethereum-rpc.publicnode.com", assets);
    }

    function test_base() public {
        address[] memory assets = new address[](3);
        assets[0] = 0x4200000000000000000000000000000000000006; // WETH
        assets[1] = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbBTC
        assets[2] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
        _rehearse("https://base.gateway.tenderly.co", assets);
    }

    function test_arbitrum() public {
        address[] memory assets = new address[](3);
        assets[0] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        assets[1] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        assets[2] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        _rehearse("https://arb1.arbitrum.io/rpc", assets, ORBIT_BLOCKS_BEHIND_HEAD);
    }

    function test_robinhood() public {
        address[] memory assets = new address[](3);
        assets[0] = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73; // WETH
        assets[1] = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC; // NVDA
        assets[2] = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // USDG
        _rehearse("https://rpc.mainnet.chain.robinhood.com", assets, ORBIT_BLOCKS_BEHIND_HEAD);
    }
}
