// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";


contract TimeOverflowTest is TestCommon {
    event AckMessage(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes acknowledgement);

    uint256 constant GAS_SPENT_ON_SOURCE = 8120;
    uint256 constant GAS_SPENT_ON_DESTINATION = 33657;
    uint256 constant GAS_RECEIVE_CONSTANT = 6625863948;

    uint256 _receive;

    event ReceiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes fromApplication,
        bytes message,
        bytes acknowledgement
    );
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function setupEscrowMessage(bytes memory message) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (uint256 gasRefund, bytes32 messageIdentifier) = application.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return (messageIdentifier, messageWithContext);
    }

    function setupProcessMessage(bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(message);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.recordLogs();
        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            message,
            destinationFeeRecipitent
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[entries.length - 1].data, (bytes32, bytes, bytes));

        return messageWithContext;
    }


    function setupForAck(bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        return (messageIdentifier, setupProcessMessage(messageWithContext, destinationFeeRecipitent));
    }

    function test_larger_than_uint_time_is_fine() public {
        vm.warp(2**64 + 1 days);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(message, destinationFeeRecipitent);

        vm.warp(2**64 + 1 days + _INCENTIVE.targetDelta);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory _acknowledgement = abi.encode(bytes32(0xd9b60178cfb2eb98b9ff9136532b6bd80eeae6a2c90a2f96470294981fcfb62b));

        vm.expectEmit();
        emit AckMessage(_DESTINATION_IDENTIFIER, messageIdentifier, _acknowledgement);
        vm.expectEmit();
        emit MessageAcked(messageIdentifier);

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;

        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(gas_on_destination),
            uint64(gas_on_source),
            uint128(BOB_incentive),
            uint128(_receive)
        );

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(BOB.balance, BOB_incentive, "BOB incentive");
    }

    // This function tests the following snippit of the code
    // unchecked {
    //     executionTime = uint64(block.timestamp) - uint64(bytes8(message[CTX1_EXECUTION_TIME_START:CTX1_EXECUTION_TIME_END]));
    // }
    function test_overflow_in_unchecked_is_fine() public {
        uint256 timeDiff = _INCENTIVE.targetDelta;
        uint256 initialTime = 2**64 - 1 - timeDiff/2;
        uint256 postTime = initialTime + timeDiff;
        require(uint64(initialTime) > uint64(postTime));  // This is what we want to ensure works properly.
        vm.warp(initialTime);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(message, destinationFeeRecipitent);

        vm.warp(postTime);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory _acknowledgement = abi.encode(bytes32(0xd9b60178cfb2eb98b9ff9136532b6bd80eeae6a2c90a2f96470294981fcfb62b));

        vm.expectEmit();
        emit AckMessage(_DESTINATION_IDENTIFIER, messageIdentifier, _acknowledgement);
        vm.expectEmit();
        emit MessageAcked(messageIdentifier);

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;

        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(gas_on_destination),
            uint64(gas_on_source),
            uint128(BOB_incentive),
            uint128(_receive)
        );

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(BOB.balance, BOB_incentive, "BOB incentive");
    }

    // relayer incentives will be sent here
    receive() payable external {
        assertEq(msg.value, _receive, "Relayer Payment");
    }
}