// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import "../../../src/apps/mock/IncentivizedMockEscrow.sol";
import "../../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowEvents } from "../../../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../../../src/interfaces/IMessageEscrowStructs.sol";
import "./../../mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";

contract sendPacketPaymentTest is TestCommon {

    uint128 constant SEND_MESSAGE_PAYMENT_COST = 10_000;

    uint256 _receive;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipient,
        bytes message
    );

    function setUp() override public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        _REFUND_GAS_TO = makeAddr("Alice");
        BOB = makeAddr("Bob");
        escrow = new IncentivizedMockEscrow(sendLostGasTo, _DESTINATION_IDENTIFIER, SIGNER, SEND_MESSAGE_PAYMENT_COST, 0);

        application = ICrossChainReceiver(address(new MockApplication(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(this));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        _MESSAGE = abi.encode(keccak256(abi.encode(1)));
        _DESTINATION_ADDRESS_THIS = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(this))))
        );
        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(application))))
        );

        _INCENTIVE = IncentiveDescription({
            maxGasDelivery: 1199199,
            maxGasAck: 1188188,
            refundGasTo: _REFUND_GAS_TO,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
    }

    function test_process_message_with_cost() external {
        IncentiveDescription storage incentive = _INCENTIVE;

        vm.recordLogs();
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        
        (bytes memory _metadata, bytes memory newMessage) = getVerifiedMessage(address(escrow), messageWithContext);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotEnoughGasProvided(uint128,uint128)",
                uint128(0),
                uint128(SEND_MESSAGE_PAYMENT_COST)
            )
        );
        escrow.processPacket(
            _metadata,
            newMessage,
            bytes32(abi.encodePacked(address(this)))
        );

        // This doesn't fail
        escrow.processPacket{value: SEND_MESSAGE_PAYMENT_COST}(
            _metadata,
            newMessage,
            bytes32(abi.encodePacked(address(this)))
        );
    }

    function test_process_message_refund_with_cost(uint32 excess) external {
        IncentiveDescription storage incentive = _INCENTIVE;

        vm.recordLogs();
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        
        (bytes memory _metadata, bytes memory newMessage) = getVerifiedMessage(address(escrow), messageWithContext);

        // This doesn't fail
        escrow.processPacket{value: SEND_MESSAGE_PAYMENT_COST + excess}(
            _metadata,
            newMessage,
            bytes32(abi.encodePacked(address(this)))
        );

        assertEq(_receive, excess, "Didn't receive excess.");
    }

    function test_process_message_reemit_with_cost(uint64 excess) external {
        IncentiveDescription storage incentive = _INCENTIVE;

        vm.recordLogs();
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        
        (bytes memory _metadata, bytes memory newMessage) = getVerifiedMessage(address(escrow), messageWithContext);

        vm.recordLogs();

        escrow.processPacket{value: SEND_MESSAGE_PAYMENT_COST}(
            _metadata,
            newMessage,
            bytes32(abi.encodePacked(address(this)))
        );

        entries = vm.getRecordedLogs();

        (, , bytes memory ackMessageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        bytes memory ackMessage = this.sliceMemory(ackMessageWithContext, 64);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotEnoughGasProvided(uint128,uint128)",
                uint128(0),
                uint128(SEND_MESSAGE_PAYMENT_COST)
            )
        );
        escrow.reemitAckMessage(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)), ackMessage);

        escrow.reemitAckMessage{value:SEND_MESSAGE_PAYMENT_COST + excess}(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)), this.sliceMemory(ackMessageWithContext, 64));

        assertEq(_receive, excess, "Didn't receive excess.");
    }

    function test_process_message_timeout_with_cost(uint64 excess) external {
        uint256 currentTime = 1000000;
        vm.warp(1000000);
        IncentiveDescription storage incentive = _INCENTIVE;

        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        bytes memory FROM_APPLICATION_START = new bytes(65);

        bytes memory mockMessage = abi.encodePacked(
            bytes1(0),
            bytes32(0),
            FROM_APPLICATION_START,
            FROM_APPLICATION_START,
            uint64(currentTime),
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotEnoughGasProvided(uint128,uint128)",
                uint128(0),
                uint128(SEND_MESSAGE_PAYMENT_COST)
            )
        );
        escrow.timeoutMessage(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)), 100, mockMessage);

        escrow.timeoutMessage{value:SEND_MESSAGE_PAYMENT_COST + excess}(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)), 100, mockMessage);

        assertEq(_receive, excess, "Didn't receive excess.");
    }

    function sliceMemory(bytes calldata b, uint256 startSlice) external returns(bytes memory) {
        return b[startSlice: ];
    }

    receive() external payable {
        _receive = msg.value;
    }
}