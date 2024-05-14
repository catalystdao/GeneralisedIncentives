// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract EscrowInformationTest is TestCommon {
    function test_error_refund_gas_to_0() public {
        IncentiveDescription storage incentive = _INCENTIVE;
        incentive.refundGasTo = address(0);
        vm.expectRevert();
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );
    }

}
