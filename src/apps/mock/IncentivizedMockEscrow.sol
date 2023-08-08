// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedMockEscrow is IncentivizedMessageEscrow, Ownable2Step {
    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    constructor(bytes32 uniqueChainIndex, address signer) {
        UNIQUE_SOURCE_IDENTIFIER = uniqueChainIndex;
        _transferOwnership(signer);
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

    function _verifyMessage(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes calldata implementationIdentifier, bytes calldata message_) {

        // Get signature from message payload
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(_metadata, (uint8, bytes32, bytes32));

        // Get signer of message
        address messageSigner = ecrecover(keccak256(_message), v, r, s);

        // Check signer is the same as the stored signer.
        require(messageSigner == owner(), "!signer");

        // Load the identifier for the calling contract.
        implementationIdentifier = _message[0:32];

        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(_message[64:96]);

        // Check that the message is intended for this chain.
        require(thisChainIdentifier == UNIQUE_SOURCE_IDENTIFIER, "!Identifier");

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(_message[64:96]);

        // Get the application message.
        message_ = _message[96:];
    }

    function _sendMessage(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override {
        emit Message(
            destinationChainIdentifier,
            destinationImplementation,
            abi.encodePacked(
                UNIQUE_SOURCE_IDENTIFIER,
                destinationChainIdentifier,
                message
            )
        );
    }
}