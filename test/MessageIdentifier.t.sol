// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";

contract MessageIdentifierTest is TestCommon {

    function test_unique_identifier_block_10() public {
        vm.roll(10);
        IncentiveDescription storage incentive = _incentive;
        (uint256 unused, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0x7d01c60c0b535b864f187d5ef6a43b38777eb9278bde07e01aac581417338a8e));
    }

    function test_unique_identifier_block_11() public {
        vm.roll(11);
        IncentiveDescription storage incentive = _incentive;
        (uint256 unused, bytes32 messageIdentifier) = escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            _message,
            incentive
        );

        assertEq(messageIdentifier, bytes32(0xb010c35a159afa479757019581efe2b2909c9552770ea6c5d3d4a484d9ca098d));
    }

    // Even with the same message, the identifier should be different between blocks.
    function test_non_unique_bounty(bytes calldata message) public {
        IncentiveDescription storage incentive = _incentive;
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            message,
            incentive
        );
        // No blocks pass between the 2 calls:
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadyBountied()")
        ); 
        escrow.escrowMessage{value: incentive.totalIncentive}(
            _destination_identifier,
            abi.encode(address(application)),
            message,
            incentive
        );
    }

    // With different destination identifiers they should produce different identifiers.
    function test_destination_identifier_impacts_message_identifier() public {
        IncentiveDescription storage incentive = _incentive;
        (uint256 unused1, bytes32 messageIdentifier1) = escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(_destination_identifier) + uint256(1)),
            abi.encode(address(application)),
            _message,
            incentive
        );

        (uint256 unused2, bytes32 messageIdentifier2) = escrow.escrowMessage{value: incentive.totalIncentive}(
            bytes32(uint256(_destination_identifier) + uint256(2)),
            abi.encode(address(application)),
            _message,
            incentive
        );

        assertEq(messageIdentifier1, bytes32(0xb611f5ca36bd36b47bab8c365fb5f0fdd9eb31b4c7b9eed405203b767b0538d7));
        assertEq(messageIdentifier2, bytes32(0x6a39bdb9cac78cd0c194b55ea88fac150b7db57dcd5b39d89964381816a2fbbd));
    }
}
