// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";
import { MockSpendGas } from "./mocks/MockSpendGas.sol";


contract GasSpendControlTest is TestCommon {
    event AckMessage(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes acknowledgement);

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

    MockSpendGas spendGasApplication;
    bytes _DESTINATION_ADDRESS_SPENDGAS;

    function setUp() override public {
        super.setUp();
        spendGasApplication = new MockSpendGas(address(escrow));

        _DESTINATION_ADDRESS_SPENDGAS = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(spendGasApplication))))
        );
    }

    function setupEscrowMessage(bytes memory message) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (uint256 gasRefund, bytes32 messageIdentifier) = spendGasApplication.escrowMessage{value: _getTotalIncentive(_INCENTIVE)}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_SPENDGAS,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return (messageIdentifier, messageWithContext);
    }

    function setupProcessMessage(bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(message);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.recordLogs();
        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            message,
            destinationFeeRecipitent
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[0].data, (bytes32, bytes, bytes));

        return messageWithContext;
    }


    function setupForAck(bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        return (messageIdentifier, setupProcessMessage(messageWithContext, destinationFeeRecipitent));
    }

    function test_process_delivery_gas() public {
        bytes memory message = _MESSAGE;

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasDelivery = 247002;  // This is not enough gas to execute the receiveCall. We should expect the sub-call to revert but the main call shouldn't.

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(abi.encodePacked(bytes2(uint16(1000))));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        vm.expectEmit();
        // Check that the ack is set to 0xff
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
                _DESTINATION_ADDRESS_SPENDGAS,
                destinationFeeRecipitent,
                uint48(0x42efc),  // Gas used
                uint64(1),
                bytes1(0xff)  // This states that the call went wrong.
            )
        );

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }

    function test_process_ack_gas() public {
        bytes memory message = _MESSAGE;

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasAck = 247002;  // This is not enough gas to execute the Ack. We should expect the sub-call to revert but the main call shouldn't.

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupForAck(abi.encodePacked(bytes2(uint16(1000))), destinationFeeRecipitent);


        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        escrow.processMessage(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }

    function test_fail_relayer_has_to_provide_enough_gas() public {
        bytes memory message = _MESSAGE;

        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasDelivery = 247388*2;  // This is not enough gas to execute the receiveCall. We should expect the sub-call to revert but the main call shouldn't.

        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(abi.encodePacked(bytes2(uint16(1000))));

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        uint256 snapshot_num = vm.snapshot();

        escrow.processMessage{gas: 283536}(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );

        vm.revertTo(snapshot_num);

        // While not perfect, it is a decent way to ensure that the gas delivery is kept true.
        vm.expectRevert();
        vm.expectCall(
            address(spendGasApplication),
            abi.encodeCall(
                spendGasApplication.receiveMessage,
                (
                    bytes32(0x8000000000000000000000000000000000000000000000000000000000123123),
                    messageIdentifier,
                    hex"140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a",
                    hex"03e8"
                )
            )
        );
        escrow.processMessage{gas: 283536 - 1}(
            _DESTINATION_IDENTIFIER,
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
    }
    
    // relayer incentives will be sent here
    receive() payable external {
    }
}