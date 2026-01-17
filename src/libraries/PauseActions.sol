// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PauseActions.
 * @notice Library defining pause action constants for pause control.
 * @author Metaborong.
 */
library PauseActions {
    /// @notice Pause type identifier for pausing all functionalities.
    bytes32 public constant PAUSE_ALL = keccak256("PAUSE_ALL");

    /// @notice Pause type identifier for pausing upgrade functionalities.
    bytes32 public constant PAUSE_UPGRADES = keccak256("PAUSE_UPGRADES");

    /// @notice Pause type identifier for pausing configuration update functionality.
    bytes32 public constant PAUSE_CONFIG_UPDATE = keccak256("PAUSE_CONFIG_UPDATE");

    /// @notice Pause type identifier for pausing token deposit functionality.
    bytes32 public constant PAUSE_DEPOSIT = keccak256("PAUSE_DEPOSIT");

    /// @notice Pause type identifier for pausing token invest functionality.
    bytes32 public constant PAUSE_INVEST = keccak256("PAUSE_INVEST");

    /// @notice Pause type identifier for pausing token withdraw functionality.
    bytes32 public constant PAUSE_WITHDRAW = keccak256("PAUSE_WITHDRAW");

    /// @notice Pause type identifier for pausing token redeem functionality.
    bytes32 public constant PAUSE_REDEEM = keccak256("PAUSE_REDEEM");

    /// @notice Pause type identifier for pausing token rebalance functionality.
    bytes32 public constant PAUSE_REBALANCE = keccak256("PAUSE_REBALANCE");

    // pause mint and pause deposit
    bytes32 public constant PAUSE_MINT = keccak256("PAUSE_MINT");
    /// @notice Pause type identifier for pausing token deposit functionality.
}
