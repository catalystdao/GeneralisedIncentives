// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/implementations/mock/IncentivizedMockEscrow.sol";
import "../src/interfaces/IIncentivizedMessageEscrow.sol";
import "../src/test/MockApplication.sol";

contract MockTest is Test {
    IIncentivizedMessageEscrow public escrow;
    MockApplication public application;

    address constant SIGNER = 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A;

    // PrivateKey 0x1111111111111111111111111111111111111111111111111111111111111111

    function setUp() public {
        escrow = new IncentivizedMockEscrow(SIGNER);
        application = new MockApplication(address(escrow));
    }

    function test_check_escrow_state() public {
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

        // TODO: check that the state is good
    }

    function test_check_escrow_events() public {
        IIncentivizedMessageEscrow.incentiveDescription memory incentive = IIncentivizedMessageEscrow.incentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 + 1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });

        vm.recordLogs();
        application.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(0x123123) + uint256(2**255)),
            abi.encode(address(application)),
            abi.encode(keccak256(abi.encode(1))),
            incentive
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // TODO: check that all of the events are there.
    }
}
