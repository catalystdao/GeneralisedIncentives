// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract AckReentryTest is TestCommon, ICrossChainReceiver {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    // Placeholder
    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata /* message */) external pure returns(bytes memory acknowledgement) {
        return abi.encodePacked(uint8(1));
    }

    function test_reentry_on_ack_message() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        application = ICrossChainReceiver(address(this));

        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160((address(this)))))
        );

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(address(escrow), message, feeRecipitent);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);
        

        vm.expectCall(
            address(this),
            abi.encodeCall(
                application.ackMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    abi.encodePacked(uint8(1))
                )
            )
        );

        _mockContext = mockContext;
        _messageWithContext = messageWithContext;
        _feeRecipitent = feeRecipitent;

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );

        assertEq(flag, true, "Reentry protection not working as expected on ack.");
    }

    // reentry variables
    bytes _mockContext;
    bytes _messageWithContext;
    bytes32 _feeRecipitent;

    bool flag;

    function ackMessage(bytes32 /* destinationIdentifier */, bytes32 /* messageIdentifier */, bytes calldata acknowledgement) external {
        vm.expectRevert(
            abi.encodeWithSignature("MessageAlreadyAcked()")
        ); 
        escrow.processMessage(
            _mockContext,
            _messageWithContext,
            _feeRecipitent
        );

        // if this reverts (because vm.expectRevert didn't handle the revert), then the next line is not hit.
        // otherwise it is. Lets capture the flag:
        flag = true;
    }

    receive() payable external {

    }
}