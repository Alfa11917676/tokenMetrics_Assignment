// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BaseStrategy
 * @dev Interface for strategy contracts used by MultiStrategyVault
 */
interface BaseStrategy {

    error InvalidInput(string message);
    
    /**
     * @dev Deposit assets into the strategy
     * @param assets Amount of assets to deposit
     */
    function depositToken(uint256 assets) external;

    /**
     * @dev Withdraw assets from the strategy
     * @param assets Amount of assets to withdraw
     */
    function withdrawToken(uint256 assets) external;

    /**
     * @dev Get the amount of assets owned by an address in this strategy
     * @param owner Address to check assets for
     * @return Amount of assets owned
     */
    function assetsOfUser(address owner) external view returns (uint256);

    /**
     * @dev Check if the strategy has a lockup period
     * @return true if strategy has lockup, false otherwise
     */
    function hasLockup() external view returns (bool);

    /**
     * @dev Check if the strategy is unlocked (for locked strategies)
     * @return true if strategy is unlocked or has no lockup, false if still locked
     */
    function isUnlocked() external view returns (bool);
}
