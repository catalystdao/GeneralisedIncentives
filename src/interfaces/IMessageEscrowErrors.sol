// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMessageEscrowErrors {
    error NotEnoughGasProvided(uint128 expected, uint128 actual);  // 030748b5
    error MessageAlreadyBountied();  // 068a62ee
    error MessageDoesNotExist();  // 970e41ec
    error MessageAlreadyAcked();  // 8af35858
    error NotImplementedError();  // d41c17e7
    error MessageAlreadySpent();  // e954aba2
    error AckHasNotBeenExecuted();  // 3d1553f8
    error NoImplementationAddressSet();  // 9f994b4b
    error InvalidImplementationAddress();  // c970156c
    error IncorrectValueProvided(uint128 expected, uint128 actual); // 0b52a60b
    error ImplementationAddressAlreadySet(bytes currentImplementation); // dba47850
    error NotEnoughGasExecution(); // 6bc33587
    error RefundGasToIsZero(); // 6a1a6afe
    error DeadlineTooLong(uint64 maxAllowed, uint64 actual); // 54090af9
    error DeadlineInPast(uint64 blocktimestamp, uint64 actual); // 2d098d59
    error CannotRetryWrongMessage(bytes32 expected, bytes32 actual); // 48ce7fac
    error MessageAlreadyProcessed(); // 7b042609
    error DeadlineNotPassed(uint64 expected, uint64 actual); // 862c57f4
    error InvalidTimeoutPackage(bytes32 expected, bytes32 actual); // e020885d
    error MessageHasInvalidContext(); // 3fcdbaba
    error RouteDisabled();
}