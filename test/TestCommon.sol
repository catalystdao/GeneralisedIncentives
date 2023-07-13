// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/apps/mock/IncentivizedMockEscrow.sol";
import "../src/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowEvents } from "../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../src/interfaces/IMessageEscrowStructs.sol";
import "../src/test/MockApplication.sol";

contract TestCommon is Test, IMessageEscrowEvents, IMessageEscrowStructs {
    bytes32 constant _DESTINATION_IDENTIFIER = bytes32(uint256(0x123123) + uint256(2**255));

    IIncentivizedMessageEscrow public escrow;
    MockApplication public application;
    
    IncentiveDescription _INCENTIVE;
    bytes _MESSAGE;
    bytes _DESTINATION_ADDRESS_THIS;
    bytes _DESTINATION_ADDRESS_APPLICATION;

    address SIGNER;
    uint256 PRIVATEKEY;

    function setUp() virtual public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        escrow = new IncentivizedMockEscrow(_DESTINATION_IDENTIFIER, SIGNER);
        application = new MockApplication(address(escrow));

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
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 + 1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
    }

    function signMessageForMock(bytes memory message) internal returns(uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(PRIVATEKEY, keccak256(message));
    }
}
