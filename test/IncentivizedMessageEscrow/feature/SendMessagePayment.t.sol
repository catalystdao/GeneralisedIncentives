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

contract SendMessagePaymentTest is TestCommon {

    uint128 constant SEND_MESSAGE_PAYMENT_COST = 10_000;

    uint256 _receive;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function setUp() override public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        _REFUND_GAS_TO = makeAddr("Alice");
        BOB = makeAddr("Bob");
        escrow = new IncentivizedMockEscrow(_DESTINATION_IDENTIFIER, SIGNER, SEND_MESSAGE_PAYMENT_COST);

        application = ICrossChainReceiver(address(new MockApplication(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(this));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

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

    function test_estimate_cost() external {
        (address asset, uint256 cost) = escrow.estimateAdditionalCost();

        assertEq(asset, address(0));
        assertEq(cost, SEND_MESSAGE_PAYMENT_COST);
    }

    function test_send_message_with_additional_cost() external {
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        // Check that the message identifier points exposes the bounty.
        IncentiveDescription memory storedIncentiveAtEscrow = escrow.bounty(messageIdentifier);

        assertEq(incentive.maxGasDelivery, storedIncentiveAtEscrow.maxGasDelivery);
        assertEq(incentive.maxGasAck, storedIncentiveAtEscrow.maxGasAck);
        assertEq(incentive.refundGasTo, storedIncentiveAtEscrow.refundGasTo);
        assertEq(incentive.priceOfDeliveryGas, storedIncentiveAtEscrow.priceOfDeliveryGas);
        assertEq(incentive.priceOfAckGas, storedIncentiveAtEscrow.priceOfAckGas);
        assertEq(incentive.targetDelta, storedIncentiveAtEscrow.targetDelta);
    }

    function test_error_send_message_without_additional_cost() external {
        IncentiveDescription storage incentive = _INCENTIVE;
        vm.expectRevert(
            abi.encodeWithSignature(
                "NotEnoughGasProvided(uint128,uint128)",
                529440925003,
                529440925002
            )
        );
        (, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE) + SEND_MESSAGE_PAYMENT_COST - 1}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        // Check that the message identifier points exposes the bounty.
        IncentiveDescription memory storedIncentiveAtEscrow = escrow.bounty(messageIdentifier);

        assertNotEq(incentive.maxGasDelivery, storedIncentiveAtEscrow.maxGasDelivery);
        assertNotEq(incentive.maxGasAck, storedIncentiveAtEscrow.maxGasAck);
        assertNotEq(incentive.refundGasTo, storedIncentiveAtEscrow.refundGasTo);
        assertNotEq(incentive.priceOfDeliveryGas, storedIncentiveAtEscrow.priceOfDeliveryGas);
        assertNotEq(incentive.priceOfAckGas, storedIncentiveAtEscrow.priceOfAckGas);
        assertNotEq(incentive.targetDelta, storedIncentiveAtEscrow.targetDelta);
    }

    function test_process_message_with_additional_payment(bytes calldata message) external {
        (, bytes memory messageWithContext) = setupEscrowMessage(address(application), message);
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));

        escrow.processMessage{value: SEND_MESSAGE_PAYMENT_COST}(
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }

    function test_process_message_without_additional_payment(bytes calldata message) external {
        (, bytes memory messageWithContext) = setupEscrowMessage(address(application), message);
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));

        vm.expectRevert(
            abi.encodeWithSignature(
                "NotEnoughGasProvidedForVerification()"
            )
        );
        escrow.processMessage{value: SEND_MESSAGE_PAYMENT_COST - 1}(
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }
}