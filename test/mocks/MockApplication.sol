// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

/**
 * @title Example application contract
 */
contract MockApplication is ICrossChainReceiver {
    
    event EscrowMessage(uint256 gasRefund, bytes32 messageIdentifier);
    event AckMessage(bytes32 destinationIdentifier, bytes acknowledgement);
    event ReceiveMessage(bytes32 sourceIdentifierbytes, bytes fromApplication, bytes message, bytes acknowledgement);

    IIncentivizedMessageEscrow immutable MESSAGE_ESCROW;

    constructor(address messageEscrow_) {
        MESSAGE_ESCROW = IIncentivizedMessageEscrow(messageEscrow_);
    }

    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IIncentivizedMessageEscrow.IncentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        (gasRefund, messageIdentifier) = MESSAGE_ESCROW.escrowMessage{value: msg.value}(
            destinationIdentifier,
            destinationAddress,
            message,
            incentive
        );

        // emit EscrowMessage(gasRefund, messageIdentifier);
    }

    function ackMessage(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) pure external {
        // emit AckMessage(destinationIdentifier, acknowledgement);
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata fromApplication, bytes calldata message) pure external returns(bytes memory acknowledgement) {
        acknowledgement = abi.encodePacked(keccak256(bytes.concat(message, fromApplication)));
        // emit ReceiveMessage(
        //     sourceIdentifierbytes,
        //     fromApplication,
        //     message,
        //     acknowledgement
        // );
        return acknowledgement;
    }

}
