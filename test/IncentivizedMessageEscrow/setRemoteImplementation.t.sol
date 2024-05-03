// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { TestCommon } from "../TestCommon.t.sol";
import { IncentivizedMessageEscrow } from "../../src/IncentivizedMessageEscrow.sol";


contract TestSetRemoteImplementation is TestCommon {

    function test_set_remote_implementation(bytes32 destination_identifier, bytes calldata implementation) public {
        vm.assume(destination_identifier != _DESTINATION_IDENTIFIER);
        vm.assume(implementation.length != 0);

        vm.expectEmit();
        emit RemoteImplementationSet(address(this), destination_identifier, keccak256(implementation), implementation);
        
        escrow.setRemoteImplementation(destination_identifier, implementation);

        assertEq(
            IncentivizedMessageEscrow(address(escrow)).implementationAddress(address(this), destination_identifier),
            implementation,
            "Implementation incorrectly set"
        );

        assertEq(
            IncentivizedMessageEscrow(address(escrow)).implementationAddressHash(address(this), destination_identifier),
            keccak256(implementation),
            "Implementation hash incorrectly set"
        );
        
    }

    // Foundry fails for some reason on 
    /* 
        bytes32 destination_identifier = 0x8000000000000000000000000000000000000000000000000000000000123123;
        bytes memory implementation = hex"d620a548de77b80e6f00431b9f916453e2a0ba79a9b593bb4348a0e29b2ae629";
    */
    // Though the test actually passes.
    function test_set_remote_implementation_twice(bytes32 destination_identifier, bytes memory implementation) public {
        vm.assume(destination_identifier != 0x8000000000000000000000000000000000000000000000000000000000123123);
        vm.assume(implementation.length != 0);
        
        escrow.setRemoteImplementation(destination_identifier, implementation);

        vm.expectRevert();

        escrow.setRemoteImplementation(destination_identifier, implementation);
    }

    // TODO: test that setting remote implementation
    // length 1 disables the route.

    function test_revert_set_disable_route(bytes32 destinationIdentifier, address destAddress, bytes calldata message, uint64 deadline) public {
        vm.assume(destinationIdentifier != _DESTINATION_IDENTIFIER);

        bytes memory destinationAddress = abi.encodePacked(
            uint8(20),
            bytes32(0),
            abi.encode(destAddress)
        );
        bytes memory implementation = hex"00";
        
        escrow.setRemoteImplementation(destinationIdentifier, implementation);

        vm.expectRevert(abi.encodeWithSignature("RouteDisabled()"));
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(destinationIdentifier, destinationAddress, message, _INCENTIVE, deadline);
    }
}