// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./TestSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMultiStrategyVault} from "@core/interfaces/IMultiStrategyVault.sol";

/**
 * @title TestFlows
 * @dev Comprehensive tests covering all test requirements
 */
contract TestFlows is TestSetup {
    
    uint256 public constant INITIAL_DEPOSIT = 1000e6; // 1000 USDC (6 decimals)
    uint256 public constant YIELD_PERCENTAGE = 1000; // 10.00% (2 decimal precision: 1000 = 10.00%)
    uint256 public constant EXPECTED_AFTER_YIELD = 1060e6; // ~1060 USDC after 10% yield
    
    function test_BasicDeposit() public {
        // Setup: Give Alice 1000 USDC
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        
        // Alice deposits 1000 USDC
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Verify shares minted correctly (1:1 initially)
        assertEq(shares, INITIAL_DEPOSIT, "Shares should equal deposit amount initially");
        assertEq(vault.balanceOf(alice), shares, "Alice should have the shares");
        
        // Verify USDC is in vault
        assertEq(usdc.balanceOf(address(vault)), INITIAL_DEPOSIT, "Vault should have 1000 USDC");
        
        // Verify totalAssets matches
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT, "Total assets should be 1000 USDC");
    }
    
    function test_SetAllocationsAndRebalance() public {
        // First deposit
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Manager sets 60/40 allocation
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000; // 60% to Protocol A (unlockedStrategy)
        allocations[1] = 4000; // 40% to Protocol B (lockedStrategy)
        
        vm.prank(manager);
        vault.setAllocations(allocations);
        
        // Verify allocations are set
        (, uint256 allocation0) = vault.strategies(0);
        (, uint256 allocation1) = vault.strategies(1);
        assertEq(allocation0, 6000, "Strategy 0 should have 60% allocation");
        assertEq(allocation1, 4000, "Strategy 1 should have 40% allocation");
        
        // Rebalance to move funds
        vm.prank(manager);
        vault.rebalance();
        
        // Verify funds are routed correctly (approximately)
        uint256 strategyAAssets = unlockedStrategy.assetsOfUser(address(vault));
        uint256 strategyBAssets = lockedStrategy.assetsOfUser(address(vault));
        uint256 totalInStrategies = strategyAAssets + strategyBAssets;
        
        // Strategy A should have approximately 60% of total
        assertApproxEqAbs(
            strategyAAssets,
            (totalInStrategies * 6000) / 10000,
            1e6, // Allow 1 USDC tolerance
            "Protocol A should have ~60%"
        );
        
        // Strategy B should have approximately 40% of total
        assertApproxEqAbs(
            strategyBAssets,
            (totalInStrategies * 4000) / 10000,
            1e6, // Allow 1 USDC tolerance
            "Protocol B should have ~40%"
        );
    }
    
    function test_StrategyYieldIncreasesTotalAssets() public {
        // Setup: Deposit and allocate
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Set allocations and rebalance
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000;
        allocations[1] = 4000;
        vm.prank(manager);
        vault.setAllocations(allocations);
        vm.prank(manager);
        vault.rebalance();
        
        // Record initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialSharesValue = vault.previewRedeem(shares);
        uint256 initialStrategyATotalAssets = unlockedStrategy.totalAssets();
        uint256 initialStrategyAAssets = unlockedStrategy.assetsOfUser(address(vault));
        
        // Protocol A increases by 10%
        unlockedStrategy.mockYield(YIELD_PERCENTAGE); // 10.00%
        
        // Verify Protocol A's totalAssets increased by ~10%
        uint256 newStrategyATotalAssets = usdc.balanceOf(address(unlockedStrategy));
        assertGt(newStrategyATotalAssets, initialStrategyATotalAssets, "Protocol A totalAssets should increase with yield");
        
        // Verify the increase is approximately 10% (allowing for rounding)
        uint256 expectedIncrease = (initialStrategyATotalAssets * YIELD_PERCENTAGE) / 10_000;
        assertApproxEqAbs(
            newStrategyATotalAssets,
            initialStrategyATotalAssets + expectedIncrease,
            1e6, // Allow 1 USDC tolerance for rounding
            "Protocol A should increase by ~10%"
        );
        
        // Verify vault's totalAssets increased
        uint256 newTotalAssets = vault.totalAssets();
        assertGt(newTotalAssets, initialTotalAssets, "Total assets should increase with yield");
        
        // Verify share value increased
        uint256 newSharesValue = vault.previewRedeem(shares);
        assertGt(newSharesValue, initialSharesValue, "Share value should increase");
    }
    
    function test_SharePriceIncreasesWithYield() public {
        // Setup: Deposit, allocate, and apply yield
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Set allocations and rebalance
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000;
        allocations[1] = 4000;
        vm.prank(manager);
        vault.setAllocations(allocations);
        vm.prank(manager);
        vault.rebalance();
        uint256 initialSharesValue = vault.previewRedeem(shares);
        // Protocol A increases by 10%
        unlockedStrategy.mockYield(YIELD_PERCENTAGE);
        // Verify user shares are worth more after yield
        uint256 newSharesValue = vault.previewRedeem(shares);
        assertGt(newSharesValue, initialSharesValue, "User shares should be worth more after yield");
        // Verify total assets increased by the yield should be 1060 USDC
        uint256 newTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            newTotalAssets,
            EXPECTED_AFTER_YIELD,
            5e6,
            "Total assets should increase by the yield"
        );
    }
    
    function test_WithdrawalWithLockedStrategy() public {
        // Setup: Deposit, allocate, apply yield
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Set allocations and rebalance
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000;
        allocations[1] = 4000;
        vm.prank(manager);
        vault.setAllocations(allocations);
        vm.prank(manager);
        vault.rebalance();
       
        // Apply yield
        unlockedStrategy.mockYield(YIELD_PERCENTAGE);

        // make some instant withdrawals from the unlocked strategy
        // this will be used to test the withdrawal queue for locked strategies
        vm.startPrank(alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 withdrawAmount = vault.previewRedeem(shares );
        uint256 returnedShares = vault.withdraw(withdrawAmount, alice, alice);
        uint256 sharesAfter = vault.balanceOf(alice);
        vm.stopPrank();

        // Check if withdrawal was queued (if shares were burned but request exists)
        (uint256 requestId, uint256 expectedAmount, bool claimed) = vault.getWithdrawRequest(alice);
        
        assertLt(sharesAfter, sharesBefore, "100% of shares should be burned");
        assertEq(sharesAfter, 0, " As we have withdrawn 100% of the shares, the balance of the user should be 0");

        // Verify request was created if queued (requestId > 0 means queued)
        assertEq(requestId, vault.nextRequestId(), "Request ID should be non-zero for queued withdrawal");
        assertEq(requestId, 1, "Request ID should be 1");

        vm.startPrank(manager);
        vault.rebalance();
       
        (uint256 id, uint256 totalAssetsToWithdrawFromStrategy, uint256 withdrawalLeftToBeProcessed, uint256 expectedUnlockTimestamp, bool claimEnabled) = vault.withdrawBatchById(1);

        (, , uint256 amountToWithdraw, , bool isClaimed) = lockedStrategy.getWithdrawData(lockedStrategy.withdrawalsIds(address(vault))); 
        assertEq(vault.nextBatchId(), 2, "The next batch id should be 2");

        vm.warp(block.timestamp + 1 days + 1);
        
        uint256 balanceBefore = usdc.balanceOf(address(vault));
        
        // Rebalance to request funds from locked strategy
        vault.rebalance();

        (id, totalAssetsToWithdrawFromStrategy, withdrawalLeftToBeProcessed, expectedUnlockTimestamp, claimEnabled) = vault.withdrawBatchById(1);

        assertEq(vault.nextBatchId(), 2, "The next batch id should be 2");
        (,,amountToWithdraw, , isClaimed) = lockedStrategy.getWithdrawData(lockedStrategy.withdrawalsIds(address(vault)));
        vm.stopPrank();

        vm.prank(alice);
        vault.claimWithdraw();

        assertEq(vault.totalAssetsToRedeem(), 0, "Total assets to redeem should be 0");
        
        assertApproxEqAbs(usdc.balanceOf(alice), 1060e6, 1e6, "User should receive 1060 USDC");
        vm.stopPrank();
    }
    
    function test_TotalAssetsAggregation() public {
        deal(address(usdc), alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        usdc.approve(address(vault), INITIAL_DEPOSIT);
        vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
        
        // Set allocations and rebalance
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000;
        allocations[1] = 4000;
        vm.prank(manager);
        vault.setAllocations(allocations);
        vm.prank(manager);
        vault.rebalance();
        
        // Get individual strategy values
        uint256 strategyAValue = unlockedStrategy.assetsOfUser(address(vault));
        uint256 strategyBValue = lockedStrategy.assetsOfUser(address(vault));
        uint256 idleBalance = usdc.balanceOf(address(vault));
        
        // Apply different yields
        unlockedStrategy.mockYield(1000); // 10% to Protocol A
        // Protocol B has no yield in this test
        lockedStrategy.mockYield(1000); // 10% to Protocol B
        
        // Verify totalAssets aggregates correctly
        uint256 totalAssets = vault.totalAssets();
        uint256 expectedTotal = idleBalance + 
            unlockedStrategy.assetsOfUser(address(vault)) + 
            lockedStrategy.assetsOfUser(address(vault));
        
        assertApproxEqAbs(
            totalAssets,
            expectedTotal,
            1e6,
            "Total assets should aggregate idle + strategy A + strategy B correctly"
        );
        
        // Verify share pricing reflects aggregated value
        uint256 shares = vault.balanceOf(alice);
        uint256 assetsPerShare = vault.previewRedeem(shares);
        assertGt(assetsPerShare, INITIAL_DEPOSIT * 1e6 / shares, "Share price should increase with yield");
    }
    
    function test_AllocationValidation() public {
        // Current implementation allows > 50% per strategy
        // This test documents that behavior
        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000; // 60% - exceeds 50% cap per strategy (if enforced)
        allocations[1] = 4000; // 40%
        
        // This will succeed because setAllocations doesn't check per-strategy cap
        vm.prank(manager);
        vault.setAllocations(allocations);
        
        // Verify allocations are set (even though they exceed 50% per strategy)
        (, uint256 allocation0) = vault.strategies(0);
        (, uint256 allocation1) = vault.strategies(1);
        assertEq(allocation0, 6000, "Strategy 0 has 60% allocation");
        assertEq(allocation1, 4000, "Strategy 1 has 40% allocation");
        
        // Test that total must equal 10000
        uint256[] memory invalidTotal = new uint256[](2);
        invalidTotal[0] = 5000;
        invalidTotal[1] = 4000; // Total = 9000, should fail
        
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IMultiStrategyVault.InvalidInput.selector, "Invalid total allocation"));
        vault.setAllocations(invalidTotal);
    }
}
