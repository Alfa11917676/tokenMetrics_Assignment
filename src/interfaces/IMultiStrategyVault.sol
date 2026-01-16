 pragma solidity ^0.8.24;

 import {BaseStrategy as IBaseStrategy} from "./IBaseStrategy.sol";

 interface IMultiStrategyVault {

    // Errors
    error InvalidInput(string message);
    error ActionPaused();
    error AuthenticationFailed();

    // Storage structures
    struct StrategyConfig {
        IBaseStrategy strategy;
        uint256 allocationBps; // Basis points (0-5000 max per strategy)
    }

    struct WithdrawRequest {
        uint256 requestId;
        uint256 expectedAmount;
        bool claimed;
    }

    struct WithdrawBatch {
        uint256 withdrawRequestId;
        uint256 totalAssetsToWithdrawFromStrategy;
        uint256 withdrawalLeftToBeProcessed;
        uint256 expectedUnlockTimestamp;
        bool claimEnabled;
    }

     // Events
     event AllocationSet(uint256[] allocationsBps);
     event Rebalanced();
     event WithdrawRequested(uint256 indexed requestId, address indexed owner, uint256 assets);
     event WithdrawClaimed(uint256 indexed requestId);
     event StrategyAdded(IBaseStrategy indexed strategy, uint256 allocationBps);
 

}