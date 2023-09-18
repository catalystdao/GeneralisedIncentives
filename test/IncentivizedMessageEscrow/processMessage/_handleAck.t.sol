// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";


contract ProcessMessageAckTest is TestCommon {

    uint256 _receive;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function test_ack_process_message() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        (, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        _receive = GAS_RECEIVE_CONSTANT;

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(_REFUND_GAS_TO.balance, _getTotalIncentive(_INCENTIVE) - _receive, "Refund");
    }

    function test_ack_called_event() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        _receive = GAS_RECEIVE_CONSTANT;
        bytes memory _acknowledgement = hex"d9b60178cfb2eb98b9ff9136532b6bd80eeae6a2c90a2f96470294981fcfb62b";

        vm.expectEmit();
        emit MessageAcked(messageIdentifier);
        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(GAS_SPENT_ON_DESTINATION),
            uint64(GAS_SPENT_ON_SOURCE),
            uint128(_receive),
            0  // Same destination as source relayer.
        );

        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.ackMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    _acknowledgement
                )
            )
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        // Check that the bounty has been deleted.
        IncentiveDescription memory incentive = escrow.bounty(messageIdentifier);
        assertEq(incentive.refundGasTo, address(0));
    }

    function test_ack_different_recipitents() public {
        vm.warp(1);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        vm.warp(_INCENTIVE.targetDelta + 1);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectEmit();
        emit MessageAcked(messageIdentifier);

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;

        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(gas_on_destination),
            uint64(gas_on_source),
            uint128(BOB_incentive),
            uint128(_receive)
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(BOB.balance, BOB_incentive, "BOB incentive");
    }

    function test_ack_less_time_than_expected(uint64 timePassed, uint64 targetDelta) public {
        vm.assume(timePassed < targetDelta);
        _INCENTIVE.targetDelta = targetDelta;
        vm.warp(1);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        vm.warp(timePassed + 1);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;
        // uint256 totalIncentive = BOB_incentive + _receive;
        // less time has passed, so more incentives are given to destination relayer.
        BOB_incentive += (_receive * (targetDelta - timePassed))/targetDelta;
        _receive -= (_receive * (targetDelta - timePassed))/targetDelta;

        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(gas_on_destination),
            uint64(gas_on_source),
            uint128(BOB_incentive),
            uint128(_receive)
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(BOB.balance, BOB_incentive, "BOB incentive");

        // Check that the bounty has been deleted.
        IncentiveDescription memory incentive = escrow.bounty(messageIdentifier);
        assertEq(incentive.refundGasTo, address(0));
    }

    function test_ack_more_time_than_expected(uint64 timePassed, uint64 targetDelta) public {
        vm.assume(targetDelta < type(uint64).max/2);
        vm.assume(timePassed > targetDelta);
        vm.assume(timePassed - targetDelta < targetDelta);
        _INCENTIVE.targetDelta = targetDelta;
        vm.warp(1);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        vm.warp(timePassed + 1);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;
        // uint256 totalIncentive = BOB_incentive + _receive;
        // less time has passed, so more incentives are given to destination relayer.
        _receive += (BOB_incentive * uint256(timePassed - targetDelta))/uint256(targetDelta);
        BOB_incentive -= (BOB_incentive * uint256(timePassed - targetDelta))/uint256(targetDelta);

        vm.expectEmit();
        emit BountyClaimed(
            messageIdentifier,
            uint64(gas_on_destination),
            uint64(gas_on_source),
            uint128(BOB_incentive),
            uint128(_receive)
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(BOB.balance, BOB_incentive, "BOB incentive");

        // Check that the bounty has been deleted.
        IncentiveDescription memory incentive = escrow.bounty(messageIdentifier);
        assertEq(incentive.refundGasTo, address(0));
    }

    // relayer incentives will be sent here
    receive() payable external {
        assertEq(msg.value, _receive, "Relayer Payment");
    }
}