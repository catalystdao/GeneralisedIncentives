// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { MockSpendGas } from "../../mocks/MockSpendGas.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract GasSpendControlTest is TestCommon {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    bytes _DESTINATION_ADDRESS_SPENDGAS;

    function setUp() override public {
        super.setUp();
        // Set a new application
        application = ICrossChainReceiver(address(new MockSpendGas(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(application))))
        );
    }

    function test_process_delivery_gas() public {
        bytes memory message = abi.encodePacked(bytes2(uint16(1000)));

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasDelivery = 193010;  // This is not enough gas to execute the receiveCall. We should expect the sub-call to revert but the main call shouldn't.

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(address(application), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectEmit();
        // Check that the ack is set to 0xff
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
                destinationFeeRecipitent,
                uint48(0x36eb2),  // Gas used
                uint64(1),
                bytes1(0xff),  // This states that the call went wrong.
                message
            )
        );

        escrow.processMessage(
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }

    function test_process_ack_gas() public {
        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasAck = 193010;  // This is not enough gas to execute the Ack. We should expect the sub-call to revert but the main call shouldn't.

        (, bytes memory messageWithContext) = setupForAck(address(application), abi.encodePacked(bytes2(uint16(1000))), destinationFeeRecipitent);


        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        escrow.processMessage(
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }

    function test_fail_relayer_has_to_provide_enough_gas() public {
        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasDelivery = 200000;  // This is not enough gas to execute the receiveCall. We should expect the sub-call to revert but the main call shouldn't.

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(address(application), abi.encodePacked(bytes2(uint16(1000))));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        uint256 snapshot_num = vm.snapshot();

        // The strange gas limit of '<gas> + 5000 - 2' here is because <gas> is how much is actually spent (read from trace) and + 5000 - 2 is some kind of refund that
        // the relayer needs to add as extra. (reentry refund)
        escrow.processMessage{gas: 239891}(
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );

        vm.revertTo(snapshot_num);

        // While not perfect, it is a decent way to ensure that the gas delivery is kept true.
        vm.expectRevert();
        vm.expectCall(
            address(application),
            abi.encodeCall(
                application.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a",
                    hex"03e8"
                )
            )
        );
        escrow.processMessage{gas: 239891 - 1}(
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }
    
    // relayer incentives will be sent here
    receive() payable external {
    }
}