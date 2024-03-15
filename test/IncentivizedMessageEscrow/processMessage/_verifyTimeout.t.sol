// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { Bytes65 } from "../../../src/utils/Bytes65.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import "../../../src/MessagePayload.sol";

contract VerifyTimeoutTest is TestCommon, Bytes65 {

    function test_timeout_invalid_implementation_address(bytes calldata message) public {
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

        // Set the escrow to another address. This will trigger the test. 
        // This will simulate another address emtting this message.
        address evilEscrow = makeAddr("evilEscrow");
        messageWithContext = bytes.concat(
            abi.encode(evilEscrow),
            messageWithContext
        );

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("InvalidImplementationAddress()"));
        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));
    }

    function test_timeout_invalid_package_blocknumber() public {
        bytes memory message = _MESSAGE;
        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(101);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number + 1,
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

        vm.expectRevert(abi.encodeWithSignature("InvalidTimeoutPackage(bytes32,bytes32)", messageIdentifier, bytes32(0x7280fbbf4b961ae2be60ac602f2b79cadc7d2270f2d4fe335b40763289bc68d3)));
        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));
    }

    function test_timeout_invalid_package_payload() public {
        bytes memory message = _MESSAGE;
        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(101);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            bytes.concat(
                rawSubmitMessage,
                hex"01"
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();


        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        messageWithContext = bytes.concat(
            abi.encode(escrow),
            messageWithContext
        );

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("InvalidTimeoutPackage(bytes32,bytes32)", messageIdentifier, bytes32(0xf1fce73f881b84131b8681088de648b38e71841d0a3b34a37f9558b561f2075a)));
        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));
    }

    function test_timeout_invalid_package_deadline() public {
        bytes memory message = _MESSAGE;
        (bytes32 messageIdentifier, bytes memory submitMessageWithContext) = setupsubmitMessage(address(application), message, 100);

        vm.warp(99);

        // Remove the context
        bytes memory rawSubmitMessage = this.memorySlice(submitMessageWithContext, 96);

        vm.recordLogs();

        escrow.timeoutMessage(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(address(escrow)),
            block.number,
            bytes.concat(
                this.memorySlice(rawSubmitMessage, 0, CTX0_DEADLINE_START),
                bytes8(uint64(98)),
                this.memorySlice(rawSubmitMessage, CTX0_DEADLINE_END)
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();


        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        messageWithContext = bytes.concat(
            abi.encode(escrow),
            messageWithContext
        );

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("InvalidTimeoutPackage(bytes32,bytes32)", messageIdentifier, bytes32(0x04aa4b2e2cba9007a1992ace08f58e5d15aee89dde337d565dcd6e6699e3a493)));
        escrow.processPacket(mockContext, messageWithContext, bytes32(uint256(uint160(address(this)))));
    }

    receive() external payable {}
}