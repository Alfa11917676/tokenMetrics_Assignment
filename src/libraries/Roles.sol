// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Roles.
 * @notice Library defining role constants for access control.
 * @author Metaborong.
 */
library Roles {
    /// @notice Role identifier for TokenMetrics Admin Role.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role identifier for TokenMetrics Dev Role
    bytes32 public constant DEV_ROLE = keccak256("DEV_ROLE");

    /// @notice Role identifier for timelock contract.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    /// @notice Role identifier for pausers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role identifier for unpausers.
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Role identifier for token minter.
    bytes32 public constant TOKEN_MINTER_ROLE = keccak256("TOKEN_MINTER_ROLE");

     /// @notice Role identifier for manager.
     bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

}
