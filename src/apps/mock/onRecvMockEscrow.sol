// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { OnReceiveV1 } from "../../versions/OnReceiveV1.sol";
import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { EscrowAddress } from "../../utils/EscrowAddress.sol";

// This is an example contract which exposes an onReceive interface. This is for messaging protocols
// where messages are delivered directly to the messaging protocol's contract rather than this contract.
// Comments marked by * imply that an integration point should be changed by external contracts.
contract OnRecvIncentivizedMockEscrow is IncentivizedMessageEscrow, EscrowAddress, OnReceiveV1 {

    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;
    address immutable public MESSAGING_PROTOCOL_CALLER;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    constructor(bytes32 uniqueChainIndex, address messaging_protocol) {
        UNIQUE_SOURCE_IDENTIFIER = uniqueChainIndex;  // * Get from messaging_protocol 
        MESSAGING_PROTOCOL_CALLER = messaging_protocol;
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes32(block.number),
                UNIQUE_SOURCE_IDENTIFIER, 
                destinationIdentifier,
                message
            )
        );
    }

    // Verify that the sender is correct.
    modifier onlyMessagingProtocol() {
        require(msg.sender == MESSAGING_PROTOCOL_CALLER);
        _;
    }

    function onReceive(
        bytes32 chainIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipitent
    ) onlyMessagingProtocol external {
        // _onReceive(chainIdentifier, rawMessage, feeRecipitent);
        uint256 gasLimit = gasleft();
        _handleCall(chainIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // The escrow manages acks, so any message can be directly provided to _onReceive.
    function onAck(
        bytes32 chainIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipitent
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        _handleAck(chainIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeout(
        bytes32 chainIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipitent
    ) onlyMessagingProtocol external {
        // TODO: Figure out a solution where the message is still calldata. Alternativly, reimplement.
        uint256 gasLimit = gasleft();
        _handleAck(chainIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // * Send to messaging_protocol 
    function _sendMessage(bytes32 destinationIdentifier, bytes memory message) internal override {
        emit Message(
            destinationIdentifier,
            _getEscrowAddress(destinationIdentifier),
            abi.encodePacked(
                UNIQUE_SOURCE_IDENTIFIER,
                message
            )
        );
    }
}