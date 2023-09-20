// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";


contract TargetDeltaZeroTest is TestCommon {
    event Debug();

    uint256 _receive;

    function setUp() override public {
        super.setUp();
        
        _INCENTIVE.targetDelta = 0;
    }

    function test_target_delta_zero(uint16 timePassed) public {
        vm.warp(1000);
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(BOB)));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(application), message, destinationFeeRecipitent);

        vm.warp(uint256(1000) + uint256(timePassed));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        // Check that the bounty has not been deleted.
        assertNotEq(escrow.bounty(messageIdentifier).refundGasTo, address(0));

        uint256 gas_on_destination = GAS_SPENT_ON_DESTINATION;
        uint256 gas_on_source = GAS_SPENT_ON_SOURCE;
        uint256 BOB_incentive = gas_on_destination * _INCENTIVE.priceOfDeliveryGas;
        _receive = gas_on_source * _INCENTIVE.priceOfAckGas;

        vm.expectEmit();
        emit MessageAcked(messageIdentifier);

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
        assertEq(escrow.bounty(messageIdentifier).refundGasTo, address(0));
    }

    // relayer incentives will be sent here
    receive() payable external {
        assertEq(msg.value, _receive, "Relayer Payment");
    }
}