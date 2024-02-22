// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

import { IncentivizedMockEscrow } from "../../../src/apps/mock/IncentivizedMockEscrow.sol";
import { MockApplication } from "../../mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract SubmitPackageDeadlineTest is TestCommon {

    function _newEscrow(uint64 deadline) internal {
        escrow = new IncentivizedMockEscrow(sendLostGasTo, _DESTINATION_IDENTIFIER, SIGNER, 0, deadline);

        application = ICrossChainReceiver(address(new MockApplication(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(this));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));
    }


    function test_max_proof_period(uint64 proofPeriod) public {
        vm.assume(proofPeriod != 0);
        vm.assume(proofPeriod > block.timestamp);
        vm.assume(type(uint64).max - 5 > proofPeriod);
        _newEscrow(proofPeriod);

        // Try to submit a proof that is too far into the future.
        vm.expectRevert(abi.encodeWithSignature("DeadlineTooLong(uint64,uint64)", uint64(block.timestamp + proofPeriod), uint64(block.timestamp + proofPeriod + 1)));
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            uint64(block.timestamp + proofPeriod + 1)
        );

        // We just need to set it correctly.
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            uint64(block.timestamp + proofPeriod)
        );
    }

    function test_zero_implies_any_proofPeriod(uint64 testDeadline) public {
        vm.assume(testDeadline > block.timestamp);
        _newEscrow(0);

        // We can set it to anything that is not in the past.
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            testDeadline
        );
    }

    function test_zero_implies_any_deadline(uint64 testDeadline) public {
        _newEscrow(0);

        vm.warp(testDeadline);

        // We can set it to anything that is not in the past.
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            0
        );
    }

    function test_call_deadline_in_past(uint64 testDeadline) public {
        vm.assume(type(uint64).max - 100 > testDeadline);
        vm.assume(testDeadline > block.timestamp);
        _newEscrow(0);

        vm.warp(testDeadline);

        vm.expectRevert(abi.encodeWithSignature("DeadlineInPast(uint64,uint64)", uint64(block.timestamp), testDeadline));
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            testDeadline
        );

        uint256 snapshot = vm.snapshot();

        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            testDeadline + 1
        );

        vm.revertTo(snapshot);

        vm.warp(testDeadline-1);
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            _MESSAGE,
            _INCENTIVE,
            testDeadline
        );


    }
}