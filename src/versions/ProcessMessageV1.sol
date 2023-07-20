// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IProcessMessageEscrow } from "../interfaces/IProcessMessageEscrow.sol";

// TODO: Name
/**
 * @title Process Message implementation
 * @author Alexander @ Catalyst
 * @notice // TODO:
 */
abstract contract ProcessMessageV1 is IProcessMessageEscrow {
    /// @notice Verify a message's authenticity.
    /// @dev Should be overwritten by the specific messaging protocol verification structure.
    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata rawMessage) virtual internal returns(bytes calldata message);

    function implementationVersion() pure override external returns(string memory versionDescriptor) {
        return "ProcessMessageV1";
    }
}