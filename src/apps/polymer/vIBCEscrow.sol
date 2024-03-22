// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { APolymerEscrow } from "./APolymerEscrow.sol";
import "../../MessagePayload.sol";

import  "vibc-core-smart-contracts/interfaces/IbcDispatcher.sol";
import { AckPacket } from "vibc-core-smart-contracts/libs/Ibc.sol";
import { IbcReceiverBase, IbcReceiver } from "vibc-core-smart-contracts/interfaces/IbcReceiver.sol";

/** 
 * @notice Polymer implementation of the Generalised Incentives based on vIBC.
 * @dev An implementation quirk of Polymer is that channels map 1:1 to BOTH chains
 * and contracts. As a result, if we trust a channel, we also imply that we trust
 * the contract on the other end of that channel. This is unlike "traditional" chain
 * mappings where there may be may addresses on the other end.
 * As a result, we are allowed to just append our address to the package and then trust that.
 * Because if someone trust the channel (which is a requirement) then they must also
 * trust the account AND the set value.
 */
contract IncentivizedPolymerEscrow is APolymerEscrow, IbcReceiverBase, IbcReceiver {
    error ChannelNotFound();
    error UnsupportedVersion();
    error UnsupportedChannelOrder();

    uint constant POLYMER_SENDER_IDENTIFIER_START = 0;
    uint constant POLYMER_SENDER_IDENTIFIER_END = 32;
    uint constant POLYMER_PACKAGE_PAYLOAD_START = 32;

    bytes32[] public connectedChannels;
    string constant VERSION = '1.0';

    // Make a shortcut to save a bit of gas.
    bytes32 immutable ADDRESS_THIS = bytes32(uint256(uint160(address(this))));

    constructor(address sendLostGasTo, address dispatcher)
        APolymerEscrow(sendLostGasTo)
        IbcReceiverBase(IbcDispatcher(dispatcher))
    {}

    //--- IBC Channel Callbacks ---//

    function onOpenIbcChannel(
        string calldata version,
        ChannelOrder order,
        bool,
        string[] calldata,
        CounterParty calldata counterparty
    ) external view onlyIbcDispatcher returns (string memory selectedVersion) {
        // Check that the order is unordered:
        if (order != ChannelOrder.NONE) revert UnsupportedChannelOrder();

        if (counterparty.channelId == bytes32(0)) {
            // ChanOpenInit
            if (
                keccak256(abi.encodePacked(version)) != keccak256(abi.encodePacked(VERSION))
            ) revert UnsupportedVersion();
        } else {
            // ChanOpenTry
            if (
                keccak256(abi.encodePacked(counterparty.version)) != keccak256(abi.encodePacked(VERSION))
            ) revert UnsupportedVersion();
        }
        return VERSION;
    }

    function onConnectIbcChannel(
        bytes32 channelId,
        bytes32,
        string calldata counterpartyVersion
    ) external onlyIbcDispatcher {
        if (
            keccak256(abi.encodePacked(counterpartyVersion)) != keccak256(abi.encodePacked(VERSION))
        ) revert UnsupportedVersion();
        connectedChannels.push(channelId);
    }

    function onCloseIbcChannel(bytes32 channelId, string calldata, bytes32) external onlyIbcDispatcher {
        unchecked {
        // logic to determin if the channel should be closed
        bool channelFound = false;
        for (uint256 i = 0; i < connectedChannels.length; ++i) {
            if (connectedChannels[i] == channelId) {
                delete connectedChannels[i];
                channelFound = true;
                return;
                // We could also break but early return saves gas.
            }
        }
        if (!channelFound) revert ChannelNotFound();

        }
    }

    //--- IBC Packet Callbacks ---//

    // packet.srcPortAddr is the IncentivizedPolymerEscrow address on the source chain.
    // packet.destPortAddr is the address of this contract.
    // channelId: the channel id from the running chain's perspective, which can be used to identify the counterparty chain.
    function onRecvPacket(IbcPacket calldata packet)
        external override
        onlyIbcDispatcher
        returns (AckPacket memory)
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        // Collect the implementation identifier we added. Remember, this is trusted IFF packet.src.channelId is trusted.
        // sourceImplementationIdentifier has already been defined by the channel on channel creation.
        bytes memory sourceImplementationIdentifier = packet.data[POLYMER_SENDER_IDENTIFIER_START:POLYMER_SENDER_IDENTIFIER_END];

        bytes memory receiveAck = _handleMessage(
            packet.src.channelId,
            sourceImplementationIdentifier,
            packet.data[POLYMER_PACKAGE_PAYLOAD_START: ],
            feeRecipitent,
            gasLimit
        );

        // Send ack:
        return AckPacket({success: true, data: bytes.concat(ADDRESS_THIS, receiveAck)});
    }

    function onAcknowledgementPacket(
        IbcPacket calldata packet,
        AckPacket calldata ack
    )
        external override
        onlyIbcDispatcher
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        // Collect the implementation identifier we added. Remember, this is trusted IFF packet.src.channelId is trusted.
        bytes memory destinationImplementationIdentifier = ack.data[POLYMER_SENDER_IDENTIFIER_START:POLYMER_SENDER_IDENTIFIER_END];

        // Get the payload by removing the implementation identifier.
        bytes calldata rawMessage = ack.data[POLYMER_PACKAGE_PAYLOAD_START:];

        // Set a verificaiton context so we can recover the ack.
        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: packet.src.channelId,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(packet.src.channelId, destinationImplementationIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    function onTimeoutPacket(IbcPacket calldata packet) external override onlyIbcDispatcher{
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        // We added a bytes32 implementation identifier. Remove it.
        bytes calldata rawMessage = packet.data[POLYMER_PACKAGE_PAYLOAD_START:];
        bytes32 messageIdentifier = bytes32(rawMessage[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        address fromApplication = address(uint160(bytes20(rawMessage[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END])));
        _handleTimeout(
            packet.src.channelId, messageIdentifier, fromApplication, rawMessage[CTX0_MESSAGE_START:], feeRecipitent, gasLimit
        );
    }

    /**
     * @param destinationChainIdentifier Channel ID. It's always from the running chain's perspective.
     * Each channel/channelId represents a directional path from the running chain to a destination chain
     * AND destination implementation. If we trust a channelId, then it is also implied that we trust the
     *  implementation deployed there.
     * @param message Packet payload. We will add our address to it. This is to standardize with other implementations where we return the destination. 
     * @param deadline Packet will timeout after the dest chain's block time in nanoseconds since the epoch passes timeoutTimestamp. If set to 0 we set it to type(uint64).max.
     */
    function _sendPacket(
        bytes32 destinationChainIdentifier,
        bytes memory /* destinationImplementation */,
        bytes memory message,
        uint64 deadline
    ) internal override returns (uint128 costOfsendPacketInNativeToken) {
        // If timeoutTimestamp is set to 0, set it to maximum.
        uint64 timeoutTimestamp = deadline > 0 ? deadline : type(uint64).max;

        dispatcher.sendPacket(
            destinationChainIdentifier,
            bytes.concat(ADDRESS_THIS, message),
            timeoutTimestamp
        );
        return 0;
    }
}
