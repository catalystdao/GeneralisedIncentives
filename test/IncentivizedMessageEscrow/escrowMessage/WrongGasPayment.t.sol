// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract EscrowWrongGasPaymentTest is TestCommon {

    function test_place_incentive() public {
        IncentiveDescription memory incentive = IncentiveDescription({
            maxGasDelivery: 1199199,
            maxGasAck: 1188188,
            refundGasTo: address(this),
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        escrow.escrowMessage{value: _getTotalIncentive(incentive)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );
    }

    // Not used.
    // function test_fail_zero_incentive() public {
    //     IncentiveDescription memory incentive = IncentiveDescription({
    //         maxGasDelivery: 0,
    //         maxGasAck: 0,
    //         refundGasTo: address(this),
    //         priceOfDeliveryGas: 0,
    //         priceOfAckGas: 0,
    //         targetDelta: 30 minutes
    //     });
    //     vm.expectRevert(
    //         abi.encodeWithSignature("ZeroIncentiveNotAllowed()")
    //     ); 
    //     escrow.escrowMessage{value: _getTotalIncentive(incentive)}(
    //         _DESTINATION_IDENTIFIER,
    //         _DESTINATION_ADDRESS_THIS,
    //         _MESSAGE,
    //         incentive
    //     );
    // }

    function test_fail_not_enough_gas_sent() public {
        uint64 error = 10;
        IncentiveDescription memory incentive = IncentiveDescription({
            maxGasDelivery: 1199199,
            maxGasAck: 1188188,
            refundGasTo: address(this),
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        vm.expectRevert(
            abi.encodeWithSignature("NotEnoughGasProvided(uint128,uint128)", _getTotalIncentive(incentive), _getTotalIncentive(incentive) - error)
        ); 
        escrow.escrowMessage{value: _getTotalIncentive(incentive) - error}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );
    }
}
