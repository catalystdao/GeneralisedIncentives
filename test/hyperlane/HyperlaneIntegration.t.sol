// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// mocks
import { MockIsm } from "./mocks/mockIsm.sol";
import { MockMailbox } from "./mocks/MockMailbox.sol";
import { MockApplication } from "../mocks/MockApplication.sol";
import { ReplacementHook } from "../../src/apps/hyperlane/ReplacementHook.sol";

import { IncentivizedHyperlaneEscrow } from "../../src/apps/hyperlane/IncentivizedHyperlaneEscrow.sol";
import { IMessageEscrowStructs } from "../../src/interfaces/IMessageEscrowStructs.sol";

contract HyperlaneTest is Test, IMessageEscrowStructs {

    IncentiveDescription _INCENTIVE;

    address application;
    IncentivizedHyperlaneEscrow escrow;
    bytes32 destinationIdentifier;
    address sendLostGasTo;

    // Deploy relevant contracts    
    function setUp() external {


        destinationIdentifier = bytes32(block.chainid);
        uint32 destinationIdentifier_uint32 = uint32(uint256(destinationIdentifier));
        address MockHook = address(new ReplacementHook());
        address mockIsm = address(new MockIsm());
        address mockMailbox = address(new MockMailbox(destinationIdentifier_uint32, mockIsm, MockHook, MockHook));
        sendLostGasTo = address(uint160(57005));
        escrow = new IncentivizedHyperlaneEscrow(sendLostGasTo, mockIsm, mockMailbox);

        application = address(new MockApplication(address(escrow)));


        _INCENTIVE = IncentiveDescription({
            maxGasDelivery: 1199199,
            maxGasAck: 1188188,
            refundGasTo: sendLostGasTo,
            priceOfDeliveryGas: 123321,
            priceOfAckGas: 321123,
            targetDelta: 30 minutes
        });
    }

    function _getTotalIncentive(IncentiveDescription memory incentive) internal pure returns(uint256) {
        return incentive.maxGasDelivery * incentive.priceOfDeliveryGas + incentive.maxGasAck * incentive.priceOfAckGas;
    }

    function test_hyperlane_integration() external {
        bytes memory message = abi.encode(uint256(251251251));
        payable(application).transfer(_getTotalIncentive(_INCENTIVE));

        // Set remote implementation contract
        vm.prank(application);
        escrow.setRemoteImplementation(destinationIdentifier, abi.encode(address(escrow)));


        // Escrow a message as the application
        vm.prank(application);
        vm.recordLogs();
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            destinationIdentifier,
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                abi.encode(application)
            ),
            message,
            _INCENTIVE
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // The majority of the data emitted by the mailbox is indexed. That is ignored by this function.
        // If we wanted to get that, we should look in the topics.
        (bytes memory package) = abi.decode(entries[1].data, (bytes));

        // Source to destination
        vm.recordLogs();
        escrow.processPacket(hex"01", package, bytes32(uint256(uint160(sendLostGasTo))));

        entries = vm.getRecordedLogs();

        // Get the new package.
        (package) = abi.decode(entries[1].data, (bytes));

        escrow.processPacket(hex"01", package, bytes32(uint256(uint160(sendLostGasTo))));
    }

    function test_hyperlane_integration(bytes memory message) external {
        payable(application).transfer(_getTotalIncentive(_INCENTIVE));

        // Set remote implementation contract
        vm.prank(application);
        escrow.setRemoteImplementation(destinationIdentifier, abi.encode(address(escrow)));


        // Escrow a message as the application
        vm.prank(application);
        vm.recordLogs();
        escrow.submitMessage{value: _getTotalIncentive(_INCENTIVE)}(
            destinationIdentifier,
            abi.encodePacked(
                uint8(20),
                bytes32(0),
                abi.encode(application)
            ),
            message,
            _INCENTIVE
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        (bytes memory package) = abi.decode(entries[1].data, (bytes));

        // IGNORE ABOVE, FOCUS BELOW:

        // Tell the ISM to fail:
        vm.expectRevert(
            abi.encodeWithSignature("ISMVerificationFailed()")
        );      
        escrow.processPacket(hex"00", package, bytes32(uint256(uint160(sendLostGasTo))));

        // Tell the ISM to not fail.
        escrow.processPacket(hex"01", package, bytes32(uint256(uint160(sendLostGasTo))));
    }
}