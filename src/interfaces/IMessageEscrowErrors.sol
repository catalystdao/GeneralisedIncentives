// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageEscrowErrors {
    error NotEnoughGasProvided(uint128 expected, uint128 actual);  // 030748b5
    error InvalidTotalIncentive(uint128 expected, uint128 actual);  // 79ddca92
    error MessageAlreadyBountied();  // 068a62ee
    error MessageDoesNotExist();  // 970e41ec
    error MessageAlreadyAcked();  // 8af35858
    error NotImplementedError();  // d41c17e7
    error feeRecipitentIncorrectFormatted(uint8 expected, uint8 actual);  // e3d86532
    error MessageAlreadySpent();  // e954aba2
    error TargetExecutionTimeInvalid(int128 difference);  // cf3b5fa4
    error DeliveryGasPriceMustBeIncreased();  // 39193a29
    error AckGasPriceMustBeIncreased();  // 553d8418
    error AckHasNotBeenExecuted();  // 3d1553f8
    error NoImplementationAddressSet();  // 9f994b4b
    error InvalidImplementationAddress();  // c970156c
    error IncorrectValueProvided(uint128 expected, uint128 actual); // 0b52a60b
    error ImplementationAddressAlreadySet(bytes currentImplementation); // dba47850
}