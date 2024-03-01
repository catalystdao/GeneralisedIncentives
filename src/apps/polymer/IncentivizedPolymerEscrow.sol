// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMETimeoutExtension} from "../../TimeoutExtension.sol";
import {MockOnRecvAMB} from "../../../test/mocks/MockOnRecvAMB.sol";

import {AckPacket} from "vibc-core-smart-contracts/Ibc.sol";
import {
    IbcMwUser,
    UniversalPacket,
    IbcUniversalPacketSender,
    IbcUniversalPacketReceiver
} from "vibc-core-smart-contracts/IbcMiddleware.sol";

/// @notice Polymer implementation of the Generalised Incentives based on vIBC.
contract IncentivizedPolymerEscrow is IMETimeoutExtension, IbcMwUser, IbcUniversalPacketReceiver {
    error NotEnoughGasProvidedForVerification();
    error NonVerifiableMessage();
    error NotImplemented();

    // Internal function for gas savings.
    function _UNIQUE_SOURCE_IDENTIFIER() internal view returns (bytes32) {
        return bytes32(block.chainid);
    }

    // Expose internal function.
    function UNIQUE_SOURCE_IDENTIFIER() external view returns (bytes32) {
        return _UNIQUE_SOURCE_IDENTIFIER();
    }

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;
    // packet will timeout if it's delivered on the destination chain after (this block time + _TIMEOUT_AFTER_BLOCK).
    uint64 constant _TIMEOUT_AFTER_BLOCK = 1 days;

    constructor(address sendLostGasTo, address messagingProtocol)
        IMETimeoutExtension(sendLostGasTo)
        IbcMwUser(messagingProtocol)
    {}

    function estimateAdditionalCost() external pure returns (address asset, uint256 amount) {
        asset = address(0);
        amount = 0;
    }

    function _getMessageIdentifier(bytes32 destinationIdentifier, bytes calldata message)
        internal
        view
        override
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(bytes32(block.number), _UNIQUE_SOURCE_IDENTIFIER(), destinationIdentifier, message)
        );
    }

    /// @notice This function is used to allow acks to be executed twice (if the first one ran out of gas)
    /// This is not intended to allow processPacket to work.
    function _verifyPacket(bytes calldata, /* _metadata */ bytes calldata _message)
        internal
        view
        override
        returns (bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_)
    {
        sourceIdentifier = isVerifiedMessageHash[keccak256(_message)].chainIdentifier;
        implementationIdentifier = isVerifiedMessageHash[keccak256(_message)].implementationIdentifier;

        if (sourceIdentifier == bytes32(0)) revert NonVerifiableMessage();

        message_ = _message;
    }

    /// @dev Disable processPacket
    function processPacket(
        bytes calldata, /* messagingProtocolContext */
        bytes calldata, /* rawMessage */
        bytes32 /* feeRecipitent */
    ) external payable override {
        revert NotImplemented();
    }

    // packet.srcPortAddr is the IncentivizedPolymerEscrow address on the source chain.
    // packet.destPortAddr is the address of this contract.
    // channelId: the universal channel id from the running chain's perspective, which can be used to identify the counterparty chain.
    function onRecvUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        onlyIbcMw
        returns (AckPacket memory)
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes memory sourceImplementationIdentifier = abi.encodePacked(packet.srcPortAddr);

        bytes memory receiveAck =
            _handleMessage(channelId, sourceImplementationIdentifier, packet.appData, feeRecipitent, gasLimit);

        // Send ack:
        return AckPacket({success: true, data: receiveAck});
    }

    // The escrow manages acks, so any message can be directly provided to _handleAck.
    function onUniversalAcknowledgement(bytes32 channelId, UniversalPacket calldata packet, AckPacket calldata ack)
        external
        onlyIbcMw
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = ack.data;
        bytes memory destinationImplementationIdentifier = abi.encodePacked(packet.destPortAddr);

        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: channelId,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(channelId, destinationImplementationIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeoutUniversalPacket(bytes32 channelId, UniversalPacket calldata packet) external onlyIbcMw {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = packet.appData;
        _handleTimeout(channelId, rawMessage, feeRecipitent, gasLimit);
    }

    // * Send to messaging_protocol
    /**
     * @param destinationChainIdentifier  Universal Channel ID. It's always from the running chain's perspective.
     * Each universal channel/channelId represents a directional path from the running chain to a destination chain.
     * Universal ChannelIds should _destChainIdToChannelIdd from the Polymer registry.
     * Although everyone is free to establish their own channels, they're not "officially" vetted until they're in the Polymer registry.
     * @param destinationImplementation IncentivizedPolymerEscrow address on the counterparty chain.
     * @param message packet payload
     */
    function _sendPacket(
        bytes32 destinationChainIdentifier,
        bytes memory destinationImplementation,
        bytes memory message
    ) internal override returns (uint128 costOfsendPacketInNativeToken) {
        // Packet will timeout after the dest chain's block time in nanoseconds since the epoch passes timeoutTimestamp.
        uint64 timeoutTimestamp = uint64(block.timestamp + _TIMEOUT_AFTER_BLOCK) * 1e9;
        IbcUniversalPacketSender(mw).sendUniversalPacket(
            destinationChainIdentifier, bytes32(destinationImplementation), message, timeoutTimestamp
        );
        return 0;
    }
}
