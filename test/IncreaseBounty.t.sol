// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";

contract EscrowInformationTest is TestCommon {
    function escrowMessage(bytes memory message) internal returns(bytes32) {
        (uint256 gasRefund, bytes32 messageIdentifier) = application.escrowMessage{value: _INCENTIVE.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        return messageIdentifier;
    }

    function test_fail_bounty_does_not_exist() public {
        // Do not escrow the message
        // bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        vm.expectRevert(
            abi.encodeWithSignature("MessageDoesNotExist()")
        ); 
        escrow.increaseBounty{value: 100000}(
            keccak256(abi.encodePacked(uint256(123))),
            _INCENTIVE.priceOfDeliveryGas + 123123,
            _INCENTIVE.priceOfAckGas + 321321
        );
    }

    function test_fail_delivery_gas_must_increase() public {
        // Do not escrow the message
        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        vm.expectRevert(
            abi.encodeWithSignature("DeliveryGasPriceMustBeIncreased()")
        ); 
        escrow.increaseBounty{value: 100000}(
            messageIdentifier,
            _INCENTIVE.priceOfDeliveryGas - 1,
            _INCENTIVE.priceOfAckGas
        );
    }

    function test_fail_ack_gas_must_increase() public {
        // Do not escrow the message
        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        vm.expectRevert(
            abi.encodeWithSignature("AckGasPriceMustBeIncreased()")
        ); 
        escrow.increaseBounty{value: 0}(
            messageIdentifier,
            _INCENTIVE.priceOfDeliveryGas,
            _INCENTIVE.priceOfAckGas - 1
        );
    }

    function test_no_increase_escrow() public {
        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        escrow.increaseBounty{value: 0}(
            messageIdentifier,
            _INCENTIVE.priceOfDeliveryGas,
            _INCENTIVE.priceOfAckGas
        );
    }

    function test_fail_overpay() public {
        uint128 overPay = 1;

        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        vm.expectRevert(
            abi.encodeWithSignature("NotEnoughGasProvided(uint128,uint128)", 0, overPay)
        );
        escrow.increaseBounty{value: overPay}(
            messageIdentifier,
            _INCENTIVE.priceOfDeliveryGas,
            _INCENTIVE.priceOfAckGas
        );
    }

    function test_fail_under_and_overpay(int256 diffPay) public {
        vm.assume(diffPay != 0);
        vm.assume(diffPay < 1000 ether);
        uint64 increaseAck = 123123;
        uint64 increaseDelivery = 321321;

        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        uint128 deliveryGas = _INCENTIVE.minGasDelivery * increaseDelivery;
        uint128 ackGas = _INCENTIVE.minGasAck * increaseAck;
        uint128 difference = deliveryGas + ackGas;
        vm.assume(0 < int256(uint256(difference)) + diffPay);

        uint128 newPay = uint128(uint256(int256(uint256(difference)) + diffPay));

        vm.expectRevert(
            abi.encodeWithSignature("NotEnoughGasProvided(uint128,uint128)", difference, newPay)
            
        );
        escrow.increaseBounty{value: newPay}(
            messageIdentifier,
            increaseDelivery + _INCENTIVE.priceOfDeliveryGas,
            increaseAck + _INCENTIVE.priceOfAckGas
        );
    }

    function test_increase_escrow() public {
        uint64 increaseAck = 123123;
        uint64 increaseDelivery = 321321;

        bytes32 messageIdentifier = escrowMessage(_MESSAGE);

        uint128 deliveryGas = _INCENTIVE.minGasDelivery * increaseDelivery;
        uint128 ackGas = _INCENTIVE.minGasAck * increaseAck;
        uint128 difference = deliveryGas + ackGas;

        escrow.increaseBounty{value: difference}(
            messageIdentifier,
            increaseDelivery + _INCENTIVE.priceOfDeliveryGas,
            increaseAck + _INCENTIVE.priceOfAckGas
        );
    }
}
