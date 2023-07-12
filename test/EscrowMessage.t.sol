// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";

contract EscrowInformationTest is TestCommon {
    uint256 _overpay;

    function test_check_escrow_state() public {
        IncentiveDescription storage incentive = _incentive;
        (uint256 gasRefund, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            _message,
            incentive
        );

        // Check that the message identifier points exposes the bounty.
        IncentiveDescription memory storedIncentiveAtEscrow = escrow.bounty(messageIdentifier);

        assertEq(incentive.minGasDelivery, storedIncentiveAtEscrow.minGasDelivery);
        assertEq(incentive.minGasAck, storedIncentiveAtEscrow.minGasAck);
        assertEq(incentive.totalIncentive, storedIncentiveAtEscrow.totalIncentive);
        assertEq(incentive.priceOfDeliveryGas, storedIncentiveAtEscrow.priceOfDeliveryGas);
        assertEq(incentive.priceOfAckGas, storedIncentiveAtEscrow.priceOfAckGas);
        assertEq(incentive.targetDelta, storedIncentiveAtEscrow.targetDelta);
    }

    function test_check_escrow_events() public {
        IncentiveDescription storage incentive = _incentive;

        vm.expectEmit(true, false, false, true);
        emit BountyPlaced(bytes32(0x9b1bd1506f72482e1e9bbaae440dbf443f2e2b83a8877c90290e2406f066b4c9), incentive);

        escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            _message,
            incentive
        );
    }

    function test_gas_refund(uint256 overpay) public {
        vm.assume(overpay < 10000 ether);
        
        IncentiveDescription storage incentive = _incentive;
        _overpay = overpay;

        
        (uint256 gasRefund, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive + overpay}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            _message,
            incentive
        );

        assertEq(gasRefund, overpay);
    }

    // test_gas_refund will end up calling this function.
    receive() payable external {
        assertNotEq(msg.value, 0);
        assertEq(msg.value, _overpay);
    }
}
