// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {APolymerEscrow} from "./APolymerEscrow.sol";
import "../../MessagePayload.sol";

import {AckPacket} from "vibc-core-smart-contracts/libs/Ibc.sol";
import {
    IbcMwUser,
    UniversalPacket,
    IbcUniversalPacketSender,
    IbcUniversalPacketReceiver
} from "vibc-core-smart-contracts/interfaces/IbcMiddleware.sol";

/// @notice Polymer implementation of the Generalised Incentives based on vIBC.
contract UniversalPolymerEscrow is APolymerEscrow, IbcMwUser, IbcUniversalPacketReceiver {

    constructor(address sendLostGasTo, address messagingProtocol)
        APolymerEscrow(sendLostGasTo)
        IbcMwUser(messagingProtocol)
    {}

    // packet.srcPortAddr is the UniversalPolymerEscrow address on the source chain.
    // packet.destPortAddr is the address of this contract.
    // channelId: the universal channel id from the running chain's perspective, which can be used to identify the counterparty chain.
    function onRecvUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        onlyIbcMw
        returns (AckPacket memory)
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes memory sourceImplementationIdentifier = bytes.concat(packet.srcPortAddr);

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
        bytes memory destinationImplementationIdentifier = bytes.concat(packet.destPortAddr);

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
        bytes32 messageIdentifier = bytes32(rawMessage[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        address fromApplication = address(uint160(bytes20(rawMessage[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END])));
        _handleTimeout(
            channelId, messageIdentifier, fromApplication, rawMessage[CTX0_MESSAGE_START:], feeRecipitent, gasLimit
        );
    }

    /**
     * @param destinationChainIdentifier  Universal Channel ID. It's always from the running chain's perspective.
     * Each universal channel/channelId represents a directional path from the running chain to a destination chain.
     * Universal ChannelIds should _destChainIdToChannelIdd from the Polymer registry.
     * Although everyone is free to establish their own channels, they're not "officially" vetted until they're in the Polymer registry.
     * @param destinationImplementation UniversalPolymerEscrow address on the counterparty chain.
     * @param message packet payload
     * @param deadline Packet will timeout after the dest chain's block time in nanoseconds since the epoch passes timeoutTimestamp.
     */
    function _sendPacket(
        bytes32 destinationChainIdentifier,
        bytes memory destinationImplementation,
        bytes memory message,
        uint64 deadline
    ) internal override returns (uint128 costOfsendPacketInNativeToken) {
        // If timeoutTimestamp is set to 0, set it to maximum. This does not really apply to Polymer since it is an onRecv implementation
        // but it should still conform to the general spec of Generalised Incentives.
        uint64 timeoutTimestamp = deadline > 0 ? deadline : type(uint64).max;
        IbcUniversalPacketSender(mw).sendUniversalPacket(
            destinationChainIdentifier, bytes32(destinationImplementation), message, timeoutTimestamp
        );
        return 0;
    }
}
