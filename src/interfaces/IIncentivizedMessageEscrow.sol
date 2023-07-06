// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IIncentivizedMessageEscrow {
    // Packs to two slots.
    struct incentiveDescription {
        uint64 minGasDelivery;          // 0: 64/256 bytes
        uint64 minGasAck;               // 0: 128/256 bytes
        uint128 priceOfDeliveryGas;     // 0: 256/256 bytes
        uint128 priceOfAckGas;          // 1: 128/256 bytes
        uint128 totalIncentive;         // 1: 256/256 bytes
    }

    function escrowMessage(bytes32 destinationIdentifier, bytes32 target, bytes calldata message, incentiveDescription calldata incentive) external payable returns(uint256);

    function deliverMessage(bytes calldata message) external payable;
}