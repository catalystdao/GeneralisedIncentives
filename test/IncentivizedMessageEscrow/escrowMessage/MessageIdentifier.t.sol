// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";

contract MessageIdentifierTest is TestCommon {

    function test_unique_identifier_block_10() public {
        vm.roll(10);
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        assertEq(messageIdentifier, bytes32(0xaa02b82738a85f91a4e3a5b6a6298a176a0d235e631bbad51b406591f0159796));
    }

    function test_unique_identifier_block_11() public {
        vm.roll(11);
        IncentiveDescription storage incentive = _INCENTIVE;
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        assertEq(messageIdentifier, bytes32(0x6fa210ac6eb9452215853391fbea47494907f6de90635d3c70f5ab97b9e873d5));
    }

    // Even with the same message, the identifier should be different between blocks.
    function test_non_unique_bounty(bytes calldata message) public {
        IncentiveDescription storage incentive = _INCENTIVE;
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive,
            0
        );
        // No blocks pass between the 2 calls:
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadyBountied()")
        ); 
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive,
            0
        );
    }

    // With different destination identifiers they should produce different identifiers.
    function test_destination_identifier_impacts_message_identifier() public {
        IncentiveDescription storage incentive = _INCENTIVE;

        escrow.setRemoteImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(1)), abi.encode(address(escrow)));

        (, bytes32 messageIdentifier1) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(1)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        escrow.setRemoteImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(2)), abi.encode(address(escrow)));

        (, bytes32 messageIdentifier2) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(2)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        assertEq(messageIdentifier1, bytes32(0xa175faea5cf764546faa147a161c4632a6326383d7dc842c16c79aa4d51970c2));
        assertEq(messageIdentifier2, bytes32(0xc81f8569a4c9c2944957b6313a5992cba9befad01d065f8e2a904cd4d3121aa2));
    }

    // With different destination identifiers they should produce different identifiers.
    function test_sender_impacts_message_identifier(address a, address b) public {
        vm.assume(a != b);
        vm.assume(a != address(application));
        vm.assume(b != address(application));
        IncentiveDescription storage incentive = _INCENTIVE;

        vm.deal(a, _getTotalIncentive(_INCENTIVE));
        vm.deal(b, _getTotalIncentive(_INCENTIVE));

        vm.prank(a);
        escrow.setRemoteImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER)), abi.encode(address(escrow)));

        vm.prank(a);
        (, bytes32 messageIdentifier1) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        vm.prank(b);
        escrow.setRemoteImplementation(bytes32(uint256(_DESTINATION_IDENTIFIER)), abi.encode(address(escrow)));

        vm.prank(b);
        (, bytes32 messageIdentifier2) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            bytes32(uint256(_DESTINATION_IDENTIFIER)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive,
            0
        );

        assertNotEq(messageIdentifier1, messageIdentifier2);
    }
}
