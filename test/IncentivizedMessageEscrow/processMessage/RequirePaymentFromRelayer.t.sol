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
    }
}