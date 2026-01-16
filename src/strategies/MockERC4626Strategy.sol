// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseStrategy as IBaseStrategy} from "../interfaces/IBaseStrategy.sol";

/**
 * @title MockERC4626Strategy
 * @dev Mock strategy that implements ERC4626 and BaseStrategy
 * Always liquid (no lockup)
 * Supports mock yield generation for testing
 */ 
contract MockERC4626Strategy is ERC4626, IBaseStrategy {
    // Virtual yield accumulator (percentage with 2 decimal places)
    // Stored as integer: 1050 = 10.50%, 1000 = 10.00%, 525 = 5.25%
    // This allows us to simulate yield without actually having the assets
    uint256 private _virtualYieldPercent;

    constructor(IERC20 asset_) ERC20("Mock ERC4626 Strategy", "mERC4626") ERC4626(asset_) {}

    /**
     * @dev Deposit assets into the strategy
     * @param assets Amount of assets to deposit
     */
    function depositToken(uint256 assets) external virtual override {
        deposit(assets, msg.sender);
    }

    /**
     * @dev Withdraw assets from the strategy
     * @param assets Amount of assets to withdraw
     */
    function withdrawToken(uint256 assets) external virtual override {
        withdraw(assets, msg.sender, msg.sender);
    }

    /**
     * @dev Get the amount of assets owned by an address in this strategy
     * @param owner Address to check assets for
     * @return Amount of assets owned
     */
    function assetsOfUser(address owner) external view virtual override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @dev Check if the strategy has a lockup period
     * @return false (this strategy is always liquid)
     */
    function hasLockup() external view virtual override returns (bool) {
        return false;
    }

    /**
     * @dev Check if the strategy is unlocked
     * @return true (this strategy is always unlocked)
     */
    function isUnlocked() external view virtual override returns (bool) {
        return true;
    }

    /**
     * @dev Override totalAssets to include virtual yield
     * This simulates yield generation for testing
     * Yield is calculated with 2 decimal places precision
     * @return Total assets including virtual yield
     */
    function totalAssets() public view override returns (uint256) {
        uint256 baseAssets = super.totalAssets();
        if (_virtualYieldPercent == 0) {
            return baseAssets;
        }
        // Apply virtual yield with 2 decimal precision:
        // baseAssets * (1 + percentage / 10000)
        // Example: 10.50% stored as 1050 -> baseAssets * (1 + 1050/10000) = baseAssets * 1.105
        return baseAssets + (baseAssets * _virtualYieldPercent) / 10_000;
    }

    /**
     * @dev Mock function to simulate yield generation
     * @param percentage Percentage with 2 decimal precision (e.g., 1050 = 10.50%, 1000 = 10.00%, 525 = 5.25%)
     */
    function mockYield(uint256 percentage) external {
        _virtualYieldPercent += percentage;
    }

    /**
     * @dev Get current virtual yield percentage (with 2 decimal precision)
     * @return Percentage stored as integer with 2 decimal precision (e.g., 1050 = 10.50%)
     */
    function getVirtualYieldPercent() external view returns (uint256) {
        return _virtualYieldPercent;
    }
}
