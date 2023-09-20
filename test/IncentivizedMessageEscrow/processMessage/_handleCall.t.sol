// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";


contract ProcessMessageCallTest is TestCommon {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function test_call_process_message() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(address(application), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory mockAck = abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));
        
        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageDelivered(messageIdentifier);
        vm.expectEmit();
        // That a new message is sent back
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encode(
                escrow
            ),
            abi.encodePacked(
                _DESTINATION_IDENTIFIER,
                _DESTINATION_IDENTIFIER,
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_APPLICATION,
                feeRecipitent,
                uint48(0x82a3),  // Gas used
                uint64(1),
                mockAck
            )
        );

        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"1400000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b",
                    hex"b10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }

    function test_call_process_message_twice() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (, bytes memory messageWithContext) = setupEscrowMessage(address(application), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadySpent()")
        ); 
        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }

    function test_expect_caller(address caller) public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        vm.prank(caller);
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(escrow));

        vm.recordLogs();
        vm.deal(caller, _getTotalIncentive(_INCENTIVE));
        vm.prank(caller);
        (, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));


        (bytes memory _metadata, bytes memory newMessage) = getVerifiedMessage(address(escrow), messageWithContext);
        
        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    abi.encodePacked(
                        uint8(20),
                        bytes32(0),
                        bytes32(uint256(uint160(caller)))
                    ),
                    hex"b10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        escrow.processMessage(
            _metadata,
            newMessage,
            feeRecipitent
        );
    }
}