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

        assertEq(messageIdentifier, bytes32(0xb052184a54ac360ad9357b08ecca6fb0db95533777c220ddb24a2c9447636a36));
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

        assertEq(messageIdentifier, bytes32(0x8c4b4f4125bc7c9c0943754a03bdea1a58c680a4069139deed023e4964e762a0));
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

        assertEq(messageIdentifier1, bytes32(0xdc4a66de9adecec9a06bc8afaffeb73714efb0ad20624b4347fa815035425616));
        assertEq(messageIdentifier2, bytes32(0x95135d09fbf48438c5b9e293dcb9a3f876eaf5f33cbe764ec253cf1770505a85));
    }

    // With different destination identifiers they should produce different identifiers.
    function test_sender_impacts_message_identifier(address a, address b) public {
        vm.assume(a != b);
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
