// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IAccessController.sol";
import "../libraries/Roles.sol";
import { AccessControlDefaultAdminRules } from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/**
 * @title AccessController.
 * @notice Contract for managing access control roles and permissions.
 * @author Metaborong.
 */
contract AccessController is IAccessController, AccessControlDefaultAdminRules {
    /// @notice flag for denoting initial setup of entities in base roles.
    bool private initFlag;

    /// @notice Constructor to initialize the AccessController.
    /// @param _initialDelay Initial delay for admin role changes.
    /// @param _initialDefaultAdmin Address of the initial default admin.
    constructor(
        uint48 _initialDelay,
        address _initialDefaultAdmin
    ) AccessControlDefaultAdminRules(_initialDelay, _initialDefaultAdmin) {}

    /// @notice initialize the AccessController.
    /// @param initRoleSetter Struct containing initial role setters.
    function initTokenMetricsRoles(IAccessController.InitRoleSetter memory initRoleSetter) external {
        if (msg.sender != defaultAdmin()) revert NotDefaultAdmin();
        if (initFlag) revert RolesAlreadyInitialised();

        if (
            initRoleSetter.dev == address(0x0) ||
            initRoleSetter.pauser == address(0x0) ||
            initRoleSetter.unpauser == address(0x0) ||
            initRoleSetter.admin == address(0x0)
        ) revert InvalidInitRoleSetter();

        super.grantRole(Roles.DEV_ROLE, initRoleSetter.dev);
        super.grantRole(Roles.MANAGER_ROLE, initRoleSetter.manager);
        super.grantRole(Roles.ADMIN_ROLE, initRoleSetter.admin);
        super.grantRole(Roles.PAUSER_ROLE, initRoleSetter.pauser);
        super.grantRole(Roles.UNPAUSER_ROLE, initRoleSetter.unpauser);

        initFlag = true;
    }

    /// @notice Function to ensure whether an entity has a specific role.
    /// @param _role The role to check for.
    /// @param _account The address of the entity to check.
    /// @return A boolean indicating whether the entity has the role.
    function ensureEntityRole(bytes32 _role, address _account) external view returns (bool) {
        return super.hasRole(_role, _account);
    }

    /// @notice Function to get the hash of a role.
    /// @param _role The role for which the hash is needed.
    /// @return The keccak256 hash of the role.
    function getRoleHash(string memory _role) external pure returns (bytes32) {
        // Converting the role to bytes and returning its hash.
        return keccak256(bytes(_role));
    }
}
