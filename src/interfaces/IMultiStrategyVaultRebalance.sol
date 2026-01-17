// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseStrategy as IBaseStrategy} from "./IBaseStrategy.sol";
import {VaultStructs} from "../libraries/VaultStructs.sol";  

/**
 * @title IMultiStrategyVaultRebalance
 * @dev Interface for rebalance executor to interact with MultiStrategyVault
 * This exposes only the functions needed for rebalancing
 */
interface IMultiStrategyVaultRebalance {
    // Note: StrategyConfig and WithdrawBatch are defined in VaultStructs library
    // asset() is inherited from ERC4626, so we don't redeclare it
    function totalAssets() external view returns (uint256);
    function totalAssetsToRedeem() external view returns (uint256);
    function strategies(uint256) external view returns (IBaseStrategy strategy, uint256 allocationBps);
    function strategiesLength() external view returns (uint256);
    function strategyShares(address) external view returns (uint256);
    function withdrawBatchById(uint256) external view returns (VaultStructs.WithdrawBatch memory);
    function nextBatchId() external view returns (uint256);
    
    function depositToStrategy(IBaseStrategy strategy, uint256 amount) external;
    function withdrawFromStrategy(IBaseStrategy strategy, uint256 amount) external returns (uint256);
    function updateStrategyShares(address strategy, uint256 shares) external;
    function updateTotalAssetsToRedeem(uint256 amount) external;
    function updateWithdrawBatch(uint256 batchId, VaultStructs.WithdrawBatch calldata batch) external;
    function incrementNextBatchId() external;
    function emitRebalanced() external;
}
