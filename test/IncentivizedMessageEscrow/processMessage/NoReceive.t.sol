// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { BadContract } from "../../mocks/BadContract.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract ProcessMessageNoReceiveTest is TestCommon {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function setUp() override public {
        super.setUp();
        application = ICrossChainReceiver(address(new BadContract()));

        vm.prank(address(application));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(application))))
        );
    }
    
    function test_application_does_not_implement_interface() public {
        bytes memory message = _MESSAGE;
        bytes32 feeRecipitent = bytes32(uint256(uint160(address(this))));

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(address(escrow), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

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
                _DESTINATION_IDENTIFIER,
                _DESTINATION_IDENTIFIER,
                bytes1(0x01),
                messageIdentifier,
                _DESTINATION_ADDRESS_THIS,
                feeRecipitent,
                uint48(0x8885),  // Gas used
                uint64(1),
                abi.encodePacked(bytes1(0xff)),
                message
            )
        );

        vm.expectCall(
            address(application),
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

        escrow.processMessage(
            mockContext,
            messageWithContext,
            feeRecipitent
        );
    }
}