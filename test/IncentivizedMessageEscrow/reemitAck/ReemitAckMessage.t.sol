// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract ReemitAckMessageTest is TestCommon {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipient,
        bytes message
    );

    function test_reemit_ack(bytes calldata message) public {
        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));

        (, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipient);

        // remove the context that setupForAck adds.
        bytes memory rawMessage = this.memorySlice(messageWithContext, 96);

        vm.expectEmit();
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encode(address(escrow)),
            this.memorySlice(messageWithContext, 32)
        );

        escrow.reemitAckMessage(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)), rawMessage);
    }

    // This tests a relayer trying to reemit a message which is slightly changed.
    function test_reemit_ack_wrong_message(bytes calldata message) public {
        bytes32 destinationFeeRecipient = bytes32(uint256(uint160(address(this))));

        (, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipient);

        // Simulate a relayer changing the ack from the application. We add a byte
        // but it could also be removing, flipping or similar.
        bytes memory newMessage = bytes.concat(
            messageWithContext,
            bytes1(0x01)
        );

        vm.expectRevert(abi.encodeWithSignature("CannotRetryWrongMessage(bytes32,bytes32)", bytes32(0), keccak256(newMessage)));
        escrow.reemitAckMessage(_DESTINATION_IDENTIFIER, abi.encodePacked(address(escrow)), newMessage);
    }
}