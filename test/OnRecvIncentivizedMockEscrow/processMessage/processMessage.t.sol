// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestOnRecvCommon } from "../TestOnRecvCommon.t.sol";


contract TestProcessMessageDisabled is TestOnRecvCommon {

    function test_process_message_disabled(bytes memory mockContext, bytes memory messageWithContext, address feeRecipitent) public {
        vm.expectRevert();
        escrow.processMessage(
            mockContext,
            messageWithContext,
            bytes32(uint256(uint160(feeRecipitent)))
        );
    }
}