// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IIncentivizedMessageEscrow {
    error NotEnoughGasProvided(uint128 expected, uint128 actual);
    error InvalidTotalIncentive(uint128 expected, uint128 actual);
    error ZeroIncentiveNotAllowed();
    error MessageAlreadyBountied();
    error NotImplementedError();
    error feeRecipitentIncorrectFormatted(uint8 expected, uint8 actual);
    error MessageAlreadySpent();
    error TargetExecutionTimeInvalid(int128 difference);

    
    // Packs to two slots.
    struct incentiveDescription {
        uint64 minGasDelivery;      // 0: 8/32 bytes
        uint64 minGasAck;           // 0: 16/32 bytes
        uint128 totalIncentive;     // 0: 32/32 bytes
        uint96 priceOfDeliveryGas;  // 1: 12/32 bytes
        uint96 priceOfAckGas;       // 1: 24/32 bytes
        uint64 targetDelta;         // 1: 32/32 bytes
    }
    

    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        incentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier);

    function processMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata message, bytes calldata feeRecipitent) external;
}