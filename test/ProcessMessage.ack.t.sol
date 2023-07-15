// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";


contract AckMessageTest is TestCommon {
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

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return (messageIdentifier, messageWithContext);
    }

    function setupProcessMessage(bytes memory message, bytes memory destinationFeeRecipitent) internal returns(bytes memory) {
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

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return messageWithContext;
    }


    function setupForAck(bytes memory message, bytes memory destinationFeeRecipitent) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        return (messageIdentifier, setupProcessMessage(messageWithContext, destinationFeeRecipitent));
    }

    function test_ack_process_message() public {
        bytes memory message = _MESSAGE;
        bytes memory feeRecipitent = _DESTINATION_ADDRESS_THIS;

        bytes memory destinationFeeRecipitent = _DESTINATION_ADDRESS_THIS;

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(message, destinationFeeRecipitent);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        _receive = 6632150877;

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(_REFUND_GAS_TO.balance, _getTotalIncentive(_INCENTIVE) - _receive, "Refund");
    }

    // relayer incentives will be sent here
    receive() payable external {
        assertEq(msg.value, _receive, "Relayer Payment");
    }
}