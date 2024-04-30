// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { TestOnRecvCommon } from "../TestOnRecvCommon.t.sol";


contract OnRecvTimeoutTest is TestOnRecvCommon {

    function test_on_timeout() public {
        bytes memory message = _MESSAGE;

        vm.recordLogs();
        payable(address(application)).transfer(_getTotalIncentive(_INCENTIVE));
        vm.prank(address(application));
        (, bytes32 messageIdentifier) = escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                abi.encode(address(application))
            ),
            message,
            _INCENTIVE,
            0
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageTimedOut(messageIdentifier);
        // );

        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveAck,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"fdb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        escrow.onTimeout(
            _DESTINATION_IDENTIFIER,
            messageWithContext,
            bytes32(uint256(uint160(address(this))))
        );
    }

    receive() external payable {}
}