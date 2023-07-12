// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "../interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../interfaces/ICrossChainReceiver.sol";

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

        emit EscrowMessage(gasRefund, messageIdentifier);
    }


    /// @notice Handles the acknowledgement from the destination
    /// @dev acknowledgement is exactly the output of receiveMessage except if receiveMessage reverted, then it is 0x00.
    /// If an acknowledgement isn't needed, this can be implemented as {}.
    /// This function can be called by someone else again. Ensure that if this endpoint is called twice with the same message nothing bad happens.
    /// @param destinationIdentifier An identifier for the destination chain.
    /// @param acknowledgement The acknowledgement sent back by receiveMessage. Is 0x00 if receiveMessage reverted. 
    function ackMessage(bytes32 destinationIdentifier, bytes calldata acknowledgement) external {
        emit AckMessage(destinationIdentifier, acknowledgement);
    }

    /// @notice receiveMessage from a cross-chain call.
    /// @dev The application needs to check the fromApplication combined with sourceIdentifierbytes to figure out if the call is authenticated.
    function receiveMessage(bytes32 sourceIdentifierbytes, bytes calldata fromApplication, bytes calldata message) external returns(bytes memory acknowledgement) {
        acknowledgement = abi.encode(keccak256(bytes.concat(message, fromApplication)));
        emit ReceiveMessage(
            sourceIdentifierbytes,
            fromApplication,
            message,
            acknowledgement
        );
        return acknowledgement;
    }

}
