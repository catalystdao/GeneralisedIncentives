// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "./TestCommon.sol";
import { MockSpendGas } from "./mocks/MockSpendGas.sol";


contract GasSpendControlTest is TestCommon {
    event AckMessage(bytes32 destinationIdentifier, bytes acknowledgement);

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

    function setupProcessMessage(bytes memory message, bytes memory destinationFeeRecipitent) internal returns(bytes memory) {
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

        (bytes32 destinationIdentifier, bytes memory recipitent, bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return messageWithContext;
    }


    function setupForAck(bytes memory message, bytes memory destinationFeeRecipitent) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(message);

        return (messageIdentifier, setupProcessMessage(messageWithContext, destinationFeeRecipitent));
    }

    // function test_process_message_gas() public {
    //     bytes memory message = _MESSAGE;

    //     bytes memory destinationFeeRecipitent = _DESTINATION_ADDRESS_THIS;

    //     _INCENTIVE.maxGasDelivery = 247002;

    //     (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(abi.encode(bytes2(uint16(1000))));

    //     (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
    //     bytes memory mockContext = abi.encode(v, r, s);

    //     console.log(_INCENTIVE.maxGasDelivery);

    //     escrow.processMessage{gas: 1000000}(
    //         _DESTINATION_IDENTIFIER,
    //         mockContext,
    //         messageWithContext,
    //         destinationFeeRecipitent
    //     );
    // }
    
    // relayer incentives will be sent here
    receive() payable external {
    }
}