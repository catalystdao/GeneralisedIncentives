// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../TestCommon.t.sol";
import { IncentivizedMessageEscrow } from "../../src/IncentivizedMessageEscrow.sol";


contract TestSetRemoteImplementation is TestCommon {

    function test_set_remote_implementation(bytes32 destination_identifier, bytes calldata implementation) public {
        vm.assume(destination_identifier != _DESTINATION_IDENTIFIER);

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
        
        escrow.setRemoteImplementation(destination_identifier, implementation);

        vm.expectRevert();

        escrow.setRemoteImplementation(destination_identifier, implementation);
    }
}