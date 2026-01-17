// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

contract MockCoreWriter is ICoreWriter {
    event ActionWritten(uint8 actionId, bytes data);

    function write(
        uint8 actionId,
        bytes calldata data
    ) external override {
        emit ActionWritten(actionId, data);
    }
}
