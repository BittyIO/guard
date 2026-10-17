// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "openzeppelin-contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {
    IBittyV1Guard,
    PriceFeed,
    MarketTradeInfo,
    ASSET_STABLE_COIN,
    NotDeployer,
    LengthMismatch,
    NotRegisteredProtocol,
    NotRegisteredImplementation,
    AddressZero,
    InvalidPriceFeed
} from "./interfaces/IBittyV1Guard.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/**
 * @dev The one call {BittyV1Guard-setPriceFeeds} makes to a Chainlink feed, and to the asset it prices.
 */
interface IDecimals {
    function decimals() external view returns (uint8);
}

/**
 * @title BittyV1Guard
 * @notice Guard of allowed assets and protocols for Bitty.
 */
contract BittyV1Guard is IBittyV1Guard, Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    address public constant DEPLOYER = 0x12EE2de7BF086388B1D560eb95e7191Edfab9823;

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant _VERSION = 1 * 1_000_000 + 0 * 1_000 + 1;

    uint48 internal constant DEFAULT_ADMIN_TRANSFER_DELAY = 7 days;

    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");
    bytes32 public constant CONFIG_MANAGER_ROLE = keccak256("CONFIG_MANAGER_ROLE");

    EnumerableSet.AddressSet internal _protocols;

    EnumerableSet.AddressSet internal _deprecatedProtocols;

    mapping(address => uint8) public protocolCategory;

    mapping(address => bool) internal _assets;

    mapping(address => uint8) public assetCategory;

    mapping(uint8 category => address) public latestImplementation;

    mapping(uint8 category => EnumerableSet.AddressSet) internal _pastImplementations;

    mapping(bytes32 key => address) internal _config;

    mapping(bytes32 key => uint256) internal _configUint;

    mapping(address asset => PriceFeed) internal _priceFeeds;

    address internal _sequencerUptimeFeed;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory assets_,
        uint8[] memory assetCategories_,
        address[] memory protocols_,
        uint8[] memory protocolCategories_
    ) public initializer {
        if (tx.origin != DEPLOYER) revert NotDeployer();
        __AccessControlDefaultAdminRules_init(DEFAULT_ADMIN_TRANSFER_DELAY, DEPLOYER);
        __UUPSUpgradeable_init();
        _grantRole(ASSET_MANAGER_ROLE, DEPLOYER);
        _grantRole(PROTOCOL_MANAGER_ROLE, DEPLOYER);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, DEPLOYER);
        _grantRole(CONFIG_MANAGER_ROLE, DEPLOYER);
        _addAssets(assets_, assetCategories_);
        _addProtocols(protocols_, protocolCategories_);
    }

    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function guardVersion() external pure override returns (uint256) {
        return _VERSION;
    }

    function versionName() external pure override returns (string memory) {
        return string.concat(
            Strings.toString(_VERSION / 1_000_000),
            ".",
            Strings.toString((_VERSION / 1_000) % 1_000),
            ".",
            Strings.toString(_VERSION % 1_000)
        );
    }

    function addAssets(address[] memory assetAddresses, uint8[] memory categories)
        external
        override
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAssets(assetAddresses, categories);
    }

    function _addAssets(address[] memory assetAddresses, uint8[] memory categories) internal {
        if (assetAddresses.length != categories.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address asset = assetAddresses[i];
            if (asset == address(0) || categories[i] == 0) {
                continue;
            }
            if (_assets[asset] && assetCategory[asset] == categories[i]) {
                continue;
            }
            _assets[asset] = true;
            assetCategory[asset] = categories[i];
            emit AssetAdded(asset, categories[i]);
        }
    }

    function removeAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address asset = assetAddresses[i];
            if (_assets[asset]) {
                _assets[asset] = false;
                assetCategory[asset] = 0;
                emit AssetRemoved(asset);
            }
        }
    }

    function isAssetRegistered(address assetAddress) external view override returns (bool) {
        return _assets[assetAddress];
    }

    function addProtocols(address[] memory protocolAddresses, uint8[] memory categories)
        external
        override
        onlyRole(PROTOCOL_MANAGER_ROLE)
    {
        _addProtocols(protocolAddresses, categories);
    }

    function _addProtocols(address[] memory protocolAddresses, uint8[] memory categories) internal {
        if (protocolAddresses.length != categories.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (protocol == address(0) || categories[i] == 0) {
                continue;
            }
            if (_protocols.contains(protocol) && protocolCategory[protocol] == categories[i]) {
                continue;
            }
            _protocols.add(protocol);
            protocolCategory[protocol] = categories[i];
            _deprecatedProtocols.remove(protocol);
            emit ProtocolAdded(protocol, categories[i]);
        }
    }

    function deprecateProtocols(address[] memory protocolAddresses) external override onlyRole(PROTOCOL_MANAGER_ROLE) {
        for (uint256 i = 0; i < protocolAddresses.length; i++) {
            address protocol = protocolAddresses[i];
            if (!_protocols.remove(protocol)) {
                revert NotRegisteredProtocol(protocol);
            }
            _deprecatedProtocols.add(protocol);
            emit ProtocolDeprecated(protocol);
        }
    }

    function isProtocolRegistered(address protocolAddress) external view override returns (bool) {
        return _protocols.contains(protocolAddress);
    }

    function getProtocols() external view override returns (address[] memory addresses) {
        return _protocols.values();
    }

    function getDeprecatedProtocols() external view override returns (address[] memory addresses) {
        return _deprecatedProtocols.values();
    }

    function isProtocolDeprecated(address protocolAddress) external view override returns (bool) {
        return _deprecatedProtocols.contains(protocolAddress);
    }

    function setImplementation(address implementation, uint8 category)
        external
        override
        onlyRole(IMPLEMENTATION_MANAGER_ROLE)
    {
        if (category == 0 || implementation == address(0)) revert AddressZero();
        address current = latestImplementation[category];
        if (current == implementation) return;
        if (current != address(0)) _pastImplementations[category].add(current);
        _pastImplementations[category].remove(implementation);
        latestImplementation[category] = implementation;
        emit ImplementationRegistered(implementation);
    }

    function retireImplementations(address[] memory implementations, uint8 category)
        external
        override
        onlyRole(IMPLEMENTATION_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < implementations.length; i++) {
            address implementation = implementations[i];
            if (!_pastImplementations[category].remove(implementation)) {
                revert NotRegisteredImplementation(implementation);
            }
            emit ImplementationUnregistered(implementation);
        }
    }

    function isImplementationRegisteredFor(address implementation, uint8 category)
        external
        view
        override
        returns (bool)
    {
        return implementation == latestImplementation[category]
            || _pastImplementations[category].contains(implementation);
    }

    function getPastImplementations(uint8 category) external view override returns (address[] memory) {
        return _pastImplementations[category].values();
    }

    function getAddress(bytes32 key) external view override returns (address) {
        return _config[key];
    }

    function setAddress(bytes32 key, address value) external override onlyRole(CONFIG_MANAGER_ROLE) {
        _config[key] = value;
        emit ConfigSet(key, value);
    }

    function getUint(bytes32 key) external view override returns (uint256) {
        return _configUint[key];
    }

    function setUint(bytes32 key, uint256 value) external override onlyRole(CONFIG_MANAGER_ROLE) {
        _configUint[key] = value;
        emit ConfigUintSet(key, value);
    }

    function setPriceFeeds(
        address[] calldata assets,
        address[] calldata feeds,
        uint32[] calldata maxAges,
        address[] calldata quotes
    ) external override onlyRole(ASSET_MANAGER_ROLE) {
        uint256 length = assets.length;
        if (feeds.length != length || maxAges.length != length || quotes.length != length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < length; i++) {
            address asset = assets[i];
            address feed = feeds[i];
            if (feed == address(0)) {
                delete _priceFeeds[asset];
                emit PriceFeedSet(asset, address(0), 0, 0, address(0));
                continue;
            }
            if (maxAges[i] == 0 || (quotes[i] != address(0) && quotes[i] == asset)) revert InvalidPriceFeed(asset);
            uint8 decimals = IDecimals(feed).decimals();
            _priceFeeds[asset] = PriceFeed({
                feed: feed,
                maxAge: maxAges[i],
                decimals: decimals,
                assetDecimals: _assetDecimals(asset),
                hasQuote: quotes[i] != address(0),
                quote: quotes[i]
            });
            emit PriceFeedSet(asset, feed, maxAges[i], decimals, quotes[i]);
        }
    }

    /**
     * @dev The native asset is 18; anything that answers no `decimals()` is 0, which a reader takes to
     *      mean "ask the token".
     */
    function _assetDecimals(address asset) private view returns (uint8) {
        if (asset == address(0)) return 18;
        (bool ok, bytes memory data) = asset.staticcall(abi.encodeCall(IDecimals.decimals, ()));
        if (!ok || data.length < 32) return 0;
        uint256 d = abi.decode(data, (uint256));
        return d > type(uint8).max ? 0 : uint8(d);
    }

    function priceFeed(address asset) external view override returns (PriceFeed memory) {
        return _priceFeeds[asset];
    }

    function setSequencerUptimeFeed(address feed) external override onlyRole(CONFIG_MANAGER_ROLE) {
        _sequencerUptimeFeed = feed;
        emit SequencerUptimeFeedSet(feed);
    }

    function sequencerUptimeFeed() external view override returns (address) {
        return _sequencerUptimeFeed;
    }

    function marketTradeChecks(address protocol, address sellToken, address buyToken)
        external
        view
        override
        returns (uint8, bool, uint8, uint8)
    {
        return (
            protocolCategory[protocol],
            _deprecatedProtocols.contains(protocol),
            assetCategory[sellToken],
            assetCategory[buyToken]
        );
    }

    function marketTradeInfo(address protocol, address sellToken, address buyToken)
        external
        view
        override
        returns (MarketTradeInfo memory info)
    {
        info.protocolCategory = protocolCategory[protocol];
        info.protocolDeprecated = _deprecatedProtocols.contains(protocol);
        info.sellCategory = assetCategory[sellToken];
        info.buyCategory = assetCategory[buyToken];

        bool sellPriced = info.sellCategory & ASSET_STABLE_COIN == 0;
        bool buyPriced = info.buyCategory & ASSET_STABLE_COIN == 0;
        if (sellPriced) (info.sellFeed, info.sellQuoteFeed) = _feedWithQuote(sellToken);
        if (buyPriced) (info.buyFeed, info.buyQuoteFeed) = _feedWithQuote(buyToken);
        if ((sellPriced || buyPriced) && block.chainid != 1) info.sequencerUptimeFeed = _sequencerUptimeFeed;
    }

    /**
     * @dev An asset's feed and, only if it is quoted, the quote's: a USD feed costs one slot.
     */
    function _feedWithQuote(address asset) private view returns (PriceFeed memory feed, PriceFeed memory quoteFeed) {
        feed = _firstSlot(asset);
        if (feed.hasQuote) {
            feed.quote = _priceFeeds[asset].quote;
            quoteFeed = _firstSlot(feed.quote);
            if (quoteFeed.hasQuote) quoteFeed.quote = _priceFeeds[feed.quote].quote;
        }
    }

    function _firstSlot(address asset) private view returns (PriceFeed memory p) {
        PriceFeed storage s = _priceFeeds[asset];
        (p.feed, p.maxAge, p.decimals, p.assetDecimals, p.hasQuote) =
        (s.feed, s.maxAge, s.decimals, s.assetDecimals, s.hasQuote);
    }
}
