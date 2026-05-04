// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IWhiteList} from "./interfaces/IWhiteList.sol";
import {AMMProviderShouldNotBeAllRemoved} from "./interfaces/IWhiteList.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title WhiteList
 * @notice Registry of allowed assets and protocol providers.
 * @dev Mutations are gated by {AccessControl} roles. `DEFAULT_ADMIN_ROLE` (assigned to `tx.origin` at deploy)
 *      can grant or revoke manager roles. Each category has its own manager role so operations can be split
 *      across addresses. For a timelocked admin, grant `DEFAULT_ADMIN_ROLE` to a `TimelockController`.
 */
contract WhiteList is IWhiteList, Initializable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Role allowed to add/remove assets.
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    /// @notice Role allowed to add/remove stable coins.
    bytes32 public constant STABLE_COIN_MANAGER_ROLE = keccak256("STABLE_COIN_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate lending providers.
    bytes32 public constant LENDING_MANAGER_ROLE = keccak256("LENDING_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate staking providers.
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    /// @notice Role allowed to add/remove AMM providers.
    bytes32 public constant AMM_MANAGER_ROLE = keccak256("AMM_MANAGER_ROLE");

    mapping(address => bool) public assets;
    mapping(address => bool) public stableCoins;
    mapping(address => bool) public lendingProviders;
    mapping(address => bool) public deprecatedLendingProviders;
    mapping(address => bool) public stakingProviders;
    mapping(address => bool) public deprecatedStakingProviders;

    EnumerableSet.AddressSet internal _ammProviders;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, tx.origin);
    }

    function initialize(
        address[] memory assets_,
        address[] memory stableCoins_,
        address[] memory lendingProviders_,
        address[] memory stakingProviders_,
        address[] memory ammProviders_
    ) public initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _addAssets(assets_);
        _addStableCoins(stableCoins_);
        _addLendingProviders(lendingProviders_);
        _addStakingProviders(stakingProviders_);
        _addAMMProviders(ammProviders_);
    }

    function addAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        _addAssets(assetAddresses);
    }

    function _addAssets(address[] memory assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                assets[assetAddresses[i]] = true;
            }
        }
    }

    function removeAssets(address[] memory assetAddresses) external override onlyRole(ASSET_MANAGER_ROLE) {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                assets[assetAddresses[i]] = false;
            }
        }
    }

    function isAssetWhiteListed(address assetAddress) external view override returns (bool) {
        return assets[assetAddress];
    }

    function addStableCoins(address[] memory stableCoinAddresses) external override onlyRole(STABLE_COIN_MANAGER_ROLE) {
        _addStableCoins(stableCoinAddresses);
    }

    function _addStableCoins(address[] memory stableCoinAddresses) internal {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                stableCoins[stableCoinAddresses[i]] = true;
            }
        }
    }

    function removeStableCoins(address[] memory stableCoinAddresses)
        external
        override
        onlyRole(STABLE_COIN_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                stableCoins[stableCoinAddresses[i]] = false;
            }
        }
    }

    function isStableCoinWhiteListed(address stableCoinAddress) external view override returns (bool) {
        return stableCoins[stableCoinAddress];
    }

    function addLendingProviders(address[] memory lendingProviderAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        _addLendingProviders(lendingProviderAddresses);
    }

    function _addLendingProviders(address[] memory lendingProviderAddresses) internal {
        for (uint256 i = 0; i < lendingProviderAddresses.length; i++) {
            if (lendingProviderAddresses[i] != address(0)) {
                lendingProviders[lendingProviderAddresses[i]] = true;
                deprecatedLendingProviders[lendingProviderAddresses[i]] = false;
            }
        }
    }

    function deprecateLendingProviders(address[] memory lendingProviderAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < lendingProviderAddresses.length; i++) {
            if (lendingProviderAddresses[i] != address(0)) {
                lendingProviders[lendingProviderAddresses[i]] = false;
                deprecatedLendingProviders[lendingProviderAddresses[i]] = true;
            }
        }
    }

    function isLendingProviderWhiteListed(address lendingProviderAddress) external view override returns (bool) {
        return lendingProviders[lendingProviderAddress];
    }

    function isLendingProviderDeprecated(address lendingProviderAddress) external view override returns (bool) {
        return deprecatedLendingProviders[lendingProviderAddress];
    }

    function addStakingProviders(address[] memory stakingProviderAddresses)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        _addStakingProviders(stakingProviderAddresses);
    }

    function _addStakingProviders(address[] memory stakingProviderAddresses) internal {
        for (uint256 i = 0; i < stakingProviderAddresses.length; i++) {
            if (stakingProviderAddresses[i] != address(0)) {
                stakingProviders[stakingProviderAddresses[i]] = true;
                deprecatedStakingProviders[stakingProviderAddresses[i]] = false;
            }
        }
    }

    function isStakingProviderWhiteListed(address stakingProviderAddress) external view override returns (bool) {
        return stakingProviders[stakingProviderAddress];
    }

    function isStakingProviderDeprecated(address stakingProviderAddress) external view override returns (bool) {
        return deprecatedStakingProviders[stakingProviderAddress];
    }

    function deprecateStakingProviders(address[] memory stakingProviderAddress)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < stakingProviderAddress.length; i++) {
            if (stakingProviderAddress[i] != address(0)) {
                stakingProviders[stakingProviderAddress[i]] = false;
                deprecatedStakingProviders[stakingProviderAddress[i]] = true;
            }
        }
    }

    function addAMMProviders(address[] memory ammProviderAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        _addAMMProviders(ammProviderAddresses);
    }

    function _addAMMProviders(address[] memory ammProviderAddresses) internal {
        for (uint256 i = 0; i < ammProviderAddresses.length; i++) {
            if (ammProviderAddresses[i] != address(0)) {
                _ammProviders.add(ammProviderAddresses[i]);
            }
        }
    }

    function removeAMMProviders(address[] memory ammProviderAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        for (uint256 i = 0; i < ammProviderAddresses.length; i++) {
            if (ammProviderAddresses[i] != address(0)) {
                _ammProviders.remove(ammProviderAddresses[i]);
            }
        }
        if (_ammProviders.length() == 0) {
            revert AMMProviderShouldNotBeAllRemoved();
        }
    }

    function isAMMProviderWhiteListed(address ammProviderAddress) external view override returns (bool) {
        return _ammProviders.contains(ammProviderAddress);
    }
}
