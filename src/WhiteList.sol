// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.27;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWhiteList} from "./interfaces/IWhiteList.sol";
import {AMMProviderShouldNotBeAllRemoved} from "./interfaces/IWhiteList.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract WhiteList is IWhiteList, Initializable, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => bool) public assets;
    mapping(address => bool) public stableCoins;
    mapping(address => bool) public lendingProviders;
    mapping(address => bool) public deprecatedLendingProviders;
    mapping(address => bool) public stakingProviders;
    mapping(address => bool) public deprecatedStakingProviders;
    mapping(address => bool) public intentProviders;
    mapping(address => bool) public deprecatedIntentProviders;

    EnumerableSet.AddressSet internal _ammProviders;

    constructor() {
        _transferOwnership(tx.origin);
    }

    function initialize(
        address[] memory assets_,
        address[] memory stableCoins_,
        address[] memory lendingProviders_,
        address[] memory stakingProviders_,
        address[] memory ammProviders_,
        address[] memory intentProviders_
    ) public initializer {
        _addAssets(assets_);
        _addStableCoins(stableCoins_);
        _addLendingProviders(lendingProviders_);
        _addStakingProviders(stakingProviders_);
        _addAMMProviders(ammProviders_);
        _addIntentProviders(intentProviders_);
    }

    function addAssets(address[] memory assetAddresses) external override onlyOwner {
        _addAssets(assetAddresses);
    }

    function _addAssets(address[] memory assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                assets[assetAddresses[i]] = true;
            }
        }
    }

    function removeAssets(address[] memory assetAddresses) external override onlyOwner {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            if (assetAddresses[i] != address(0)) {
                assets[assetAddresses[i]] = false;
            }
        }
    }

    function isAssetWhiteListed(address assetAddress) external view override returns (bool) {
        return assets[assetAddress];
    }

    function addStableCoins(address[] memory stableCoinAddresses) external override onlyOwner {
        _addStableCoins(stableCoinAddresses);
    }

    function _addStableCoins(address[] memory stableCoinAddresses) internal {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                stableCoins[stableCoinAddresses[i]] = true;
            }
        }
    }

    function removeStableCoins(address[] memory stableCoinAddresses) external override onlyOwner {
        for (uint256 i = 0; i < stableCoinAddresses.length; i++) {
            if (stableCoinAddresses[i] != address(0)) {
                stableCoins[stableCoinAddresses[i]] = false;
            }
        }
    }

    function isStableCoinWhiteListed(address stableCoinAddress) external view override returns (bool) {
        return stableCoins[stableCoinAddress];
    }

    function addLendingProviders(address[] memory lendingProviderAddresses) external override onlyOwner {
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

    function deprecateLendingProviders(address[] memory lendingProviderAddresses) external override onlyOwner {
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

    function addStakingProviders(address[] memory stakingProviderAddresses) external override onlyOwner {
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

    function deprecateStakingProviders(address[] memory stakingProviderAddress) external override onlyOwner {
        for (uint256 i = 0; i < stakingProviderAddress.length; i++) {
            if (stakingProviderAddress[i] != address(0)) {
                stakingProviders[stakingProviderAddress[i]] = false;
                deprecatedStakingProviders[stakingProviderAddress[i]] = true;
            }
        }
    }

    function addAMMProviders(address[] memory ammProviderAddresses) external override onlyOwner {
        _addAMMProviders(ammProviderAddresses);
    }

    function _addAMMProviders(address[] memory ammProviderAddresses) internal {
        for (uint256 i = 0; i < ammProviderAddresses.length; i++) {
            if (ammProviderAddresses[i] != address(0)) {
                _ammProviders.add(ammProviderAddresses[i]);
            }
        }
    }

    function removeAMMProviders(address[] memory ammProviderAddresses) external override onlyOwner {
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

    function addIntentProviders(address[] memory intentProviderAddresses) external override onlyOwner {
        _addIntentProviders(intentProviderAddresses);
    }

    function _addIntentProviders(address[] memory intentProviderAddresses) internal {
        for (uint256 i = 0; i < intentProviderAddresses.length; i++) {
            if (intentProviderAddresses[i] != address(0)) {
                intentProviders[intentProviderAddresses[i]] = true;
            }
        }
    }

    function isIntentProviderWhiteListed(address intentProviderAddress) external view override returns (bool) {
        return intentProviders[intentProviderAddress];
    }

    function deprecateIntentProviders(address[] memory intentProviderAddresses) external override onlyOwner {
        for (uint256 i = 0; i < intentProviderAddresses.length; i++) {
            if (intentProviderAddresses[i] != address(0)) {
                intentProviders[intentProviderAddresses[i]] = false;
                deprecatedIntentProviders[intentProviderAddresses[i]] = true;
            }
        }
    }

    function isIntentProviderDeprecated(address intentProviderAddress) external view override returns (bool) {
        return deprecatedIntentProviders[intentProviderAddress];
    }
}
