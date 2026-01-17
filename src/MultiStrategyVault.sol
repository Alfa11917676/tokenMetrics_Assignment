// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IPauseController} from "./interfaces/IPauseController.sol";
import {Roles} from "./libraries/Roles.sol";
import "./interfaces/IMultiStrategyVault.sol";
import "./interfaces/IMultiStrategyVaultRebalance.sol";
import "./interfaces/IRebalanceExecutor.sol";
import "./strategies/MockLockedStrategy.sol";
import "./libraries/PauseActions.sol";
import "./libraries/VaultStructs.sol";
import "./interfaces/ICoreWriter.sol";
import "forge-std/console.sol";

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

    /// @notice Instance of the CoreWriter interface.
    ICoreWriter public coreWriter;

    /// @notice Rebalance executor contract
    IRebalanceExecutor public rebalanceExecutor;

    uint256 public totalAssetsToRedeem;
    uint256 public maxAllocationBps;
    // Storage
    VaultStructs.StrategyConfig[] public strategies;
    mapping(address => VaultStructs.WithdrawRequest) private withdrawRequests;
    mapping(uint256 => VaultStructs.WithdrawBatch) public withdrawBatchById;
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
     * @param _coreWriter Address of the CoreWriter
     * @param _pauseController Address of the PauseController
     */
    constructor(
        IERC20 asset_,
        address _accessController,
        address _coreWriter,
        address _pauseController    
    ) ERC20("Multi Strategy Vault", "MSV") ERC4626(asset_) {
        if (
            _accessController == address(0x0) ||
            _pauseController == address(0x0) ||
            address(asset_) == address(0x0) ||
            _coreWriter == address(0x0)
        ) revert InvalidInput("Invalid input");
        accessController = IAccessController(_accessController);
        pauseController = IPauseController(_pauseController);
        coreWriter = ICoreWriter(_coreWriter);
        maxAllocationBps = 8000;
        nextBatchId = 1;
    }

    /**
     * @dev Set the rebalance executor contract
     * @param _rebalanceExecutor Address of the RebalanceExecutor contract
     */
    function setRebalanceExecutor(address _rebalanceExecutor) external onlyEntityRole(Roles.ADMIN_ROLE) {
        if (_rebalanceExecutor == address(0x0)) revert InvalidInput("Invalid executor");
        rebalanceExecutor = IRebalanceExecutor(_rebalanceExecutor);
    }

    /// @notice Set the maximum allocation basis points
    /// @param _maxAllocationBps The maximum allocation basis points    
    function setMaxAllocationBps(uint256 _maxAllocationBps) external onlyEntityRole(Roles.ADMIN_ROLE) {
        if (_maxAllocationBps >= 10000) revert InvalidInput("Invalid allocation");
        maxAllocationBps = _maxAllocationBps;
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

        if (allocationBps > maxAllocationBps) revert InvalidInput("Invalid allocation");

        if (totalAllocation + allocationBps > 10000) revert InvalidInput("Invalid allocation");

        strategies.push(VaultStructs.StrategyConfig({
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

    function getWithdrawRequest(address user) external view returns (uint256, uint256, bool) {
        return (withdrawRequests[user].requestId, withdrawRequests[user].expectedAmount, withdrawRequests[user].claimed);
    }

    /**
     * @dev Override totalAssets to include idle USDC and strategy assets
     * Excludes totalAssetsToRedeem (assets waiting to be claimed by users)
     * @return Total assets managed by the vault (excluding pending redemptions)
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        // Add assets from each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            IBaseStrategy strategy = strategies[i].strategy;
            // Verify strategy is valid (not zero address) and has shares
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
            if (allocationsBps[i] > maxAllocationBps) revert InvalidInput("Invalid allocation");
          
            totalBps += allocationsBps[i];
            strategies[i].allocationBps = allocationsBps[i];
        }
        
        if (totalBps != 10_000) revert InvalidInput("Invalid total allocation");
        
        emit AllocationSet(allocationsBps);
    }

    /**
     * @dev Rebalance funds across strategies according to allocations
     * Delegates to RebalanceExecutor to reduce contract size
     */
    function rebalance() external whenNotPaused(PauseActions.PAUSE_REBALANCE) {
        if (address(rebalanceExecutor) == address(0)) revert InvalidInput("Rebalance executor not set");
        rebalanceExecutor.executeRebalance(address(this));
    }

    function instantWithdraw(uint256 shares, address receiver) internal returns (uint256) {
        if (shares == 0) revert InvalidInput("Invalid shares");
        if (balanceOf(msg.sender) < shares) revert InvalidInput("Insufficient balance");
        
        // Calculate expected assets
        uint256 expectedAssets = previewRedeem(shares);
        
        // Burn shares immediately (no pending shares)
        _burn(msg.sender, shares);
        
        // Get available liquid USDC
        uint256 available = IERC20(asset()).balanceOf(address(this)) - totalAssetsToRedeem;
        uint256 amountToTransfer;
        
        if (available >= expectedAssets) {
            // Full payment available
            IERC20(asset()).safeTransfer(receiver, expectedAssets);
            return expectedAssets; 
        } else {

            // Partial payment, queue remainder
            if (available > 0) {
                amountToTransfer += available;
                // IERC20(asset()).safeTransfer(receiver, available);
            }

            uint256 queuedAssets = expectedAssets - available;
            for (uint256 i = 0; i < strategies.length; i++) {
                if (!strategies[i].strategy.hasLockup()) {
                    uint256 assetsStaked = strategies[i].strategy.assetsOfUser(address(this));
                    if (assetsStaked >= queuedAssets) {
                        strategies[i].strategy.withdrawToken(queuedAssets);
                        amountToTransfer += queuedAssets;
                        queuedAssets = 0;
                        break;
                    }
                    else {
                        strategies[i].strategy.withdrawToken(assetsStaked); 
                        amountToTransfer += assetsStaked;
                        queuedAssets -= assetsStaked;
                    }
                    IERC4626 strategyVault = IERC4626(address(strategies[i].strategy));
                    strategyShares[address(strategies[i].strategy)] = strategyVault.balanceOf(address(this));
                }
            }
            if (amountToTransfer > 0) 
            IERC20(asset()).safeTransfer(receiver, amountToTransfer);
            if (amountToTransfer != expectedAssets) 
                revert InvalidInput("Insufficient assets to redeem instant withdraw");
            
            return expectedAssets;
        }
    }

    /**
     * @dev Request withdrawal by burning shares immediately
     * Pays available liquid USDC, queues remainder if needed
     * @param shares Number of shares to redeem
     * @return requestId Request ID (0 if fully paid immediately)
     */
    function requestQueuedWithdraw(uint256 shares, address receiver) internal returns (uint256) {

        if (shares == 0) revert InvalidInput("Invalid shares");
        if (balanceOf(msg.sender) < shares) revert InvalidInput("Insufficient balance");
        VaultStructs.WithdrawRequest storage existing = withdrawRequests[receiver];
        if (existing.requestId != 0 && !existing.claimed) {
            revert InvalidInput("Request already exists");
        }

        // Calculate expected assets
        uint256 expectedAssets = previewRedeem(shares);
        
        // Burn shares immediately (no pending shares)
        _burn(msg.sender, shares);
        
        // increment the next request id
        uint256 requestId = ++nextRequestId;

        
        // Initialize batch if it doesn't exist (batch starts at 1, but might not be initialized)
        if (withdrawBatchById[nextBatchId].withdrawRequestId == 0 && 
            withdrawBatchById[nextBatchId].totalAssetsToWithdrawFromStrategy == 0) {
            // Batch is uninitialized, initialize it
            withdrawBatchById[nextBatchId] = VaultStructs.WithdrawBatch({
                withdrawRequestId: 0,
                totalAssetsToWithdrawFromStrategy: 0,
                withdrawalLeftToBeProcessed: 0,
                expectedUnlockTimestamp: 0,
                claimEnabled: false
            });
        }
        
        withdrawBatchById[nextBatchId].totalAssetsToWithdrawFromStrategy += expectedAssets;
        withdrawRequests[receiver] = VaultStructs.WithdrawRequest({
            requestId: requestId,
            expectedAmount: expectedAssets,
            claimed: false
        });
        emit WithdrawRequested(requestId, msg.sender, expectedAssets);
        return requestId;
    }

    /**
     * @dev Claim queued withdrawal after strategies unlock
     */
    function claimWithdraw() external {
        VaultStructs.WithdrawRequest storage request = withdrawRequests[msg.sender];
        if (request.requestId == 0) revert InvalidInput("Invalid request");
        if (request.claimed) revert InvalidInput("Invalid request claimed");
        
        // Mark as claimed before transfer (reentrancy protection)
        request.claimed = true;

        // Check available balance (vault balance + totalAssetsToRedeem)
    
        if (totalAssetsToRedeem < request.expectedAmount) revert InvalidInput("Insufficient assets to redeem");
        totalAssetsToRedeem -= request.expectedAmount;
        console.log("totalAssetsToRedeem", totalAssetsToRedeem);
        console.log("request.expectedAmount", request.expectedAmount);
        console.log("usdc balance of msg.sender", IERC20(asset()).balanceOf(address(this)));
        
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
        return requestQueuedWithdraw(shares, receiver);
    }

    function instantWithdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        if (receiver != owner) revert InvalidInput("Invalid receiver");
        uint256 shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        // can cut some fees here if needed
        return instantWithdraw(shares, receiver);
    }

    /**
     * @dev Override redeem to use requestWithdraw
     */
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused(PauseActions.PAUSE_REDEEM) returns (uint256) {
        revert InvalidInput("Invalid redeem");
    }

    /**
     * @dev Override deposit to add checks
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused(PauseActions.PAUSE_DEPOSIT) returns (uint256) {

        if (assets == 0) revert InvalidInput("Invalid assets");
        if (receiver == address(0)) revert InvalidInput("Invalid receiver");

        return super.deposit(assets, receiver);
    }

    function depositToHyperCore(uint256 assets, address receiver) public returns (uint256) {
        if (assets == 0) revert InvalidInput("Invalid assets");
        if (receiver == address(0)) revert InvalidInput("Invalid receiver");
        coreWriter.write(2, abi.encode(assets, receiver));
        return assets;
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

    // ============ IMultiStrategyVaultRebalance Interface Functions ============
    // These functions are called by the RebalanceExecutor to modify vault state

    function strategiesLength() external view returns (uint256) {
        return strategies.length;
    }

    function depositToStrategy(IBaseStrategy strategy, uint256 amount) external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        IERC20 assetToken = IERC20(asset());
        SafeERC20.forceApprove(assetToken, address(strategy), amount);
        strategy.depositToken(amount);
        SafeERC20.forceApprove(assetToken, address(strategy), 0);
        
        IERC4626 strategyVault = IERC4626(address(strategy));
        strategyShares[address(strategy)] = strategyVault.balanceOf(address(this));
    }

    function withdrawFromStrategy(IBaseStrategy strategy, uint256 amount) external returns (uint256) {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        
        // Limit withdrawal to actual USDC balance in strategy (not virtual yield)
        uint256 actualBalance = IERC20(asset()).balanceOf(address(strategy));
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        if (amount > actualBalance) {
            amount = actualBalance;
        }
        
        if (amount > 0) {
            strategy.withdrawToken(amount);
            
            IERC4626 vault = IERC4626(address(strategy));
            strategyShares[address(strategy)] = vault.balanceOf(address(this));
            
            // Return actual amount withdrawn (check balance change)
            uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
            return balanceAfter - balanceBefore;
        }
        return 0;
    }

    function updateStrategyShares(address strategy, uint256 shares) external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        strategyShares[strategy] = shares;
    }

    function updateTotalAssetsToRedeem(uint256 amount) external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        totalAssetsToRedeem = amount;
    }

    function updateWithdrawBatch(uint256 batchId, VaultStructs.WithdrawBatch calldata batch) external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        withdrawBatchById[batchId] = batch;
    }

    function incrementNextBatchId() external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        nextBatchId++;
    }

    function emitRebalanced() external {
        if (msg.sender != address(rebalanceExecutor)) revert InvalidInput("Unauthorized");
        emit Rebalanced();
    }
}
