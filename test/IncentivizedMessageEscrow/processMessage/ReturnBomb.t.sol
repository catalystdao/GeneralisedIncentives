// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { TestCommon } from "../../TestCommon.t.sol";
import { ReturnBomber } from "../../mocks/ReturnBomber.sol";
import { ICrossChainReceiver } from "../../../src/interfaces/ICrossChainReceiver.sol";


contract ReturnBombTest is TestCommon {
    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    bytes _DESTINATION_ADDRESS_SPENDGAS;

    function setUp() override public {
        super.setUp();
        // Set a new application
        application = ICrossChainReceiver(address(new ReturnBomber(address(escrow))));

        // Set implementations to the escrow address.
        vm.prank(address(application));
        escrow.setRemoteImplementation(_DESTINATION_IDENTIFIER, abi.encode(address(escrow)));

        _DESTINATION_ADDRESS_APPLICATION = abi.encodePacked(
            uint8(20),
            bytes32(0),
            bytes32(uint256(uint160(address(application))))
        );
    }


    function test_process_ack_gas() public {
        bytes32 destinationFeeRecipitent = bytes32(uint256(uint160(address(this))));

        _INCENTIVE.maxGasAck = 10000000;  // This is not enough gas to execute the Ack. We should expect the sub-call to revert but the main call shouldn't.

        (, bytes memory messageWithContext) = setupForAck(address(application), abi.encodePacked(bytes2(uint16(1))), destinationFeeRecipitent);


        (uint8 v, bytes32 r, bytes32 s) = signMessageForMock(messageWithContext);
        bytes memory mockContext = abi.encode(v, r, s);

        uint256 beforeReturnBomb = gasleft();
        escrow.processPacket(
            mockContext,
            messageWithContext,
            destinationFeeRecipitent
        );
        uint256 afterReturnBomb = gasleft();

        assertGt(
            _INCENTIVE.maxGasAck,
            beforeReturnBomb - afterReturnBomb,
            "Return bomb used more gas than expected" 
        );
    }

    // relayer incentives will be sent here
    receive() payable external {
    }
}