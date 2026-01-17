// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMultiStrategyVaultRebalance} from "./interfaces/IMultiStrategyVaultRebalance.sol";
import {BaseStrategy as IBaseStrategy} from "./interfaces/IBaseStrategy.sol";
import {MockLockedStrategy} from "./strategies/MockLockedStrategy.sol";
import {VaultStructs} from "./libraries/VaultStructs.sol";
import "forge-std/console.sol";

/**
 * @title RebalanceExecutor
 * @dev Separate contract to handle rebalance logic, reducing the size of MultiStrategyVault
 */
contract RebalanceExecutor {
    using SafeERC20 for IERC20;

    /**
     * @dev Execute rebalance logic
     * @param vault Address of the MultiStrategyVault to rebalance
     */
    function executeRebalance(address vault) external {
        IMultiStrategyVaultRebalance vaultInterface = IMultiStrategyVaultRebalance(vault);
        
        // Step 1: Withdraw funds from previous batch if unlocked
        uint256 nextBatchId = vaultInterface.nextBatchId();
        if (nextBatchId > 1) {
            VaultStructs.WithdrawBatch memory previousBatch = vaultInterface.withdrawBatchById(nextBatchId - 1);
            
            if (!previousBatch.claimEnabled && previousBatch.totalAssetsToWithdrawFromStrategy > 0) {
                for (uint256 i = 0; i < vaultInterface.strategiesLength(); i++) {
                    (IBaseStrategy strategy, ) = vaultInterface.strategies(i);
                    if (strategy.hasLockup()) {
                        MockLockedStrategy lockedStrategy = MockLockedStrategy(address(strategy));
                        (, , , uint256 actualUnlockTimestamp, bool isClaimed) = lockedStrategy.getWithdrawData(previousBatch.withdrawRequestId);
                        
                        if (isClaimed) {
                            VaultStructs.WithdrawBatch memory updatedBatch = previousBatch;
                            updatedBatch.claimEnabled = true;
                            vaultInterface.updateWithdrawBatch(nextBatchId - 1, updatedBatch);
                            continue;
                        }
                        
                        if (actualUnlockTimestamp <= block.timestamp) {
                            uint256 amountRedeemed = lockedStrategy.redeemFunds(previousBatch.withdrawRequestId);
                            vaultInterface.updateTotalAssetsToRedeem(vaultInterface.totalAssetsToRedeem() + amountRedeemed);
                            
                            // transfer usdc to this contract
                            IERC20(IERC4626(vault).asset()).safeTransfer(address(vault), amountRedeemed);
                            
                            VaultStructs.WithdrawBatch memory updatedBatch = previousBatch;
                            updatedBatch.withdrawalLeftToBeProcessed = amountRedeemed;
                            updatedBatch.claimEnabled = true;
                            vaultInterface.updateWithdrawBatch(nextBatchId - 1, updatedBatch);
                        }
                    }
                }
            }
        }

        // Step 2: Rebalance the portfolio
        uint256 total = vaultInterface.totalAssets();
        uint256 strategiesLength = vaultInterface.strategiesLength();
        
        for (uint256 i = 0; i < strategiesLength; i++) {
            (IBaseStrategy strategy, uint256 allocationBps) = vaultInterface.strategies(i);
            
            uint256 targetAssets = (total * allocationBps) / 10_000;
            uint256 currentAssets = strategy.assetsOfUser(vault);
            
            if (currentAssets < targetAssets) {
                // Underweight: deposit difference
                uint256 depositAmount = targetAssets - currentAssets;
                address assetAddress = IERC4626(vault).asset();
                uint256 actualBalance = IERC20(assetAddress).balanceOf(vault);
                uint256 totalAssetsToRedeem = vaultInterface.totalAssetsToRedeem();
                uint256 idleBalance = actualBalance > totalAssetsToRedeem ? actualBalance - totalAssetsToRedeem : 0;
                
                if (depositAmount > idleBalance) {
                    depositAmount = idleBalance;
                }
                
                if (depositAmount > 0) {
                    vaultInterface.depositToStrategy(strategy, depositAmount);
                }
            } else if (currentAssets > targetAssets) {
                // Overweight: withdraw excess (only if not locked)
                if (!strategy.hasLockup()) {
                    uint256 withdrawAmount = currentAssets - targetAssets;
                    IERC4626 strategyVault = IERC4626(address(strategy));
                    uint256 maxWithdrawable = strategyVault.maxWithdraw(vault);
                    if (withdrawAmount > maxWithdrawable) {
                        withdrawAmount = maxWithdrawable;
                    }
                    
                    if (withdrawAmount > 0) {
                        vaultInterface.withdrawFromStrategy(strategy, withdrawAmount);
                    }
                }
            }
        }

        // Step 3: Request withdrawal from locked strategies
        VaultStructs.WithdrawBatch memory currentBatch = vaultInterface.withdrawBatchById(nextBatchId);
        uint256 amountToWithdraw = currentBatch.totalAssetsToWithdrawFromStrategy;
        
        if (amountToWithdraw > 0) {
            for (uint256 i = 0; i < strategiesLength; i++) {
                (IBaseStrategy strategy, ) = vaultInterface.strategies(i);
                
                if (!strategy.hasLockup()) {
                    uint256 assetsStaked = strategy.assetsOfUser(vault);
                    if (assetsStaked > 0) {
                        IERC4626 strategyVault = IERC4626(address(strategy));
                        address assetAddress = IERC4626(vault).asset();
                        uint256 actualStrategyBalance = IERC20(assetAddress).balanceOf(address(strategy));
                        uint256 shares = strategyVault.balanceOf(vault);
                        uint256 maxWithdrawable = shares > 0 ? strategyVault.previewRedeem(shares) : 0;
                        if (maxWithdrawable > actualStrategyBalance) {
                            maxWithdrawable = actualStrategyBalance;
                        }
                        uint256 withdrawable = assetsStaked > maxWithdrawable ? maxWithdrawable : assetsStaked;
                        
                        if (withdrawable >= amountToWithdraw && withdrawable > 0) {
                            uint256 actualWithdraw = amountToWithdraw > maxWithdrawable ? maxWithdrawable : amountToWithdraw;
                            if (actualWithdraw > 0) {
                                uint256 actualWithdrawn = vaultInterface.withdrawFromStrategy(strategy, actualWithdraw);
                                amountToWithdraw -= actualWithdraw;
                                vaultInterface.updateTotalAssetsToRedeem(vaultInterface.totalAssetsToRedeem() + actualWithdrawn);
                            }
                            if (amountToWithdraw == 0) break;
                        } else if (withdrawable > 0) {
                            uint256 actualWithdrawn = vaultInterface.withdrawFromStrategy(strategy, withdrawable);
                            amountToWithdraw -= withdrawable;
                            vaultInterface.updateTotalAssetsToRedeem(vaultInterface.totalAssetsToRedeem() + actualWithdrawn);
                        }
                    }
                } else {
                    uint256 assetsStaked = strategy.assetsOfUser(vault);
                    if (assetsStaked > 0) {
                        MockLockedStrategy lockedStrategy = MockLockedStrategy(address(strategy));
                        
                        if (assetsStaked >= amountToWithdraw) {
                            lockedStrategy.withdrawToken(amountToWithdraw);
                            amountToWithdraw = 0;
                        } else {
                            lockedStrategy.withdrawToken(assetsStaked);
                            amountToWithdraw -= assetsStaked;
                        }
                        
                        if (currentBatch.withdrawRequestId == 0) {
                            uint256 withdrawRequestId = lockedStrategy.withdrawalsIds(vault);
                            if (withdrawRequestId == 0) {
                                uint256 nextId = lockedStrategy.nextRequestId();
                                if (nextId > 0) {
                                    withdrawRequestId = nextId - 1;
                                }
                            }
                            
                            if (withdrawRequestId > 0) {
                                currentBatch.withdrawRequestId = withdrawRequestId;
                                (, , , uint256 expectedUnlockTimestamp, ) = lockedStrategy.getWithdrawData(withdrawRequestId);
                                currentBatch.expectedUnlockTimestamp = expectedUnlockTimestamp;
                            }
                        }
                        
                        if (amountToWithdraw == 0) break;
                    }
                }
            }

            // Step 4: Create new batch if withdrawals were requested
            if (currentBatch.totalAssetsToWithdrawFromStrategy > 0) {
                vaultInterface.updateWithdrawBatch(nextBatchId, currentBatch);
                vaultInterface.incrementNextBatchId();
                
                VaultStructs.WithdrawBatch memory newBatch = VaultStructs.WithdrawBatch({
                    withdrawRequestId: 0,
                    totalAssetsToWithdrawFromStrategy: 0,
                    withdrawalLeftToBeProcessed: 0,
                    expectedUnlockTimestamp: 0,
                    claimEnabled: false
                });
                vaultInterface.updateWithdrawBatch(vaultInterface.nextBatchId(), newBatch);
            }
        }
        
        vaultInterface.emitRebalanced();
    }
}
