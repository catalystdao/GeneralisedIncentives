// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IMETimeoutExtension } from "../../TimeoutExtension.sol";
import { MockOnRecvAMB } from "../../../test/mocks/MockOnRecvAMB.sol";

import { IbcReceiver } from "./interfaces/IbcReceiver.sol";
import { IbcDispatcher } from "./interfaces/IbcDispatcher.sol";
import { IbcPacket, AckPacket, PacketFee, ChannelOrder } from "./interfaces/Ibc.sol";

// This is an example contract which exposes an onReceive interface. This is for messaging protocols
// where messages are delivered directly to the messaging protocol's contract rather than this contract.
// Comments marked by * imply that an integration point should be changed by external contracts.
contract IncentivizedPolymerEscrow is IMETimeoutExtension, IbcReceiver {
    error NotEnoughGasProvidedForVerification();
    error NonVerifiableMessage();
    error NotImplemented();

    // Internal function for gas savings.
    function _UNIQUE_SOURCE_IDENTIFIER() view internal returns(bytes32) {
        return bytes32(block.chainid);

    }

    // Expose internal function.
    function UNIQUE_SOURCE_IDENTIFIER() view external returns(bytes32) {
        return _UNIQUE_SOURCE_IDENTIFIER();
    }

    IbcDispatcher immutable public IBC_DISPATCHER;

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;


    constructor(address sendLostGasTo, address messagingProtocol) IMETimeoutExtension(sendLostGasTo) {
        IBC_DISPATCHER = IbcDispatcher(messagingProtocol);
    }

    // Verify that the sender is correct.
    modifier onlyMessagingProtocol() {
        require(msg.sender == address(IBC_DISPATCHER));
        _;
    }

    function estimateAdditionalCost() external pure returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = 0;
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes32(block.number),
                _UNIQUE_SOURCE_IDENTIFIER(), 
                destinationIdentifier,
                message
            )
        );
    }

    function _verifyPacket(bytes calldata /* _metadata */, bytes calldata _message) internal view override returns (bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        sourceIdentifier = isVerifiedMessageHash[keccak256(_message)].chainIdentifier;
        implementationIdentifier = isVerifiedMessageHash[keccak256(_message)].implementationIdentifier;
        
        if (sourceIdentifier == bytes32(0)) revert NonVerifiableMessage();

        message_ = _message;
    }


    /// @dev This is an example of how this function can be disabled.
    /// This doesn't have to be how it is done. This implementation works
    /// fine with and without (There is even a test for that).
    function processPacket(
        bytes calldata /* messagingProtocolContext */,
        bytes calldata /* rawMessage */,
        bytes32 /* feeRecipitent */
    ) external override payable {
        revert NotImplemented();
    }

    function onRecvPacket(
        IbcPacket calldata packet
    ) onlyMessagingProtocol external returns(AckPacket memory) {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes32 chainIdentifier = packet.src.channelId;
        bytes memory sourceImplementationIdentifier = abi.encodePacked(packet.src.portId);

        bytes memory receiveAck = _handleMessage(
            chainIdentifier,
            sourceImplementationIdentifier,
            packet.data,
            feeRecipitent,
            gasLimit
        );

        // Send ack:
        return AckPacket({
            success: true,
            data: receiveAck
        });
    }

    // The escrow manages acks, so any message can be directly provided to _onReceive.
    function onAcknowledgementPacket(
        IbcPacket calldata packet,
        AckPacket calldata ack
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = ack.data;
        bytes32 chainIdentifier = packet.dest.channelId;
        bytes memory destinationImplementationIdentifier = abi.encodePacked(packet.dest.portId);

        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: chainIdentifier,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(
            chainIdentifier,
            destinationImplementationIdentifier,
            rawMessage,
            feeRecipitent,
            gasLimit
        );
    }

    // For timeouts, we need to construct the message.
    function onTimeoutPacket(
        IbcPacket calldata packet
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = packet.data;
        bytes32 chainIdentifier = packet.dest.channelId;

        _handleTimeout(chainIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // * Send to messaging_protocol 
    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory /* destinationImplementation */, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        // TODO: destinationImplementation. How to choose channels?
        IBC_DISPATCHER.sendPacket(
            destinationChainIdentifier,
            abi.encodePacked(
                message
            ),
            0,
            PacketFee(0,0,0)
        );
        return 0;
    }

    //
    // Channel handshake methods
    //

    function onOpenIbcChannel(
        string calldata version,
        ChannelOrder ordering,
        bool feeEnabled,
        string[] calldata connectionHops,
        string calldata counterpartyPortId,
        bytes32 counterpartyChannelId,
        string calldata counterpartyVersion
    ) external returns (string memory selectedVersion) {
        // TODO
    }

    function onConnectIbcChannel(
        bytes32 channelId,
        bytes32 counterpartyChannelId,
        string calldata counterpartyVersion
    ) external {
        // TODO
    }

    function onCloseIbcChannel(
        bytes32 channelId,
        string calldata counterpartyPortId,
        bytes32 counterpartyChannelId
    ) external {
        // TODO
    }
}