// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/apps/mock/IncentivizedMockEscrow.sol";
import "../src/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowEvents } from "../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../src/interfaces/IMessageEscrowStructs.sol";
import { MockApplication } from "./mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../src/interfaces/ICrossChainReceiver.sol";

interface ICansubmitMessage is IMessageEscrowStructs{
    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier);
}

contract TestCommon is Test, IMessageEscrowEvents, IMessageEscrowStructs {
    
    uint256 constant GAS_SPENT_ON_SOURCE = 6888;
    uint256 constant GAS_SPENT_ON_DESTINATION = 32073;
    
    bytes32 constant _DESTINATION_IDENTIFIER = bytes32(uint256(0x123123) + uint256(2**255));

    IIncentivizedMessageEscrow public escrow;
    ICrossChainReceiver public application;
    
    IncentiveDescription _INCENTIVE;
    address _REFUND_GAS_TO;
    bytes _MESSAGE;
    bytes _DESTINATION_ADDRESS_THIS;
    bytes _DESTINATION_ADDRESS_APPLICATION;

    address SIGNER;
    address sendLostGasTo = address(0xdead);
    address BOB;
    uint256 PRIVATEKEY;

    function setUp() virtual public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        _REFUND_GAS_TO = makeAddr("Alice");
        BOB = makeAddr("Bob");
        sendLostGasTo = makeAddr("sendLostGasTo");
        escrow = new IncentivizedMockEscrow(sendLostGasTo, _DESTINATION_IDENTIFIER, SIGNER, 0, 0);

        application = ICrossChainReceiver(address(new MockApplication(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(this));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        _MESSAGE = abi.encode(keccak256(abi.encode(1)));
        _DESTINATION_ADDRESS_THIS = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(this))))
        );
        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(application))))
        );

        _INCENTIVE = IncentiveDescription({
            maxGasDelivery: 1199199,
            maxGasAck: 1188188,
            refundGasTo: _REFUND_GAS_TO,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
    }

    function _getTotalIncentive(IncentiveDescription memory incentive) internal pure returns(uint256) {
        return incentive.maxGasDelivery * incentive.priceOfDeliveryGas + incentive.maxGasAck * incentive.priceOfAckGas;
    }

    function signMessageForMock(bytes memory message) internal view returns(uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(PRIVATEKEY, keccak256(message));
    }

    function getVerifiedMessage(address emitter, bytes memory message) internal view returns(bytes memory _metadata, bytes memory newMessage) {

        newMessage = abi.encodePacked(bytes32(uint256(uint160(emitter))), message);

        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(newMessage);

        _metadata = abi.encode(v, r, s);
    }

    function submitMessage(bytes memory message) internal returns(bytes32) {
        (bytes32 messageIdentifier, ) = setupsubmitMessage(address(application), message);

        return messageIdentifier;
    }

    function setupsubmitMessage(address fromAddress, bytes memory message) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (, uint256 cost) = escrow.estimateAdditionalCost();
        (, bytes32 messageIdentifier) = ICansubmitMessage(fromAddress).submitMessage{value: _getTotalIncentive(_INCENTIVE) + cost}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE,
            0
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return (messageIdentifier, abi.encodePacked(bytes32(uint256(uint160(address(escrow)))), messageWithContext));
    }

    function setupsubmitMessage(address fromAddress, bytes memory message, uint64 deadline) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (, uint256 cost) = escrow.estimateAdditionalCost();
        (, bytes32 messageIdentifier) = ICansubmitMessage(fromAddress).submitMessage{value: _getTotalIncentive(_INCENTIVE) + cost}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE,
            deadline
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return (messageIdentifier, abi.encodePacked(bytes32(uint256(uint160(address(escrow)))), messageWithContext));
    }

    function setupprocessPacket(bytes memory message, bytes32 destinationFeeRecipient) internal returns(bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(message);
        bytes memory mockContext = abi.encode(v, r, s);

        (, uint256 cost) = escrow.estimateAdditionalCost();
        vm.recordLogs();
        escrow.processPacket{value: cost}(
            mockContext,
            message,
            destinationFeeRecipient
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return abi.encodePacked(bytes32(uint256(uint160(address(escrow)))), messageWithContext);
    }

    function setupForAck(address fromAddress, bytes memory message, bytes32 destinationFeeRecipient) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupsubmitMessage(fromAddress, message);

        return (messageIdentifier, setupprocessPacket(messageWithContext, destinationFeeRecipient));
    }

    function memorySlice(bytes calldata data, uint256 start) pure external returns(bytes memory slice) {
        slice = data[start: ];
    }

    function memorySlice(bytes calldata data, uint256 start, uint256 end) pure external returns(bytes memory slice) {
        slice = data[start:end];
    }
}
