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

        assertEq(messageIdentifier, bytes32(0x63d67e3fce2ed64674223d39595772649b279109e9bffd287446258b536459ac));
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

        assertEq(messageIdentifier, bytes32(0xff33b82153b4b666a3b395852e06879d8be2aab78d77e93307ba3879e1cf7042));
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

        assertEq(messageIdentifier1, bytes32(0x0336e79dacdcf5c72d112c6a1dcc16484993043f84feb08300a9c78ee317ff09));
        assertEq(messageIdentifier2, bytes32(0x27a6da8297249099dc55dcdcd0de9b3114fdded9901a151414e2a1eea034f9db));
    }
}
