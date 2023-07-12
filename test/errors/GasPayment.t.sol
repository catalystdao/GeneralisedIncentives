// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../TestCommon.sol";

contract GasPaymentTest is TestCommon {

    function test_place_incentive() public {
        IncentiveDescription memory incentive = IncentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 + 1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );
    }

    function test_place_zero_incentive() public {
        IncentiveDescription memory incentive = IncentiveDescription({
            minGasDelivery: 0,
            minGasAck: 0,
            totalIncentive: 0,
            priceOfDeliveryGas: 0,
            priceOfAckGas: 0,
            targetDelta: 30 minutes
        });
        vm.expectRevert(
            abi.encodeWithSignature("ZeroIncentiveNotAllowed()")
        ); 
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );
    }

    function test_place_incentive_total_sum_wrong() public {
        uint64 error = 10;
        IncentiveDescription memory incentive = IncentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 +  1188188 * 321123 - error,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        vm.expectRevert(
            abi.encodeWithSignature("NotEnoughGasProvided(uint128,uint128)", incentive.totalIncentive + error, incentive.totalIncentive)
        ); 
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );
    }

    function test_place_incentive_total_send_wrong() public {
        uint64 error = 10;
        IncentiveDescription memory incentive = IncentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 +  1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        vm.expectRevert(
            abi.encodeWithSignature("NotEnoughGasProvided(uint128,uint128)", incentive.totalIncentive, incentive.totalIncentive - error)
        ); 
        escrow.escrowMessage{value: incentive.totalIncentive - error}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );
    }
}
