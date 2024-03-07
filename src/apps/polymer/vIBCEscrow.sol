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
import  "vibc-core-smart-contracts/interfaces/IbcDispatcher.sol";
import {
    IbcReceiverBase, IbcReceiver
} from "vibc-core-smart-contracts/interfaces/IbcReceiver.sol";

/// @notice Polymer implementation of the Generalised Incentives based on vIBC.
contract IncentivizedPolymerEscrow is APolymerEscrow, IbcReceiverBase, IbcReceiver {

    bytes32[] public connectedChannels;
    string constant VERSION = '1.0';

    constructor(address sendLostGasTo, address dispatcher)
        APolymerEscrow(sendLostGasTo)
        IbcReceiverBase(IbcDispatcher(dispatcher))
    {}

    // IBC callback functions

    function onOpenIbcChannel(
        string calldata version,
        ChannelOrder /*  */,
        bool,
        string[] calldata,
        CounterParty calldata counterparty
    ) external view onlyIbcDispatcher returns (string memory selectedVersion) {
        if (counterparty.channelId == bytes32(0)) {
            // ChanOpenInit
            require(
                keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked(VERSION)),
                'Unsupported version'
            );
        } else {
            // ChanOpenTry
            require(
                keccak256(abi.encodePacked(counterparty.version)) == keccak256(abi.encodePacked(VERSION)),
                'Unsupported version'
            );
        }
        return VERSION;
    }

    function onConnectIbcChannel(
        bytes32 channelId,
        bytes32,
        string calldata counterpartyVersion
    ) external onlyIbcDispatcher {
        require(
            keccak256(abi.encodePacked(counterpartyVersion)) == keccak256(abi.encodePacked(VERSION)),
            'Unsupported version'
        );
        connectedChannels.push(channelId);
    }

    function onCloseIbcChannel(bytes32 channelId, string calldata, bytes32) external onlyIbcDispatcher {
        // logic to determin if the channel should be closed
        bool channelFound = false;
        for (uint256 i = 0; i < connectedChannels.length; i++) {
            if (connectedChannels[i] == channelId) {
                delete connectedChannels[i];
                channelFound = true;
                break;
            }
        }
        require(channelFound, 'Channel not found');
    }

    // packet.srcPortAddr is the IncentivizedPolymerEscrow address on the source chain.
    // packet.destPortAddr is the address of this contract.
    // channelId: the universal channel id from the running chain's perspective, which can be used to identify the counterparty chain.
    function onRecvPacket(IbcPacket calldata packet)
        external override
        onlyIbcDispatcher
        returns (AckPacket memory)
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes memory sourceImplementationIdentifier = bytes.concat(hex""); // TODO packet.src.portId decode from a mapping

        bytes memory receiveAck =
            _handleMessage(packet.src.channelId, sourceImplementationIdentifier, packet.data, feeRecipitent, gasLimit);

        // Send ack:
        return AckPacket({success: true, data: receiveAck});
    }

    // The escrow manages acks, so any message can be directly provided to _handleAck.
    function onAcknowledgementPacket(
        IbcPacket calldata packet,
        AckPacket calldata ack
    )
        external override
        onlyIbcDispatcher
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = ack.data;
        bytes memory destinationImplementationIdentifier = bytes.concat(hex""); // TODO packet.dest.portId , we need to map from channelId.

        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: packet.src.channelId,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(packet.src.channelId, destinationImplementationIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeoutPacket(IbcPacket calldata packet) external override onlyIbcDispatcher{
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = packet.data;
        bytes32 messageIdentifier = bytes32(rawMessage[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        address fromApplication = address(uint160(bytes20(rawMessage[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END])));
        _handleTimeout(
            packet.src.channelId, messageIdentifier, fromApplication, rawMessage[CTX0_MESSAGE_START:], feeRecipitent, gasLimit
        );
    }

    /**
     * @param destinationChainIdentifier  Universal Channel ID. It's always from the running chain's perspective.
     * Each universal channel/channelId represents a directional path from the running chain to a destination chain.
     * Universal ChannelIds should _destChainIdToChannelIdd from the Polymer registry.
     * Although everyone is free to establish their own channels, they're not "officially" vetted until they're in the Polymer registry.
     * @param message packet payload
     * @param deadline Packet will timeout after the dest chain's block time in nanoseconds since the epoch passes timeoutTimestamp.
     */
    function _sendPacket(
        bytes32 destinationChainIdentifier,
        bytes memory /* destinationImplementation */,
        bytes memory message,
        uint64 deadline
    ) internal override returns (uint128 costOfsendPacketInNativeToken) {
        // If timeoutTimestamp is set to 0, set it to maximum. This does not really apply to Polymer since it is an onRecv implementation
        // but it should still conform to the general spec of Generalised Incentives.
        uint64 timeoutTimestamp = deadline > 0 ? deadline : type(uint64).max;

        dispatcher.sendPacket(destinationChainIdentifier, message, timeoutTimestamp);
        return 0;
    }
}
