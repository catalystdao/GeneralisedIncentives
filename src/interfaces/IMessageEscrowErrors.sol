// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMessageEscrowErrors {
    error NotEnoughGasProvided(uint128 expected, uint128 actual);
    error InvalidTotalIncentive(uint128 expected, uint128 actual);
    error MessageAlreadyBountied();
    error MessageDoesNotExist();
    error MessageAlreadyAcked();
    error NotImplementedError();
    error feeRecipitentIncorrectFormatted(uint8 expected, uint8 actual);
    error MessageAlreadySpent();
    error TargetExecutionTimeInvalid(int128 difference);
    error DeliveryGasPriceMustBeIncreased();
    error AckGasPriceMustBeIncreased();
    error AckHasNotBeenExecuted();
    error NoImplementationAddressSet();
    error InvalidImplementationAddress();
}