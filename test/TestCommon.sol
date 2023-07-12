// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/implementations/mock/IncentivizedMockEscrow.sol";
import "../src/interfaces/IIncentivizedMessageEscrow.sol";
import { IMessageEscrowEvents } from "../src/interfaces/IMessageEscrowEvents.sol";
import { IMessageEscrowStructs } from "../src/interfaces/IMessageEscrowStructs.sol";
import "../src/test/MockApplication.sol";

contract TestCommon is Test, IMessageEscrowEvents, IMessageEscrowStructs {
    bytes32 constant _destination_identifier = bytes32(uint256(0x123123) + uint256(2**255));

    IIncentivizedMessageEscrow public escrow;
    MockApplication public application;
    
    IncentiveDescription _incentive;
    bytes _message;

    address SIGNER;
    uint256 PRIVATEKEY;

    function setUp() virtual public {
        (SIGNER, PRIVATEKEY) = makeAddrAndKey("signer");
        escrow = new IncentivizedMockEscrow(SIGNER);
        application = new MockApplication(address(escrow));

        _message = abi.encode(keccak256(abi.encode(1)));

        _incentive = IncentiveDescription({
            minGasDelivery: 1199199,
            minGasAck: 1188188,
            totalIncentive: 1199199 * 123321 + 1188188 * 321123,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });

    }
}
