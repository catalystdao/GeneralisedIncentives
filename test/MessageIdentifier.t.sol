// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";

contract MessageIdentifierTest is TestCommon {

    function test_unique_identifier_block_10() public {
        vm.roll(10);
        IncentiveDescription storage incentive = _INCENTIVE;
        (uint256 unused, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0xf05e0ca00911f1e899dcc2a2b34ae6a81e6d807d649fac3bf301d22adaab370b));
    }

    function test_unique_identifier_block_11() public {
        vm.roll(11);
        IncentiveDescription storage incentive = _INCENTIVE;
        (uint256 unused, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0xad796d50abed2b9f91b027ed86c52256476dd66ad7d1c0a789a2285cf2ad71f6));
    }

    // Even with the same message, the identifier should be different between blocks.
    function test_non_unique_bounty(bytes calldata message) public {
        IncentiveDescription storage incentive = _INCENTIVE;
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive
        );
        // No blocks pass between the 2 calls:
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadyBountied()")
        ); 
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_THIS,
            message,
            incentive
        );
    }

    // With different destination identifiers they should produce different identifiers.
    function test_DESTINATION_IDENTIFIER_impacts_MESSAGE_identifier() public {
        IncentiveDescription storage incentive = _INCENTIVE;
        (uint256 unused1, bytes32 messageIdentifier1) = escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(1)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        (uint256 unused2, bytes32 messageIdentifier2) = escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(_DESTINATION_IDENTIFIER) + uint256(2)),
            _DESTINATION_ADDRESS_THIS,
            _MESSAGE,
            incentive
        );

        assertEq(messageIdentifier1, bytes32(0x8ba40a82a80752b4a381baec116964861862eb6c926b16da869061adaddc428f));
        assertEq(messageIdentifier2, bytes32(0xf525c217f2302cb99972860c1bf75861e194eed2f050aae6cfb4178dcc276949));
    }
}
