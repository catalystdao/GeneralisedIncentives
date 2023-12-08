// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { ReplacementHook } from "./ReplacementHook.sol";

import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import { IPostDispatchHook } from "./interfaces/hooks/IPostDispatchHook.sol";
import { Message } from "./libs/Message.sol";
import { IMailbox } from "./interfaces/IMailbox.sol";

interface IVersioned {
    function VERSION() view external returns(uint8);
}

/// @notice Hyperlane implementation of Generalised incentives.
contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow, ReplacementHook {
    // ============ Libraries ============

    using Message for bytes;


    error BadChainIdentifier();
    error BadMailboxVersion(uint8 VERSION, uint8 messageVersion);
    error BadDomain(uint32 localDomain, uint32 messageDestination);
    error ISMVerificationFailed();


    IPostDispatchHook CUSTOM_HOOK = IPostDispatchHook(address(this)); 
    bytes NOTHING = hex"";

    uint32 public immutable localDomain;
    IMailbox public immutable MAILBOX;
    uint8 public immutable VERSION;

    constructor(address sendLostGasTo, address mailbox_) IncentivizedMessageEscrow(sendLostGasTo){
        MAILBOX = IMailbox(mailbox_);

        // Collect the chain identifier from the mailbox and store it here. 
        // localDomain is immutable on mailbox.
        localDomain = MAILBOX.localDomain();
        VERSION = IVersioned(mailbox_).VERSION();
    }

    function _requiredHookQuote() internal view returns(uint256 amount) {
        IPostDispatchHook requiredHook = MAILBOX.requiredHook();

        bytes memory message = NOTHING;

        return amount = requiredHook.quoteDispatch(NOTHING, message);
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = _requiredHookQuote();
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes32(block.number),
                localDomain, 
                destinationIdentifier,
                message
            )
        );
    }

    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        /// CHECKS ///

        // Check that the message was intended for this mailbox.
        if(VERSION != _message.version()) revert BadMailboxVersion(VERSION, _message.version());
        if (localDomain != _message.destination()) revert BadDomain(localDomain, _message.destination());

        // Get the recipient's ISM.
        address recipient = _message.recipientAddress();
        IInterchainSecurityModule ism = MAILBOX.recipientIsm(recipient);

        /// EFFECTS ///

        sourceIdentifier = bytes32(uint256(_message.origin()));
        implementationIdentifier = abi.encodePacked(_message.sender());

        /// INTERACTIONS ///

        // Verify the message via the interchain security module.
        if (!ism.verify(_metadata, _message)) revert ISMVerificationFailed();

        // Get the application message.
        message_ = _message.body();
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // Get the cost of sending wormhole messages.
        costOfsendPacketInNativeToken = uint128(_requiredHookQuote());
        uint32 destinationDomain = uint32(uint256(destinationChainIdentifier));

        // Handoff the message to hyperlane
        MAILBOX.dispatch{value: costOfsendPacketInNativeToken}(
            uint32(destinationDomain),
            bytes32(destinationImplementation),
            message,
            hex"",
            CUSTOM_HOOK
        );
    }
}