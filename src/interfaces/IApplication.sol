// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IApplication {
    function ackMessage(bytes32 sourceIdentifierbytes, bytes calldata acknowledgement) external;

    /// @notice receiveMessage from a cross-chain call.
    /// @dev The application needs to check the fromApplication combined with sourceIdentifierbytes to figure out if the call is authenticated.
    function receiveMessage(bytes32 sourceIdentifierbytes, bytes calldata fromApplication, bytes calldata message) external returns(bytes memory);
}