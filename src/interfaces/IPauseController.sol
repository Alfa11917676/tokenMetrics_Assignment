// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPauseController.
 * @notice Interface for controlling pause and unpause actions.
 * @author Metaborong.
 */
interface IPauseController {
    /// @notice Error thrown when Input address is zero.
    error InputAddressZero();

    /// @notice Error thrown when authentication fails.
    error AuthenticationFailed();

    /// @notice Error thrown when an action is already paused.
    error ActionAlreadyPaused();

    /// @notice Error thrown when an action is already unpaused.
    error ActionAlreadyUnPaused();

    /// @notice Emitted when an action is paused.
    event LogActionPaused(address indexed _pausedBy, bytes32 indexed _pauseType);

    /// @notice Emitted when an action is unpaused.
    event LogActionUnPaused(address indexed _unPausedBy, bytes32 indexed _pauseType);

    /// @notice Pauses all actions.
    function pauseAllActions() external;

    /// @notice Pauses a specific action.
    function pauseAction(bytes32 _actionHash) external;

    /// @notice Unpauses all actions.
    function unpauseAllActions() external;

    /// @notice Unpauses a specific action.
    function unpauseAction(bytes32 _actionHash) external;

    /// @notice Checks if a specific action is paused.
    function isActionPaused(bytes32 _actionHash) external view returns (bool);

    /// @notice Gets the hash of an action.
    function getActionHash(string memory _action) external pure returns (bytes32);
}
