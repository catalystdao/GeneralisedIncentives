// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestOnRecvCommon } from "../TestOnRecvCommon.t.sol";


contract OnRecvAckTest is TestOnRecvCommon {

    function test_on_ack() public {
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
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        vm.recordLogs();
        escrow.onReceive(
            _DESTINATION_IDENTIFIER,
            abi.encode(address(escrow)),
            messageWithContext,
            bytes32(uint256(uint160(address(this))))
        );
        entries = vm.getRecordedLogs();

        (, , messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));



        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageAcked(messageIdentifier);

        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveAck,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"d9b60178cfb2eb98b9ff9136532b6bd80eeae6a2c90a2f96470294981fcfb62b"
                )
            )
        );

        escrow.onAck(
            _DESTINATION_IDENTIFIER,
            abi.encode(address(escrow)),
            messageWithContext,
            bytes32(uint256(uint160(address(this))))
        );
    }

    receive() external payable {}
}