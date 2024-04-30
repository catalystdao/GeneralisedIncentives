// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMessageEscrowErrors {
    error AckHasNotBeenExecuted(); // 0x3d1553f8
    error CannotRetryWrongMessage(bytes32,bytes32); // 0x48ce7fac
    error DeadlineInPast(uint64 blocktimestamp, uint64 actual); // 0x2d098d59
    error DeadlineNotPassed(uint64 expected, uint64 actual); // 0x862c57f4
    error DeadlineTooLong(uint64 maxAllowed, uint64 actual); // 0x3c06f369
    error ImplementationAddressAlreadySet(bytes currentImplementation); // 0xdba47850
    error IncorrectValueProvided(uint128 expected, uint128 actual); // 0x0b52a60b
    error InvalidImplementationAddress(); // 0xc970156c
    error InvalidTimeoutPackage(bytes32 expected, bytes32 actual); // 0xe020885d
    error MessageAlreadyAcked(); // 0x8af35858
    error MessageAlreadyBountied(); // 0x068a62ee
    error MessageAlreadyProcessed(); // 0x7b042609
    error MessageAlreadySpent(); // 0xe954aba2
    error MessageDoesNotExist(); // 0x970e41ec
    error MessageHasInvalidContext(); // 0x3fcdbaba
    error NoImplementationAddressSet(); // 0x9f994b4b
    error NotEnoughGasExecution(); // 0x6bc33587
    error NotEnoughGasProvided(uint128 expected, uint128 actual);    // 0x030748b5
    error NotImplementedError(); // 0xd41c17e7
    error RefundGasToIsZero(); // 0x6a1a6afe
    error SendLostGasToAddress0(); // 0x470337f2
}