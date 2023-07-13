// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";


contract ProcessMessageTest is TestCommon {
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
        (uint256 gasRefund, bytes32 messageIdentifier) = application.escrowMessage{value: _INCENTIVE.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return (messageIdentifier, messageWithContext);
    }

    function test_call_process_message() public {
        bytes memory message = _MESSAGE;
        bytes memory feeRecipitent = _DESTINATION_ADDRESS_THIS;

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory mockAck = abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));

        vm.expectEmit();
        // Check that the application was called
        emit ReceiveMessage(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            mockAck
        );
        vm.expectEmit();
        // That a new message is sent back
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                bytes32(uint256(uint160(address(escrow))))
            ),
            abi.encodePacked(
                _DESTINATION_IDENTIFIER,
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_APPLICATION,
                feeRecipitent,
                uint128(0x8163),  // Gas used
                uint64(1),
                mockAck
            )
        );
        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageDelivered(messageIdentifier);

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }

    function test_call_process_message_twice() public {
        bytes memory message = _MESSAGE;
        bytes memory feeRecipitent = _DESTINATION_ADDRESS_THIS;

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadySpent()")
        ); 
        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }
}