// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../TestCommon.t.sol";
import { IncentivizedMessageEscrow } from "../../src/IncentivizedMessageEscrow.sol";


contract TestSetRemoteImplementation is TestCommon {

    function test_set_remote_implementation(bytes32 destination_identifier, bytes calldata implementation) public {

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

    function test_set_remote_implementation_twice(bytes32 destination_identifier, bytes calldata implementation) public {
        
        escrow.setRemoteImplementation(destination_identifier, implementation);

        vm.expectRevert(abi.encodeWithSignature("ImplementationAddressAlreadySet(bytes)", implementation));
        escrow.setRemoteImplementation(destination_identifier, implementation);
    }
}