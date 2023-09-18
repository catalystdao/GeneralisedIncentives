// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract MessageIdentifierTest is TestCommon {

    function test_unique_identifier_block_10() public {
        vm.roll(10);
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0x7d115fc12d69b0838b2ba4a0a17beac33c5aa489e50d17565642b46e724a1b1f));
    }

    function test_unique_identifier_block_11() public {
        vm.roll(11);
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0xeaa2656c806ede225c7826a7d7f26fbc0f3ba4c918a54ed06a04842f76fef24b));
    }

    // Even with the same message, the identifier should be different between blocks.
    function test_non_unique_bounty(bytes calldata message) public {
        IncentiveDescription storage incentive = _INCENTIVE;
        escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive
        );
        // No blocks pass between the 2 calls:
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadyBountied()")
        ); 
        escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive
        );
    }

    // With different destination identifiers they should produce different identifiers.
    function test_destination_identifier_impacts_message_identifier() public {
        IncentiveDescription storage incentive = _INCENTIVE;

        escrow.setRemoteEscrowImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(1)), abi.encode(address(escrow)));

        (, bytes32 messageIdentifier1) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(1)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        escrow.setRemoteEscrowImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(2)), abi.encode(address(escrow)));

        (, bytes32 messageIdentifier2) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(2)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier1, bytes32(0x7d9ecc6ce9343b45ddf5643fdc24b97e1dafea3c3859295759ad4b292ad08cf1));
        assertEq(messageIdentifier2, bytes32(0x373c6daaaee9fb27298c4ae298c8922b86a3cc41c9869d102aeb5ca37da7cf4a));
    }
}
