// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { EscrowAddress } from "../../utils/EscrowAddress.sol";

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedMockEscrow is IncentivizedMessageEscrow, EscrowAddress, Ownable2Step {
    event ImplementationAddressSet(bytes32 chainIdentifier, bytes32 implementationAddress);

    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;

    mapping(bytes32 => bytes32) public implementationAddress;

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    constructor(bytes32 uniqueChainIndex, address signer) {
        UNIQUE_SOURCE_IDENTIFIER = uniqueChainIndex;
        _transferOwnership(signer);
    }

    function setImplementationAddress(bytes32 chainIdentifier, bytes32 address_) external onlyOwner {
        implementationAddress[chainIdentifier] = address_;

        emit ImplementationAddressSet(chainIdentifier, address_);
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

    function _verifyMessage(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes calldata message_) {

        // Get signature from message payload
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(_metadata, (uint8, bytes32, bytes32));

        // Get signer of message
        address messageSigner = ecrecover(keccak256(_message), v, r, s);

        // Check signer is the same as the stored signer.
        require(messageSigner == owner(), "!signer");
        // Get the source identifier from message payload.
        bytes32 messageSenderIdentifier = bytes32(_message[0:32]);
        sourceIdentifier = bytes32(_message[32:64]);

        require(implementationAddress[sourceIdentifier] == messageSenderIdentifier, "!caller");

        // Get the application message.
        message_ = _message[64:];
    }

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