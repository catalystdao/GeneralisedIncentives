// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { ReplacementHook } from "./ReplacementHook.sol";

import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import { IMessageRecipient } from "./interfaces/IMessageRecipient.sol";
import { IPostDispatchHook } from "./interfaces/hooks/IPostDispatchHook.sol";
import { Message } from "./libs/Message.sol";
import { IMailbox } from "./interfaces/IMailbox.sol";

interface IVersioned {
    function VERSION() view external returns(uint8);
}

/// @notice Hyperlane implementation of Generalised incentives.
contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow, ReplacementHook, ISpecifiesInterchainSecurityModule, IMessageRecipient {
    // ============ Libraries ============

    using Message for bytes;


    error BadChainIdentifier(); // 0x3c1e02c;
    error BadMailboxVersion(uint8 VERSION, uint8 messageVersion); // 0x0d8b788f
    error BadDomain(uint32 localDomain, uint32 messageDestination); // 0x2da4acb6
    error WrongRecipient(address trueRecipient); // 0xb2d27e64
    error ISMVerificationFailed(); // 0x902013b
    error DeliverMessageDirectlyToGeneralisedIncentvies(); // 0xecb92632


    IPostDispatchHook CUSTOM_HOOK = IPostDispatchHook(address(this)); 
    bytes NOTHING = hex"";

    uint32 public immutable localDomain;
    IMailbox public immutable MAILBOX;
    uint8 public immutable VERSION;
    IInterchainSecurityModule immutable INTERCHAIN_SECURITY_MODULE;

    function interchainSecurityModule() external view returns (IInterchainSecurityModule) {
        return INTERCHAIN_SECURITY_MODULE;
    }

    /// @dev The hyperlane mailbox requires the call to not fail.
    /// By always failing, the message cannot be delivered through the hyperlane mailbox.
    function handle(
        uint32 /* _origin */,
        bytes32 /* _sender */,
        bytes calldata /* _message */
    ) external payable {
        revert DeliverMessageDirectlyToGeneralisedIncentvies();
    }

    constructor(address sendLostGasTo, address interchainSecurityModule_, address mailbox_) IncentivizedMessageEscrow(sendLostGasTo){
        MAILBOX = IMailbox(mailbox_);

        // Collect the chain identifier from the mailbox and store it here. 
        // localDomain is immutable on mailbox.
        localDomain = MAILBOX.localDomain();
        VERSION = IVersioned(mailbox_).VERSION();
        INTERCHAIN_SECURITY_MODULE = IInterchainSecurityModule(interchainSecurityModule_);
    }

    /// @notice Get the required cost of the requiredHook. Calling the mailbox directly requires significantly
    /// more gas as it would eventually also call this contract.
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
                msg.sender,
                bytes32(block.number),
                localDomain, 
                destinationIdentifier,
                message
            )
        );
    }

    /// @notice Verify a Hyperlane package. The heavy lifting is done by 
    /// the ism. This function is based on the function `process`
    /// in the Hyperlane Mailbox with optimisations around the errors.
    /// @dev Normally, it is enforced that this function is without side-effects.
    /// However, the ISM interface allows .verify to modify state.
    /// As a result, we cannot manage to promise that.
    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        /// CHECKS ///

        // Check that the message was intended for this "mailbox".
        if (VERSION != _message.version()) revert BadMailboxVersion(VERSION, _message.version());
        if (localDomain != _message.destination()) revert BadDomain(localDomain, _message.destination());

        // Notice that there is no verification that a message hasn't been already delivered. That is because that is done elsewhere.

        // Check if the recipient is this contract.
        address recipient = _message.recipientAddress();
        if (recipient != address(this)) revert WrongRecipient(recipient);
        // We don't have to get the ism, since it is read anyway from this contract. The line would be MAILBOX.recipientIsm(recipient) but it would eventually call this contract anyway.

        /// EFFECTS ///

        // We are not emitting the events since that is not useful.

        /// INTERACTIONS ///

        // Verify the message via the interchain security module.
        if (!INTERCHAIN_SECURITY_MODULE.verify(_metadata, _message)) revert ISMVerificationFailed();

        // Get the application message.
        sourceIdentifier = bytes32(uint256(_message.origin()));
        implementationIdentifier = abi.encodePacked(_message.sender());
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