// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/apps/mock/IncentivizedMockEscrow.sol";
import "../src/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowEvents } from "../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../src/interfaces/IMessageEscrowStructs.sol";
import "./mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../src/interfaces/ICrossChainReceiver.sol";

interface ICanEscrowMessage is IMessageEscrowStructs{
    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier);
}

contract TestCommon is Test, IMessageEscrowEvents, IMessageEscrowStructs {
    
    uint256 constant GAS_SPENT_ON_SOURCE = 6397;
    uint256 constant GAS_SPENT_ON_DESTINATION = 33443;
    uint256 constant GAS_RECEIVE_CONSTANT = 6178448034;
    
    bytes32 constant _DESTINATION_IDENTIFIER = bytes32(uint256(0x123123) + uint256(2**255));

    IIncentivizedMessageEscrow public escrow;
    ICrossChainReceiver public application;
    
    IncentiveDescription _INCENTIVE;
    address _REFUND_GAS_TO;
    bytes _MESSAGE;
    bytes _DESTINATION_ADDRESS_THIS;
    bytes _DESTINATION_ADDRESS_APPLICATION;

    address SIGNER;
    address BOB;
    uint256 PRIVATEKEY;

    function setUp() virtual public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        _REFUND_GAS_TO = makeAddr("Alice");
        BOB = makeAddr("Bob");
        escrow = new IncentivizedMockEscrow(_DESTINATION_IDENTIFIER, SIGNER, 0);

        application = ICrossChainReceiver(address(new MockApplication(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        vm.prank(address(this));
        escrow.setRemoteEscrowImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

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

    function escrowMessage(bytes memory message) internal returns(bytes32) {
        (bytes32 messageIdentifier, ) = setupEscrowMessage(address(application), message);

        return messageIdentifier;
    }

    function setupEscrowMessage(address fromAddress, bytes memory message) internal returns(bytes32, bytes memory) {
        vm.recordLogs();
        (, uint256 cost) = escrow.estimateAdditionalCost();
        (, bytes32 messageIdentifier) = ICanEscrowMessage(fromAddress).escrowMessage{value: _getTotalIncentive(_INCENTIVE) + cost}(
            _DESTINATION_IDENTIFIER,
            _DESTINATION_ADDRESS_APPLICATION,
            message,
            _INCENTIVE
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return (messageIdentifier, abi.encodePacked(bytes32(uint256(uint160(address(escrow)))), messageWithContext));
    }

    function setupProcessMessage(bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(message);
        bytes memory mockContext = abi.encode(v, r, s);

        (, uint256 cost) = escrow.estimateAdditionalCost();
        vm.recordLogs();
        escrow.processMessage{value: cost}(
            mockContext,
            message,
            destinationFeeRecipitent
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        (, , bytes memory messageWithContext) = abi.decode(entries[1].data, (bytes32, bytes, bytes));

        return abi.encodePacked(bytes32(uint256(uint160(address(escrow)))), messageWithContext);
    }

    function setupForAck(address fromAddress, bytes memory message, bytes32 destinationFeeRecipitent) internal returns(bytes32, bytes memory) {
        (bytes32 messageIdentifier, bytes memory messageWithContext) = setupEscrowMessage(fromAddress, message);

        return (messageIdentifier, setupProcessMessage(messageWithContext, destinationFeeRecipitent));
    }
    
}
