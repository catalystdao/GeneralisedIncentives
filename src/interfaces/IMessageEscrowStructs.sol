// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageEscrowStructs {
    struct IncentiveDescription {
        uint64 minGasDelivery;      // 0: 8/32 bytes
        uint64 minGasAck;           // 0: 16/32 bytes
        uint128 totalIncentive;     // 0: 32/32 bytes
        uint96 priceOfDeliveryGas;  // 1: 12/32 bytes
        uint96 priceOfAckGas;       // 1: 24/32 bytes
        uint64 targetDelta;         // 1: 32/32 bytes
    }
}
