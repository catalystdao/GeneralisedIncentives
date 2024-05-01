// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract EscrowInformationTest is TestCommon {
    uint256 _overpay;

    function test_check_escrow_state() public {
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
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

    function test_check_escrow_events() public {
        IncentiveDescription storage incentive = _INCENTIVE;

        bytes32 destinationChainIdentifier = bytes32(uint256(0x123123) + uint256(2**255));

        vm.expectEmit();
        emit BountyPlaced(abi.encode(escrow), destinationChainIdentifier, bytes32(0x61adb1706803b672d6bc2979570942722fe2471f728cd5f8ebba7c642ca0d4b6), incentive);

        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            destinationChainIdentifier,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );
    }

    function test_gas_refund(uint256 overpay) public {
        vm.assume(overpay < 10000 ether);

        IncentiveDescription storage incentive = _INCENTIVE;
        _overpay = overpay;

        
        (uint256 gasRefund, ) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE) + overpay}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        assertEq(gasRefund, overpay);
    }

    // test_gas_refund will end up calling this function.
    receive() payable external {
        assertNotEq(msg.value, 0);
        assertEq(msg.value, _overpay);
    }
}
