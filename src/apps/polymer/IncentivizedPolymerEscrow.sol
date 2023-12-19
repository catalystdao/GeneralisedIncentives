// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMETimeoutExtension} from "../../TimeoutExtension.sol";
import {MockOnRecvAMB} from "../../../test/mocks/MockOnRecvAMB.sol";

import {AckPacket} from "vibc-core-smart-contracts/contracts/Ibc.sol";
import {
    IbcMwUser,
    UniversalPacket,
    IbcUniversalPacketSender,
    IbcUniversalPacketReceiver
} from "vibc-core-smart-contracts/contracts/IbcMiddleware.sol";

/// @notice Polymer implementation of the Generalised Incentives based on vIBC.
/// @dev Notice that since the relayer is read from tx.origin, this implementation only works between EVM chains.
contract IncentivizedPolymerEscrow is IMETimeoutExtension, IbcMwUser, IbcUniversalPacketReceiver {
    error NonVerifiableMessage();
    error NotImplemented();
    error MessagingProtocolSetToAddress0();

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    // packet will timeout if it's delivered on the destination chain after (this block time + _TIMEOUT_AFTER_BLOCK).
    uint64 constant _TIMEOUT_AFTER_BLOCK = 1 days;

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;

    // Internal function for gas savings.
    function _UNIQUE_SOURCE_IDENTIFIER() internal view returns (bytes32) {
        return bytes32(block.chainid);
    }

    // Expose internal function.
    function UNIQUE_SOURCE_IDENTIFIER() external view returns (bytes32) {
        return _UNIQUE_SOURCE_IDENTIFIER();
    }

    constructor(address sendLostGasTo, address messagingProtocol)
        IMETimeoutExtension(sendLostGasTo)
        IbcMwUser(messagingProtocol)
    {
        if (messagingProtocol == address(0)) revert MessagingProtocolSetToAddress0();
    }

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
    /// When packages arrive on ack, they are stored such that the verification scheme works.
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

    /**
     * @notice Called when a package arrives from a Polymer relayer.
     * @param channelId The universal channel id from the running chain's perspective, which can be used to identify the counterparty chain.
     * @param packet The packet along with packet context.
     *  packet.srcPortAddr is the IncentivizedPolymerEscrow address on the source chain.
     *  packet.destPortAddr is the address of this contract.
     */
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

    /**
     * @notice Called when a package is acked.
     * @param channelId The universal channel id from the running chain's perspective, which can be used to identify the counterparty chain.
     * @param packet The packet along with packet context.
     * @param ack The ack from the destination chain. Note that acknowledgement data is used over the package data
     * even if there is repeated information. That is a limitation of the design of Generalised Incentives.
     */
    function onUniversalAcknowledgement(bytes32 channelId, UniversalPacket calldata packet, AckPacket calldata ack)
        external
        onlyIbcMw
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = ack.data;
        bytes memory destinationImplementationIdentifier = abi.encodePacked(packet.destPortAddr);

        // Allow acks to be redelivered.
        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: channelId,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(channelId, destinationImplementationIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    /**
     * @notice Called when a package is timedout.
     * @dev This is a special case when the package hasn't executed on the destination chain and an
     * "ack-ish" is returned. The special handler: _handleTimeout is used to fix the packet. 
     * @param packet The packet along with packet context.
     */
    function onTimeoutUniversalPacket(bytes32 channelId, UniversalPacket calldata packet) external onlyIbcMw {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = packet.appData;
        _handleTimeout(channelId, rawMessage, feeRecipitent, gasLimit);
    }

    /**
     * @notice Send to Polymer for handling
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
