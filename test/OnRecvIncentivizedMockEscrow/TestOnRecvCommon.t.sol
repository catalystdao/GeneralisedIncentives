// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import { OnRecvIncentivizedMockEscrow } from "../../src/apps/mock/OnRecvIncentivizedMockEscrow.sol";
import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { MockOnRecvAMB } from "../mocks/MockOnRecvAMB.sol";
import { IMessageEscrowEvents } from "../../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../../src/interfaces/IMessageEscrowStructs.sol";
import "../mocks/MockApplication.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

contract TestOnRecvCommon is Test, IMessageEscrowEvents, IMessageEscrowStructs, MockOnRecvAMB {
    bytes32 constant _DESTINATION_IDENTIFIER = bytes32(uint256(0x123123) + uint256(2**255));

    OnRecvIncentivizedMockEscrow public escrow;
    ICrossChainReceiver public application;
    
    IncentiveDescription _INCENTIVE;
    address _REFUND_GAS_TO;
    bytes _MESSAGE;
    bytes _DESTINATION_ADDRESS_THIS;
    bytes _DESTINATION_ADDRESS_APPLICATION;
    address sendLostGasTo;

    function setUp() virtual public {
        _REFUND_GAS_TO = makeAddr("Alice");
        sendLostGasTo = makeAddr("sendLostGasTo");
        escrow = new OnRecvIncentivizedMockEscrow(sendLostGasTo, address(this));

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
}
