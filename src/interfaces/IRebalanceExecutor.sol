// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRebalanceExecutor
 * @dev Interface for the rebalance executor contract
 */
interface IRebalanceExecutor {
    /**
     * @dev Execute rebalance logic
     * @param vault Address of the MultiStrategyVault to rebalance
     */
    function executeRebalance(address vault) external;
}
