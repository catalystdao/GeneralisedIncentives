// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestOnRecvCommon } from "../TestOnRecvCommon.t.sol";


contract OnRecvCallTest is TestOnRecvCommon {

    function test_on_call() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

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
        emit MessageDelivered(messageIdentifier);
        vm.expectEmit();
        // That a new message is sent back
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encode(
                escrow
            ),
            abi.encodePacked(
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_APPLICATION,
                feeRecipient,
                uint48(0x6b27),  // Gas used
                uint64(1),
                hex"d9b60178cfb2eb98b9ff9136532b6bd80eeae6a2c90a2f96470294981fcfb62b"
            )
        );

        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"1400000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b",
                    hex"b10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        escrow.onReceive(
            _DESTINATION_IDENTIFIER,
            abi.encode(address(escrow)),
            messageWithContext,
            bytes32(uint256(uint160(address(this))))
        );
    }
}