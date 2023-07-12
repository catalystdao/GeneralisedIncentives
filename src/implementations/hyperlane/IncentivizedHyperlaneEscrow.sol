// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { IMailbox } from "./interfaces/IMailbox.sol";
import { Message } from "./libs/Message.sol";
import { IInterchainSecurityModule, ISpecifiesInterchainSecurityModule } from "./interfaces/IInterchainSecurityModule.sol";


contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow {
    using Message for bytes;

    // ============ Constants ============

    // Domain of chain on which the contract is deployed
    uint32 public immutable localDomain;

    uint8 public constant VERSION = 0;

    bytes32 constant ALT_DEPLOYMENT = bytes32("0x12341234");

    mapping(bytes32 => bytes32) public destinationToAddress;

    /// @notice Gets this address on the destination chain
    /// @dev Can be overwritten if a messaging router uses some other assumption
    function _getEscrowAddress(bytes32 destinationIdentifier) internal virtual returns(bytes32) {
        // Try to save gas by not accessing storage. If the most significant bit is set to 1, then return itself
        if (uint256(destinationIdentifier) >> 255 == 1) return bytes32(bytes20(address(this)));
        if (uint256(destinationIdentifier) >> 254 == 1) return ALT_DEPLOYMENT;
        // TODO Check gas usage of vs
        // if ((destinationIdentifier & 2**255) == 1) return bytes32(bytes20(address(this)));
        // if ((destinationIdentifier & 2**254) == 1) return ALT_DEPLOYMENT;
        return destinationToAddress[destinationIdentifier];
    }

    IMailbox immutable MAILBOX;

    constructor(bytes32 uniqueChainIndex, address mailbox_, uint32 localDomain_) IncentivizedMessageEscrow(uniqueChainIndex) {
        MAILBOX = IMailbox(mailbox_);
        localDomain = localDomain_;
    }

    // TODO: Figure out if this is a good method to verify the message.
    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata _metadata, bytes calldata _message) internal override returns(bytes calldata message_) {
        // Check that the message was intended for this mailbox.
        require(_message.version() == VERSION, "!version");
        require(_message.destination() == localDomain, "!destination");

        // Verify the message via the ISM.
        IInterchainSecurityModule _ism = IInterchainSecurityModule(
            MAILBOX.recipientIsm(_message.recipientAddress())
        );
        require(_ism.verify(_metadata, _message), "!module");

        return _message.body();
    }

    function _sendMessage(bytes32 destinationIdentifier, bytes memory message) internal override {
        MAILBOX.dispatch(uint32(bytes4(destinationIdentifier)), _getEscrowAddress(destinationIdentifier), message);
    }
}