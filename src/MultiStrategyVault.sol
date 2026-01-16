// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IPauseController} from "./interfaces/IPauseController.sol";
import {Roles} from "./libraries/Roles.sol";
import "./interfaces/IMultiStrategyVault.sol";
import "./libraries/PauseActions.sol";

/**
 * @title MultiStrategyVault
 * @dev ERC-4626 vault that allocates assets across multiple strategies
 * Supports allocation management, withdrawal queue for locked strategies, and pause functionality
 */
contract MultiStrategyVault is ERC4626, IMultiStrategyVault {
    using SafeERC20 for IERC20;


    /// @notice Instance of the AccessController interface.
    IAccessController public accessController;

    /// @notice Instance of the PauseController interface.
    IPauseController public pauseController;

    uint256 public unlockTimestamp;
    uint256 public totalAssetsToRedeem;

    // Storage
    StrategyConfig[] public strategies;
    mapping(address => WithdrawRequest) public withdrawRequests;
    mapping(uint256 => WithdrawBatch) public withdrawBatchById;
    mapping(address => uint256) public strategyShares; // Track vault's shares in each strategy (by strategy address)
    uint256 public nextRequestId;
    uint256 public nextBatchId;

     /// @notice Modifier to restrict function access to certain roles.
     modifier onlyEntityRole(bytes32 _role) {
        _onlyEntityRole(_role, msg.sender);
        _;
    }

    /// @notice Modifier to ensure actions are not performed when paused.
    modifier whenNotPaused(bytes32 _actionHash) {
        _whenNotPaused(_actionHash);
        _;
    }
   
    /**
     * @dev Constructor
     * @param asset_ The underlying asset token (USDC)
     * @param _accessController Address of the AccessController (for PauseController)
     * @param _pauseController Address of the PauseController
     */
    constructor(
        IERC20 asset_,
        address _accessController,
        address _pauseController    
    ) ERC20("Multi Strategy Vault", "MSV") ERC4626(asset_) {
        if (
            _accessController == address(0x0) ||
            _pauseController == address(0x0) ||
            address(asset_) == address(0x0) 
        ) revert InvalidInput("Invalid input");
        accessController = IAccessController(_accessController);
        pauseController = IPauseController(_pauseController);
        nextBatchId = 1;
        
    }

    /**
     * @dev Add a strategy to the vault
     * @param strategy The strategy contract to add
     * @param allocationBps Initial allocation in basis points
     */
    function addStrategy(address strategy, uint256 allocationBps) external onlyEntityRole(Roles.MANAGER_ROLE) {
        if (strategy == address(0)) revert InvalidInput("Invalid strategy");

        // check for total allocation percentage
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            totalAllocation += strategies[i].allocationBps;
        }
        if (totalAllocation + allocationBps > 10000) revert InvalidInput("Invalid allocation");

        strategies.push(StrategyConfig({
            strategy: IBaseStrategy(strategy),
            allocationBps: allocationBps
        }));
        
        emit StrategyAdded(IBaseStrategy(strategy), allocationBps);
    }

    /**
     * @dev Get the number of strategies
     */
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }

    /**
     * @dev Override totalAssets to include idle USDC and strategy assets
     * @return Total assets managed by the vault
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        
        // Add assets from each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            IBaseStrategy strategy = strategies[i].strategy;
            uint256 shares = strategyShares[address(strategy)];
            if (shares > 0) {
                // Use the strategy's convertToAssets to get the asset value of our shares
                // Since strategies are ERC4626, we can call convertToAssets directly
                IERC4626 strategyVault = IERC4626(address(strategy));
                total += strategyVault.convertToAssets(shares);
            }
        }
        
        return total;
    }

    /**
     * @dev Set allocation percentages for strategies
     * @param allocationsBps Array of allocation basis points (must sum to 10,000)
     */
    function setAllocations(uint256[] calldata allocationsBps) external onlyEntityRole(Roles.MANAGER_ROLE) {
        if (allocationsBps.length != strategies.length) revert InvalidInput("Invalid allocations");
        
        uint256 totalBps = 0;
        for (uint256 i = 0; i < allocationsBps.length; i++) {
            totalBps += allocationsBps[i];
            strategies[i].allocationBps = allocationsBps[i];
        }
        
        if (totalBps != 10_000) revert InvalidInput("Invalid total allocation");
        
        emit AllocationSet(allocationsBps);
    }

    /**
     * @dev Rebalance funds across strategies according to allocations
     */
    function rebalance() external whenNotPaused(PauseActions.PAUSE_REBALANCE) {
        
        // withdrawl the amount from the strategies which are locked
        // first check if there is any existing withdraw request for the previous batch
        if (nextBatchId > 1) {
            WithdrawBatch storage previousBatch = withdrawBatchById[nextBatchId - 1];
            if (previousBatch.expectedUnlockTimestamp <= block.timestamp && !previousBatch.claimEnabled) {
                // as we have considered that there are 2 strategies, one with lockup and one without lockup
                // so we have to make a .call to the strategy contract to get the withdraw request id
                for (uint256 i = 0; i < strategies.length; i++) {
                    if (strategies[i].strategy.hasLockup()) {
                        (bool success, bytes memory data) = address(strategies[i].strategy).call(
                            abi.encodeWithSignature("redeemFunds(uint256)", previousBatch.withdrawRequestId)
                        );
                            if (success) {
                                uint256 amountRedeemed = abi.decode(data, (uint256));
                                totalAssetsToRedeem += amountRedeemed;
                                previousBatch.withdrawalLeftToBeProcessed = amountRedeemed;
                                previousBatch.claimEnabled = true;
                            } else {
                                revert InvalidInput("Failed to redeem funds");
                            }
                        }
                    }
                }
            }

            uint256 total = totalAssets() - totalAssetsToRedeem;
            for (uint256 i = 0; i < strategies.length; i++) {
                StrategyConfig memory config = strategies[i];
                IBaseStrategy strategy = config.strategy;
                
                // Calculate target assets for this strategy
                uint256 targetAssets = (total * config.allocationBps) / 10_000;
                
                // Get current assets in this strategy
                uint256 currentAssets = strategy.assetsOfUser(address(this));
                
                if (currentAssets < targetAssets) {
                    // Underweight: deposit difference
                    uint256 depositAmount = targetAssets - currentAssets;
                    uint256 idleBalance = IERC20(asset()).balanceOf(address(this));
                    
                    // Only deposit what we have available
                    if (depositAmount > idleBalance) {
                        depositAmount = idleBalance;
                    }
                    
                    if (depositAmount > 0) {
                        IERC20 assetToken = IERC20(asset());
                        SafeERC20.forceApprove(assetToken, address(strategy), depositAmount);
                        strategy.depositToken(depositAmount);
                        SafeERC20.forceApprove(assetToken, address(strategy), 0);
                        
                        // Update strategy shares tracking
                        IERC4626 strategyVault = IERC4626(address(strategy));
                        strategyShares[address(strategy)] = strategyVault.balanceOf(address(this));
                    }
                } else if (currentAssets > targetAssets) {
                    // Overweight: withdraw excess (only if not locked)
                    if (!strategy.hasLockup()) {
                        uint256 withdrawAmount = currentAssets - targetAssets;
                        
                        if (withdrawAmount > 0) {
                            strategy.withdrawToken(withdrawAmount);
                            
                            // Update strategy shares tracking
                            IERC4626 strategyVault = IERC4626(address(strategy));
                            strategyShares[address(strategy)] = strategyVault.balanceOf(address(this));
                        }
                    } else {
                        // if locked, queue the withdrawal
                    }
                }
            }
            // withdraw the entire amount from the strategies which have locked strategies as 
            // we have already withdrawn the amount from the strategies which have not locked strategies
            uint256 amountToWithdraw = withdrawBatchById[nextBatchId].totalAssetsToWithdrawFromStrategy;
                if (amountToWithdraw > 0) {
                    for (uint256 i = 0; i < strategies.length; i++) {
                        if (strategies[i].strategy.hasLockup()) {
                            uint256 assetsStaked = strategies[i].strategy.assetsOfUser(address(this));
                            if (assetsStaked > 0) {
                                // fetch the amount to be withdrawn from the strategy
                                if (assetsStaked >= amountToWithdraw) {    
                                    strategies[i].strategy.withdrawToken(amountToWithdraw);
                                    break;
                                }
                                else {
                                    strategies[i].strategy.withdrawToken(assetsStaked);
                                    amountToWithdraw -= assetsStaked;
                                }
                                // Using low-level call since interface doesn't have these function signatures
                                // Get withdraw request ID from strategy
                                (bool success, bytes memory data) = address(strategies[i].strategy).call(
                                    abi.encodeWithSignature("withdrawalsIds(address)", address(this))
                                );
                                uint256 withdrawRequestId;
                                if (success) {
                                    withdrawRequestId = abi.decode(data, (uint256));
                                    withdrawBatchById[nextBatchId].withdrawRequestId = withdrawRequestId;
                                } else {
                                    revert InvalidInput("Failed to get withdraw request id");
                                }
                                // Get withdraw data from strategy
                                (success, data) = address(strategies[i].strategy).call(
                                    abi.encodeWithSignature("getWithdrawData(uint256)", withdrawRequestId)
                                );
                                if (success) {
                                    (, , ,uint256 expectedUnlockTimestamp,) = abi.decode(data, (uint256, address, uint256, uint256, bool));
                                    withdrawBatchById[nextBatchId].expectedUnlockTimestamp = expectedUnlockTimestamp;
                                } else {
                                    revert InvalidInput("Failed to get withdraw data");
                                }
                            }
                        }
                    }

                    nextBatchId++;
                    withdrawBatchById[nextBatchId] = WithdrawBatch({
                        withdrawRequestId: 0,
                        totalAssetsToWithdrawFromStrategy: 0,
                        withdrawalLeftToBeProcessed: 0,
                        expectedUnlockTimestamp: 0,
                        claimEnabled: false
                    });
                }
        emit Rebalanced();
    }

    /**
     * @dev Request withdrawal by burning shares immediately
     * Pays available liquid USDC, queues remainder if needed
     * @param shares Number of shares to redeem
     * @return requestId Request ID (0 if fully paid immediately)
     */
    function requestWithdraw(uint256 shares, address receiver) public returns (uint256) {
        if (shares == 0) revert InvalidInput("Invalid shares");
        if (balanceOf(msg.sender) < shares) revert InvalidInput("Insufficient balance");
        
        // Calculate expected assets
        uint256 expectedAssets = previewRedeem(shares);
        
        // Burn shares immediately (no pending shares)
        _burn(msg.sender, shares);
        
        // Get available liquid USDC
        uint256 available = IERC20(asset()).balanceOf(address(this));
        
        if (available >= expectedAssets) {
            // Full payment available
            IERC20(asset()).safeTransfer(receiver, expectedAssets);
            return 0; 
        } else {

            // Partial payment, queue remainder
            if (available > 0) {
                IERC20(asset()).safeTransfer(receiver, available);
            }

            uint256 queuedAssets = expectedAssets - available;
            for (uint256 i = 0; i < strategies.length; i++) {
                if (!strategies[i].strategy.hasLockup()) {
                    uint256 assetsStaked = strategies[i].strategy.assetsOfUser(address(this));
                    if (assetsStaked >= queuedAssets) {
                        strategies[i].strategy.withdrawToken(queuedAssets);
                    }
                    else {
                        strategies[i].strategy.withdrawToken(assetsStaked); 
                        queuedAssets -= assetsStaked;
                    }
                }
            }

            uint256 requestId = nextRequestId++;
            withdrawBatchById[nextBatchId].totalAssetsToWithdrawFromStrategy += queuedAssets;
            withdrawRequests[receiver] = WithdrawRequest({
                requestId: requestId,
                expectedAmount: queuedAssets,
                claimed: false
            });
            
            emit WithdrawRequested(requestId, msg.sender, queuedAssets);
            return requestId;
        }
    }

    /**
     * @dev Claim queued withdrawal after strategies unlock
     */
    function claimWithdraw() external {
        WithdrawRequest storage request = withdrawRequests[msg.sender];
        if (request.requestId == 0) revert InvalidInput("Invalid request");
        if (request.claimed) revert InvalidInput("Invalid request claimed");
        
        // Check all locked strategies are unlocked
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].strategy.hasLockup()) {
                if (!strategies[i].strategy.isUnlocked()) revert InvalidInput("Strategy still locked");
            }
        }
        
        // Mark as claimed before transfer (reentrancy protection)
        request.claimed = true;
        
        // Decrease totalAssetsToRedeem when user claims
        if (totalAssetsToRedeem >= request.expectedAmount) {
            totalAssetsToRedeem -= request.expectedAmount;
        } else {
            revert InvalidInput("Insufficient assets to redeem");
        }
        
        // Transfer queued assets
        IERC20(asset()).safeTransfer(msg.sender, request.expectedAmount);
        
        emit WithdrawClaimed(request.requestId);
    }

    /**
     * @dev Override withdraw to use requestWithdraw
     */
    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused(PauseActions.PAUSE_WITHDRAW) returns (uint256) {
        if (receiver != owner) revert InvalidInput("Invalid receiver");
        uint256 shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        return requestWithdraw(shares, receiver);
    }

    /**
     * @dev Override redeem to use requestWithdraw
     */
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused(PauseActions.PAUSE_REDEEM) returns (uint256) {
        if (receiver != owner) revert InvalidInput("Invalid receiver");
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        return requestWithdraw(shares, receiver);
    }

    /**
     * @dev Override deposit to add checks
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused(PauseActions.PAUSE_DEPOSIT) returns (uint256) {

        if (assets == 0) revert InvalidInput("Invalid assets");
        if (receiver == address(0)) revert InvalidInput("Invalid receiver");

        return super.deposit(assets, receiver);
    }

    /// ============================================== internal functions ==============================================
    
    /// @notice Checks if the caller has the specified role.
    /// @param _role The role to check.
    /// @param _user The address of the user to check.
    function _onlyEntityRole(bytes32 _role, address _user) internal view {
        if (!accessController.ensureEntityRole(_role, _user)) revert AuthenticationFailed();
    }

    /// @notice Checks if the specified action is not paused.
    /// @param _actionHash The hash of the action to check.
    function _whenNotPaused(bytes32 _actionHash) internal view {
        if (pauseController.isActionPaused(_actionHash)) revert ActionPaused();
    }
}
