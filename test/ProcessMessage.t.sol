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

    function addContextToMessage(bytes memory message) internal returns(bytes memory) {
        vm.recordLogs();
        application.escrowMessage{value: _INCENTIVE.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory message) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return message;
    }

    function test_call_process_message() public {
        bytes memory message = _MESSAGE;
        bytes memory feeRecipitent = _DESTINATION_ADDRESS_THIS;

        bytes memory messageWithContext = addContextToMessage(message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory mockAck = abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));

        bytes32 messageIdentifier = 0x561213edd20145c0e5b7e2f9303e83b75eb429046e9bddac10f0d8b1d53be42e;

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
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_APPLICATION,
                feeRecipitent,
                uint128(0x8117),  // Gas used
                uint64(1),
                mockAck
            )
        );
        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageDelivered(messageIdentifier);

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,  // This value is not checked by the mock.
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }
}