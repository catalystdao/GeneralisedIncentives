// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";
import { BadlyDesignedRefundTo } from "./mocks/BadRefundTo.sol";


contract NoReceiveTest is TestCommon {
    event ReceiveMessage(
        bytes32 sourceIdentifierbytes,
        bytes fromApplication,
        bytes message,
        bytes acknowledgement
    );
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    BadlyDesignedRefundTo badApplication;
    bytes _DESTINATION_ADDRESS_BAD_APPLICATION;

    function setUp() override public {
        super.setUp();
        badApplication = new BadlyDesignedRefundTo();

        _DESTINATION_ADDRESS_BAD_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(badApplication))))
        );
    }

    function setupEscrowMessage(bytes memory message) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (uint256 gasRefund, bytes32 messageIdentifier) = escrow.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_BAD_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return (messageIdentifier, messageWithContext);
    }

    function test_application_does_not_implement_interface() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        bytes memory mockAck = abi.encode(keccak256(bytes.concat(message, _DESTINATION_ADDRESS_APPLICATION)));

        vm.expectEmit();
        // That a new message is sent back
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                bytes32(uint256(uint160(address(escrow))))
            ),
            abi.encodePacked(
                _DESTINATION_IDENTIFIER,
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_THIS,
                feeRecipitent,
                uint48(0x73ea),  // Gas used
                uint64(1),
                abi.encodePacked(bytes1(0xff)),
                message
            )
        );
        vm.expectEmit();
        // Check MessageDelivered emitted
        emit MessageDelivered(messageIdentifier);

        vm.expectCall(
            address(badApplication),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    hex"1400000000000000000000000000000000000000000000000000000000000000000000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e1496",
                    hex"b10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }
}