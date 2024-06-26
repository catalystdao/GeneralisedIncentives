// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract CallReentryTest is TestCommon, ICrossChainReceiver {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipient,
        bytes message
    );

    function test_reentry_on_call_message() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipient = bytes32(uint256(uint160(address(this))));

        application = ICrossChainReceiver(address(this));

        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160((address(this)))))
        );

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupsubmitMessage(address(escrow), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);
        

        vm.expectCall(
            address(this),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"1400000000000000000000000000000000000000000000000000000000000000000000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e1496",
                    hex"b10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
                )
            )
        );

        _mockContext = mockContext;
        _messageWithContext = messageWithContext;
        _feeRecipient = feeRecipient;

        vm.expectEmit();
        emit Message(
            _DESTINATION_IDENTIFIER,
            abi.encode(
                escrow
            ),
            abi.encodePacked(
                _DESTINATION_IDENTIFIER,
                _DESTINATION_IDENTIFIER,
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_APPLICATION,
                feeRecipient,
                uint48(0xfccc),  // Gas used
                uint64(1),
                uint8(1)
            )
        );
        escrow.processPacket(
            mockContext,
            messageWithContext,
            feeRecipient
        );

        assertEq(flag, true, "Reentry protection not working as expected on call.");
    }

    // reentry variables
    bytes _mockContext;
    bytes _messageWithContext;
    bytes32 _feeRecipient;

    bool flag;

    // Receive the message and reentry.
    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata /* message */) external returns(bytes memory acknowledgement) {
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadySpent()")
        ); 
        escrow.processPacket(
            _mockContext,
            _messageWithContext,
            _feeRecipient
        );

        flag = true;
        
        return abi.encodePacked(uint8(1));
    }

    // Placeholder
    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) external {
    }
    
}