// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { EscrowAddress } from "../../EscrowAddress.sol";

// This is a mock contract which should only be used for testing
// It does not work as a authenticated message escrow!
// There are several bugs, it is insure and there isn't enough data validation.
contract IncentivizedMockEscrow is IncentivizedMessageEscrow, EscrowAddress {

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    address immutable SIGNER;

    constructor(address signer_) {
        SIGNER = signer_;
    }

    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata _metadata, bytes calldata _message) internal override returns(bytes calldata message_) {
        
        (uint8 v, bytes32 r, bytes1 s) = abi.decode(_metadata, (uint8, bytes32, bytes1));

        address messageSigner = ecrecover(keccak256(_message), v, r, s);
        require(messageSigner == SIGNER, "!signer");

        return _message;
    }

    function _sendMessage(bytes32 destinationIdentifier, bytes memory message) internal override {
        emit Message(
            destinationIdentifier,
            _getEscrowAddress(destinationIdentifier),
            message
        );
    }
}