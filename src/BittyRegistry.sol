// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {AMMProtocolShouldNotBeAllRemoved} from "./interfaces/IRegistry.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title BittyRegistry
 * @notice Registry of allowed assets and protocols for Bitty.
 * @dev Mutations are gated by {AccessControl} roles. `DEFAULT_ADMIN_ROLE` (assigned to `tx.origin` at deploy)
 *      can grant or revoke manager roles. Each category has its own manager role so operations can be split
 *      across addresses. For a timelocked admin, grant `DEFAULT_ADMIN_ROLE` to a `TimelockController`.
 */
contract BittyRegistry is IRegistry, Initializable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Role allowed to add/remove assets.
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    /// @notice Role allowed to add/remove stable coins.
    bytes32 public constant STABLE_COIN_MANAGER_ROLE = keccak256("STABLE_COIN_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate lending protocols.
    bytes32 public constant LENDING_MANAGER_ROLE = keccak256("LENDING_MANAGER_ROLE");
    /// @notice Role allowed to add/deprecate staking protocols.
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    /// @notice Role allowed to add/remove AMM protocols.
    bytes32 public constant AMM_MANAGER_ROLE = keccak256("AMM_MANAGER_ROLE");

    mapping(address => bool) public assets;
    mapping(address => bool) public stableCoins;
    mapping(address => bool) public lendingProtocols;
    mapping(address => bool) public deprecatedLendingProtocols;
    mapping(address => bool) public stakingProtocols;
    mapping(address => bool) public deprecatedStakingProtocols;

    EnumerableSet.AddressSet internal _ammProtocols;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, tx.origin);
    }

    function initialize(
        address[] memory assets_,
        address[] memory stableCoins_,
        address[] memory lendingProtocols_,
        address[] memory stakingProtocols_,
        address[] memory ammProtocols_
    ) public initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _addAssets(assets_);
        _addStableCoins(stableCoins_);
        _addLendingProtocols(lendingProtocols_);
        _addStakingProtocols(stakingProtocols_);
        _addAMMProtocols(ammProtocols_);
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

    function isAssetRegistered(address assetAddress) external view override returns (bool) {
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

    function isStableCoinRegistered(address stableCoinAddress) external view override returns (bool) {
        return stableCoins[stableCoinAddress];
    }

    function addLendingProtocols(address[] memory lendingProtocolAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        _addLendingProtocols(lendingProtocolAddresses);
    }

    function _addLendingProtocols(address[] memory lendingProtocolAddresses) internal {
        for (uint256 i = 0; i < lendingProtocolAddresses.length; i++) {
            if (lendingProtocolAddresses[i] != address(0)) {
                lendingProtocols[lendingProtocolAddresses[i]] = true;
                deprecatedLendingProtocols[lendingProtocolAddresses[i]] = false;
            }
        }
    }

    function deprecateLendingProtocols(address[] memory lendingProtocolAddresses)
        external
        override
        onlyRole(LENDING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < lendingProtocolAddresses.length; i++) {
            if (lendingProtocolAddresses[i] != address(0)) {
                lendingProtocols[lendingProtocolAddresses[i]] = false;
                deprecatedLendingProtocols[lendingProtocolAddresses[i]] = true;
            }
        }
    }

    function isLendingProtocolRegistered(address lendingProtocolAddress) external view override returns (bool) {
        return lendingProtocols[lendingProtocolAddress];
    }

    function isLendingProtocolDeprecated(address lendingProtocolAddress) external view override returns (bool) {
        return deprecatedLendingProtocols[lendingProtocolAddress];
    }

    function addStakingProtocols(address[] memory stakingProtocolAddresses)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        _addStakingProtocols(stakingProtocolAddresses);
    }

    function _addStakingProtocols(address[] memory stakingProtocolAddresses) internal {
        for (uint256 i = 0; i < stakingProtocolAddresses.length; i++) {
            if (stakingProtocolAddresses[i] != address(0)) {
                stakingProtocols[stakingProtocolAddresses[i]] = true;
                deprecatedStakingProtocols[stakingProtocolAddresses[i]] = false;
            }
        }
    }

    function isStakingProtocolRegistered(address stakingProtocolAddress) external view override returns (bool) {
        return stakingProtocols[stakingProtocolAddress];
    }

    function isStakingProtocolDeprecated(address stakingProtocolAddress) external view override returns (bool) {
        return deprecatedStakingProtocols[stakingProtocolAddress];
    }

    function deprecateStakingProtocols(address[] memory stakingProtocolAddress)
        external
        override
        onlyRole(STAKING_MANAGER_ROLE)
    {
        for (uint256 i = 0; i < stakingProtocolAddress.length; i++) {
            if (stakingProtocolAddress[i] != address(0)) {
                stakingProtocols[stakingProtocolAddress[i]] = false;
                deprecatedStakingProtocols[stakingProtocolAddress[i]] = true;
            }
        }
    }

    function addAMMProtocols(address[] memory ammProtocolAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        _addAMMProtocols(ammProtocolAddresses);
    }

    function _addAMMProtocols(address[] memory ammProtocolAddresses) internal {
        for (uint256 i = 0; i < ammProtocolAddresses.length; i++) {
            if (ammProtocolAddresses[i] != address(0)) {
                _ammProtocols.add(ammProtocolAddresses[i]);
            }
        }
    }

    function removeAMMProtocols(address[] memory ammProtocolAddresses) external override onlyRole(AMM_MANAGER_ROLE) {
        for (uint256 i = 0; i < ammProtocolAddresses.length; i++) {
            if (ammProtocolAddresses[i] != address(0)) {
                _ammProtocols.remove(ammProtocolAddresses[i]);
            }
        }
        if (_ammProtocols.length() == 0) {
            revert AMMProtocolShouldNotBeAllRemoved();
        }
    }

    function isAMMProtocolRegistered(address ammProtocolAddress) external view override returns (bool) {
        return _ammProtocols.contains(ammProtocolAddress);
    }
}
