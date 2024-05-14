// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { Bytes65 } from "../../../src/utils/Bytes65.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import "../../../src/MessagePayload.sol";

contract HandleTimeoutTest is TestCommon, Bytes65 {

    function test_timeout_twice(bytes calldata message) public {
        (, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(101);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            rawSubmitMessage
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();


        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        messageWithContext = bytes.concat(
            abi.encode(escrow),
            messageWithContext
        );

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));

        vm.expectRevert(abi.encodeWithSignature("MessageAlreadyAcked()"));
        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));
    }

    function test_timeout_deliver_ack_timeout(bytes calldata message) public {
        (, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(101);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        // Timeout the package
        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            rawSubmitMessage
        );

        Vm.Log[] memory entriesTimeout = vm.getRecordedLogs();

        (, , bytes memory messageWithContextTimeout) = abi.decode(entriesTimeout[1].data, (bytes32, bytes, bytes));

        // Deliver the ack (which will also timeout)

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(submitMessageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.recordLogs();

        // deliver the ack
        escrow.processPacket(mockContext, submitMessageWithContext, bytes32(uint256(uint160(address(this)))));

        Vm.Log[] memory entriesDeliver = vm.getRecordedLogs();

        (, , bytes memory messageWithContextDeliver) = abi.decode(entriesDeliver[1].data, (bytes32, bytes, bytes));


        messageWithContextDeliver = bytes.concat(
            abi.encode(escrow),
            messageWithContextDeliver
        );

        (v, r, s) = signMessageForMock(messageWithContextDeliver);
        bytes memory mockContextDeliver = abi.encode(v, r, s);

        escrow.processPacket(mockContextDeliver, messageWithContextDeliver, bytes32(uint256(uint160(address(this)))));

        messageWithContextTimeout = bytes.concat(
            abi.encode(escrow),
            messageWithContextTimeout
        );

        (v, r, s) = signMessageForMock(messageWithContextTimeout);
        bytes memory mockContextTimeout = abi.encode(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("MessageAlreadyAcked()"));
        escrow.processPacket(mockContextTimeout, messageWithContextTimeout, bytes32(uint256(uint160(address(this)))));
    }

    function test_timeout_deliver_timeout_ack(bytes calldata message) public {
        (, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(101);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        // Timeout the package
        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            rawSubmitMessage
        );

        Vm.Log[] memory entriesTimeout = vm.getRecordedLogs();

        (, , bytes memory messageWithContextTimeout) = abi.decode(entriesTimeout[1].data, (bytes32, bytes, bytes));

        // Deliver the ack (which will also timeout)

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(submitMessageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.recordLogs();

        // deliver the ack
        escrow.processPacket(mockContext, submitMessageWithContext, bytes32(uint256(uint160(address(this)))));

        Vm.Log[] memory entriesDeliver = vm.getRecordedLogs();

        (, , bytes memory messageWithContextDeliver) = abi.decode(entriesDeliver[1].data, (bytes32, bytes, bytes));

        messageWithContextTimeout = bytes.concat(
            abi.encode(escrow),
            messageWithContextTimeout
        );

        (v, r, s) = signMessageForMock(messageWithContextTimeout);
        bytes memory mockContextTimeout = abi.encode(v, r, s);

        escrow.processPacket(mockContextTimeout, messageWithContextTimeout, bytes32(uint256(uint160(address(this)))));

        messageWithContextDeliver = bytes.concat(
            abi.encode(escrow),
            messageWithContextDeliver
        );

        (v, r, s) = signMessageForMock(messageWithContextDeliver);
        bytes memory mockContextDeliver = abi.encode(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("MessageAlreadyAcked()"));
        escrow.processPacket(mockContextDeliver, messageWithContextDeliver, bytes32(uint256(uint160(address(this)))));
    }

    receive() external payable {}
}