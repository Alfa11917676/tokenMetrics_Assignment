// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IAccessController.sol";
import "../interfaces/IPauseController.sol";
import "../libraries/PauseActions.sol";
import "../libraries/Roles.sol";

/**
 * @title PauseController.
 * @notice Contract for controlling pause and unpause actions based on access control roles.
 * @author Metaborong.
 */
contract PauseController is IPauseController {
    /// @notice Instance of the AccessController interface.
    IAccessController public immutable accessController;

    /// @notice Mapping to track the pause status of actions.
    mapping(bytes32 => bool) internal paused;

    /// @notice Modifier to restrict access to only pausers or unpausers.
    modifier onlyPauserOrUnpauser(bytes32 _role) {
        if (!accessController.ensureEntityRole(_role, msg.sender)) revert AuthenticationFailed();
        _;
    }

    /// @notice Constructor to initialize the PauseController with an access controller.
    /// @param _accessController Address of the access controller contract.
    constructor(address _accessController) {
        if (_accessController == address(0x0)) revert InputAddressZero();
        accessController = IAccessController(_accessController);
    }

    /// @notice Pauses all actions.
    function pauseAllActions() external onlyPauserOrUnpauser(Roles.PAUSER_ROLE) {
        _pause(PauseActions.PAUSE_ALL);
    }

    /// @notice Pauses a specific action.
    /// @param _actionHash The hash representing the action to be paused.
    function pauseAction(bytes32 _actionHash) external onlyPauserOrUnpauser(Roles.PAUSER_ROLE) {
        _pause(_actionHash);
    }

    /// @notice Unpauses all actions.
    function unpauseAllActions() external onlyPauserOrUnpauser(Roles.UNPAUSER_ROLE) {
        _unpause(PauseActions.PAUSE_ALL);
    }

    /// @notice Unpauses a specific action.
    /// @param _actionHash The hash representing the action to be unpaused.
    function unpauseAction(bytes32 _actionHash) external onlyPauserOrUnpauser(Roles.UNPAUSER_ROLE) {
        _unpause(_actionHash);
    }

    /// @notice Checks if a specific action is paused.
    /// @param _actionHash The hash representing the action to check.
    /// @return A boolean indicating whether the action is paused.
    function isActionPaused(bytes32 _actionHash) external view returns (bool) {
        return (paused[_actionHash] || paused[PauseActions.PAUSE_ALL]);
    }

    /// @notice Gets the hash of an action.
    /// @param _action The name of the action for which the hash is needed.
    /// @return The keccak256 hash of the action name.
    function getActionHash(string memory _action) external pure returns (bytes32) {
        bytes memory actionInBytes = bytes(_action);
        return keccak256(actionInBytes);
    }

    /// @notice Internal function to pause an action.
    /// @param _actionHash The hash representing the action to be paused.
    function _pause(bytes32 _actionHash) internal {
        if (paused[_actionHash]) revert ActionAlreadyPaused();

        paused[_actionHash] = true;
        emit LogActionPaused(msg.sender, _actionHash);
    }

    /// @notice Internal function to unpause an action.
    /// @param _actionHash The hash representing the action to be unpaused.
    function _unpause(bytes32 _actionHash) internal {
        if (!paused[_actionHash]) revert ActionAlreadyUnPaused();

        paused[_actionHash] = false;
        emit LogActionUnPaused(msg.sender, _actionHash);
    }
}
