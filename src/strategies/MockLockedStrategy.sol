// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockERC4626Strategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

/**
 * @title MockLockedStrategy
 * @dev Strategy with a lockup period
 * Extends MockERC4626Strategy but prevents withdrawals before unlock timestamp
 */
contract MockLockedStrategy is MockERC4626Strategy {
    uint256 public unlockTimestamp;
    uint256 public nextRequestId;
    uint256 private _virtualYieldPercent;
    struct WithdrawRequest {
        uint256 requestId;
        address receiver;
        uint256 expectedAmount;
        uint256 unlockTimestamp;
        bool claimed;
    }
    mapping(uint256 => WithdrawRequest) public withdrawRequests;
    mapping(address => uint256) public withdrawalsIds;

    constructor(IERC20 asset_, uint256 lockupDuration_) MockERC4626Strategy(asset_) {
        unlockTimestamp = lockupDuration_;
    }

    /**
     * @dev Deposit assets into the strategy
     * @param assets Amount of assets to deposit
     */
    function depositToken(uint256 assets) external override {
        deposit(assets, msg.sender);
    }

    /**
     * @dev Withdraw assets from the strategy
     * @param assets Amount of assets to withdraw
     */
    function withdrawToken(uint256 assets) external override {
        // initiate the withdrawal by starting the lockin period
        // give 2% interest on the assets
        uint256 requestId = nextRequestId++;

        withdrawRequests[requestId] = WithdrawRequest({
            requestId: requestId,
            expectedAmount: assets,
            receiver: msg.sender,
            unlockTimestamp: block.timestamp + unlockTimestamp,
            claimed: false
        });
        withdrawalsIds[msg.sender] = requestId;
    }

    function redeemFunds(uint256 requestId) external returns (uint256) {
        WithdrawRequest storage request = withdrawRequests[requestId];
        if (request.receiver != msg.sender) revert InvalidInput("Invalid request receiver");
        if (request.claimed) revert InvalidInput("Invalid request claimed");
        
        // Check if the request is unlocked
        if (block.timestamp < request.unlockTimestamp) revert InvalidInput("Request not unlocked");
        request.claimed = true;
        delete withdrawalsIds[msg.sender];

        IERC20(asset()).transfer(request.receiver, request.expectedAmount);
        return request.expectedAmount;
    }

    function convertToAssets(uint256 shares) public override view virtual returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }



    function getWithdrawData(uint256 requestId) external view returns (uint256, address, uint256, uint256, bool) {
        WithdrawRequest storage request = withdrawRequests[requestId];
        return (request.requestId, request.receiver, request.expectedAmount, request.unlockTimestamp, request.claimed);
    }

    /**
     * @dev Check if the strategy has a lockup period
     * @return true (this strategy has a lockup)
     */
    function hasLockup() external pure override returns (bool) {
        return true;
    }

    /**
     * @dev Check if the strategy is unlocked
     * @return true if current timestamp >= unlockTimestamp, false otherwise
     */
    function isUnlocked() external view override returns (bool) {
        return block.timestamp >= unlockTimestamp;
    }
}
