// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { Bytes65 } from "../../src/utils/Bytes65.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "../../src/MessagePayload.sol";

contract TimeoutMessageTest is TestCommon, Bytes65 {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipient,
        bytes message
    );

    function test_timeout_message(bytes calldata message) public {
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));


        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);
        
        vm.expectEmit();
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            bytes.concat(
                _DESTINATION_IDENTIFIER,
                _DESTINATION_IDENTIFIER,
                CTX_TIMEDOUT_ON_DESTINATION,
                this.memorySlice(rawSubmitMessage, MESSAGE_IDENTIFIER_START, FROM_APPLICATION_END),
                this.memorySlice(rawSubmitMessage, CTX0_DEADLINE_START, CTX0_DEADLINE_END),
                bytes32(block.number),
                message
            )
        );

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            rawSubmitMessage
        );
    }

    function test_message_cannot_be_timeouted_after_exec(bytes calldata message) public {
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));


        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message);

        // Ready for ack.
        setupprocessPacket(submitMessageWithContext, destinationFeeRecipient);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.expectRevert(abi.encodeWithSignature("MessageAlreadyProcessed()"));
        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            rawSubmitMessage
        );
    }

    function test_message_cannot_be_timeouted_before_deadline(bytes calldata message, uint64 newTimestamp) public {
        vm.assume(newTimestamp < type(uint64).max - 100);
        vm.assume(newTimestamp > 100);
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));


        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.warp(newTimestamp);

        bytes memory newRawSubmitMessage = bytes.concat(
            this.memorySlice(rawSubmitMessage, 0, CTX0_DEADLINE_START),
            bytes8(uint64(newTimestamp+1)),
            this.memorySlice(rawSubmitMessage, CTX0_DEADLINE_END)
        );

        vm.expectRevert(abi.encodeWithSignature("DeadlineNotPassed(uint64,uint64)", uint64(newTimestamp+1), uint64(newTimestamp)));
        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            newRawSubmitMessage
        );
    }

    function test_message_deadline_0_implies_any(bytes calldata message, uint64 newTimestamp) public {
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));


        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.warp(newTimestamp);

        bytes memory newRawSubmitMessage = bytes.concat(
            this.memorySlice(rawSubmitMessage, 0, CTX0_DEADLINE_START),
            bytes8(uint64(0)),
            this.memorySlice(rawSubmitMessage, CTX0_DEADLINE_END)
        );

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            newRawSubmitMessage
        );
    }
}