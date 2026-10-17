// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BittyV1Guard} from "../../src/BittyV1Guard.sol";
import {PriceFeed, MarketTradeInfo} from "../../src/interfaces/IBittyV1Guard.sol";

/**
 * The 1.0.0 → 1.0.1 upgrade rehearsed on the live guard of each chain: everything 1.0.0 answers must
 * answer the same after it, and the new price-feed surface must work on top. Public RPCs, latest block.
 */
contract UpgradeToV101ForkTest is Test {
    BittyV1Guard constant GUARD = BittyV1Guard(0x000000000F5fcD35885BfE4c700042cE7cb39554);

    struct Snapshot {
        address[] protocols;
        address[] deprecated;
        uint8[] protocolCategories;
        uint8[] assetCategories;
        bool[] assetRegistered;
        address latestVault;
        address gasWrapped;
        address owner;
        address admin;
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
        for (uint256 i; i < assets.length; ++i) {
            s.assetCategories[i] = GUARD.assetCategory(assets[i]);
            s.assetRegistered[i] = GUARD.isAssetRegistered(assets[i]);
        }
        s.latestVault = GUARD.latestImplementation(1);
        s.gasWrapped = GUARD.getAddress(keccak256("bitty.gasWrapped"));
        s.owner = GUARD.getAddress(keccak256("bitty.owner"));
        s.admin = GUARD.defaultAdmin();
    }

    function _rehearse(string memory rpc, address[] memory assets, address weth, address ethUsd, address stable)
        internal
    {
        vm.createSelectFork(rpc);
        assertEq(GUARD.versionName(), "1.0.0", "the live guard is 1.0.0");
        Snapshot memory before = _snapshot(assets);

        BittyV1Guard next = new BittyV1Guard();
        vm.prank(before.admin);
        UUPSUpgradeable(address(GUARD)).upgradeToAndCall(address(next), "");

        assertEq(GUARD.versionName(), "1.0.1");
        Snapshot memory afterwards = _snapshot(assets);
        assertEq(keccak256(abi.encode(afterwards)), keccak256(abi.encode(before)), "1.0.0 state reads the same");

        address[] memory a = new address[](1);
        address[] memory f = new address[](1);
        uint32[] memory m = new uint32[](1);
        (a[0], f[0], m[0]) = (weth, ethUsd, 1 days);
        vm.prank(before.admin);
        GUARD.setPriceFeeds(a, f, m, new address[](1));
        PriceFeed memory p = GUARD.priceFeed(weth);
        assertEq(p.decimals, 8, "decimals read from the real Chainlink feed");
        assertEq(p.assetDecimals, 18, "and WETH's from the token");

        MarketTradeInfo memory info = GUARD.marketTradeInfo(before.protocols[0], weth, stable);
        assertEq(info.sellCategory, GUARD.assetCategory(weth));
        assertEq(info.sellFeed.feed, ethUsd);
    }

    function test_ethereum() public {
        address[] memory assets = new address[](4);
        assets[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        assets[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        assets[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        assets[3] = 0x14c3abF95Cb9C93a8b82C1CdCB76D72Cb87b2d4c; // AAPLon
        _rehearse(
            "https://ethereum-rpc.publicnode.com",
            assets,
            assets[0],
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            assets[2]
        );
    }

    function test_base() public {
        address[] memory assets = new address[](3);
        assets[0] = 0x4200000000000000000000000000000000000006; // WETH
        assets[1] = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf; // cbBTC
        assets[2] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
        _rehearse(
            "https://base.gateway.tenderly.co", assets, assets[0], 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, assets[2]
        );
    }

    function test_robinhood() public {
        address[] memory assets = new address[](3);
        assets[0] = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73; // WETH
        assets[1] = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC; // NVDA
        assets[2] = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // USDG
        _rehearse(
            "https://rpc.mainnet.chain.robinhood.com",
            assets,
            assets[0],
            0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9,
            assets[2]
        );
    }
}
