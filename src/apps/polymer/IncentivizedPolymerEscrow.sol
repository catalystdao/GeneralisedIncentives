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

// This is an example contract which exposes an onReceive interface. This is for messaging protocols
// where messages are delivered directly to the messaging protocol's contract rather than this contract.
// Comments marked by * imply that an integration point should be changed by external contracts.
contract IncentivizedPolymerEscrow is IMETimeoutExtension, IbcMwUser {
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

    /// @dev This is an example of how this function can be disabled.
    /// This doesn't have to be how it is done. This implementation works
    /// fine with and without (There is even a test for that).
    function processPacket(
        bytes calldata, /* messagingProtocolContext */
        bytes calldata, /* rawMessage */
        bytes32 /* feeRecipitent */
    ) external payable override {
        revert NotImplemented();
    }

    // packet.srcPortAddr is the IncentivizedPolymerEscrow address on the source chain.
    // packet.destPortAddr is the address of this contract.
    // channelId: the universal channel id on the source chain, which can be used to identify the source chain.
    function onRecvUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        onlyIbcMw
        returns (AckPacket memory)
    {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes memory sourceImplementationIdentifier = abi.encodePacked(packet.srcPortAddr);

        bytes memory receiveAck = _handleMessage(
            bytes32(abi.encodePacked(packet.srcPortAddr)),
            sourceImplementationIdentifier,
            packet.appData,
            feeRecipitent,
            gasLimit
        );

        // Send ack:
        return AckPacket({success: true, data: receiveAck});
    }

    // The escrow manages acks, so any message can be directly provided to _onReceive.
    function onUniversalAcknowledgement(UniversalPacket calldata packet, AckPacket calldata ack) external onlyIbcMw {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = ack.data;
        // TODO: get dest chain ID?
        bytes32 chainIdentifier;
        bytes memory destinationImplementationIdentifier = abi.encodePacked(packet.destPortAddr);

        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: chainIdentifier,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(chainIdentifier, destinationImplementationIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeoutUniversalPacket(UniversalPacket calldata packet) external onlyIbcMw {
        uint256 gasLimit = gasleft();
        bytes32 feeRecipitent = bytes32(uint256(uint160(tx.origin)));

        bytes calldata rawMessage = packet.appData;
        // TODO: get dest chain ID?
        bytes32 chainIdentifier;

        _handleTimeout(chainIdentifier, rawMessage, feeRecipitent, gasLimit);
    }

    // * Send to messaging_protocol
    function _sendPacket(
        bytes32 destinationChainIdentifier,
        bytes memory, /* destinationImplementation */
        bytes memory message
    ) internal override returns (uint128 costOfsendPacketInNativeToken) {
        // TODO: get Polymer universal channelId from Polymer registry. Each channelID is unique for a pair of chains.
        bytes32 channelId = _getChannelId(destinationChainIdentifier);
        // TODO: get IncentivizedPolymerEscrow address deployed on the destination chain.
        address destEscrowAddr;
        // set timeoutTimestamp to 1 day from now. It's the dest chain's block time in nanoseconds since the epoch.
        uint64 timeoutTimestamp = uint64(block.timestamp + 1 days) * 1e9;
        IbcUniversalPacketSender(mw).sendUniversalPacket(channelId, destEscrowAddr, message, timeoutTimestamp);
        return 0;
    }

    mapping(bytes32 => bytes32) _destChainChannelIds;

    function _getChannelId(bytes32 destChainId) internal view returns (bytes32) {
        // verify destChainId has a valid channelId
        return _destChainChannelIds[destChainId];
    }
}
