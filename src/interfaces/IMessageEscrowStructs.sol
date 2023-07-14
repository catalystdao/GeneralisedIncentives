// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageEscrowStructs {
    struct IncentiveDescription {
        uint48 maxGasDelivery;      // 0: 6/32 bytes
        uint48 maxGasAck;           // 0: 12/32 bytes
        address refundGasTo;        // 0: 32/32 bytes
        uint96 priceOfDeliveryGas;  // 1: 12/32 bytes
        uint96 priceOfAckGas;       // 1: 24/32 bytes
        uint64 targetDelta;         // 1: 32/32 bytes
    }
}
