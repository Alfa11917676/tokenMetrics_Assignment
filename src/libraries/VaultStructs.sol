// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseStrategy as IBaseStrategy} from "../interfaces/IBaseStrategy.sol";

/**
 * @title VaultStructs
 * @dev Library containing shared structs for MultiStrategyVault
 */
library VaultStructs {
    struct StrategyConfig {
        IBaseStrategy strategy;
        uint256 allocationBps;
    }

    struct WithdrawBatch {
        uint256 withdrawRequestId;
        uint256 totalAssetsToWithdrawFromStrategy;
        uint256 withdrawalLeftToBeProcessed;
        uint256 expectedUnlockTimestamp;
        bool claimEnabled;
    }

    struct WithdrawRequest {
        uint256 requestId;
        uint256 expectedAmount;
        bool claimed;
    }
}
