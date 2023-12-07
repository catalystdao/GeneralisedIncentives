// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";


import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import { Message } from "./libs/Message.sol";
import { IMailbox } from "./interfaces/IMailbox.sol";

interface IVersioned {
    function VERSION() view external returns(uint8);
}

/// @notice Hyperlane implementation of Generalised incentives.
contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow {
    // ============ Libraries ============

    using Message for bytes;


    error BadChainIdentifier();

    address CUSTOM_HOOK = address(this); 
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

    function _quoteDispatch() internal view returns(uint256 amount) {
        amount = MAILBOX.quoteDispatch(uint32(0), address(0), NOTHING, NOTHING, CUSTOM_HOOK);
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = _quoteDispatch();
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

    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        /// CHECKS ///

        // Check that the message was intended for this mailbox.
        require(_message.version() == VERSION, "Mailbox: bad version");
        require(
            _message.destination() == localDomain,
            "Mailbox: unexpected destination"
        );

        // Get the recipient's ISM.
        address recipient = _message.recipientAddress();
        IInterchainSecurityModule ism = MAILBOX.recipientIsm(recipient);

        /// EFFECTS ///

        sourceIdentifier = bytes32(_message.origin());
        implementationIdentifier = abi.encodePacked(_message.sender());

        /// INTERACTIONS ///

        // Verify the message via the interchain security module.
        require(
            ism.verify(_metadata, _message),
            "Mailbox: ISM verification failed"
        );

        // Load the identifier for the calling contract.
        implementationIdentifier = abi.encodePacked(vm.emitterAddress);

        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(payload[0:32]);

        // Check that the message is intended for this chain.
        if (thisChainIdentifier != bytes32(uint256(chainId()))) revert BadChainIdentifier();

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(bytes2(vm.emitterChainId));

        // Get the application message.
        message_ = payload[32:];
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // Get the cost of sending wormhole messages.
        costOfsendPacketInNativeToken = uint128(_quoteDispatch());
        uint32 destinationDomain = uint32(destinationChainIdentifier);

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