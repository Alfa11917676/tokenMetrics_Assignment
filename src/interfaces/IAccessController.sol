// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccessController.
 * @notice Interface
 * @author Metaborong.
 */
interface IAccessController {
    /// @notice Error thrown when setting role via non default admin.
    error NotDefaultAdmin();

    /// @notice Error thrown when trying to set init role entities with invalid enities address.
    error InvalidInitRoleSetter();

    /// @notice Error thrown when trying to set init role entities again.
    error RolesAlreadyInitialised();

    /// @notice Struct to initialize role setters during contract deployment.
    struct InitRoleSetter {
        address admin;
        address pauser;
        address manager;
        address unpauser;
        address dev;
    }

    /// @notice Ensures that an account has the specified role.
    function ensureEntityRole(bytes32 _role, address _account) external view returns (bool);

    /// @notice Converts a role name to its corresponding hash value.
    function getRoleHash(string memory _role) external pure returns (bytes32);
}
