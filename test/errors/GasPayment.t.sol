// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/implementations/mock/IncentivizedMockEscrow.sol";
import "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import "../../src/test/MockApplication.sol";

contract MockTest is Test {
    IIncentivizedMessageEscrow public escrow;
    MockApplication public application;

    address constant SIGNER = 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A;

    // PrivateKey 0x1111111111111111111111111111111111111111111111111111111111111111

    function setUp() public {
        escrow = new IncentivizedMockEscrow(SIGNER);
        application = new MockApplication(address(escrow));
    }

    function test_place_incentive() public {
        IIncentivizedMessageEscrow.incentiveDescription memory incentive = IIncentivizedMessageEscrow.incentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 + 1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
        application.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            abi.encode(keccak256(abi.encode(1))),
            incentive
        );
    }

    function test_place_incentive_total_sum_wrong() public {
        uint64 error = 10;
        IIncentivizedMessageEscrow.incentiveDescription memory incentive = IIncentivizedMessageEscrow.incentiveDescription({
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
        application.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            abi.encode(keccak256(abi.encode(1))),
            incentive
        );
    }

    function test_place_incentive_total_send_wrong() public {
        uint64 error = 10;
        IIncentivizedMessageEscrow.incentiveDescription memory incentive = IIncentivizedMessageEscrow.incentiveDescription({
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
        application.escrowMessage{value: incentive.totalIncentive - error}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            abi.encode(keccak256(abi.encode(1))),
            incentive
        );
    }
}
