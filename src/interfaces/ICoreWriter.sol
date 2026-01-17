// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICoreWriter
 * @dev Interface for HyperCore CoreWriter contract
 * Used for interacting with HyperCore protocol actions
 */
interface ICoreWriter {
    function write(
        uint8 actionId,
        bytes calldata data
    ) external;
}
