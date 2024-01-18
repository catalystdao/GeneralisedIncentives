// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IMETimeoutExtension } from "../../TimeoutExtension.sol";
import { MockOnRecvAMB } from "../../../test/mocks/MockOnRecvAMB.sol";

// This is an example contract which exposes an onReceive interface. This is for messaging protocols
// where messages are delivered directly to the messaging protocol's contract rather than this contract.
// Comments marked by * imply that an integration point should be changed by external contracts.
contract OnRecvIncentivizedMockEscrow is IMETimeoutExtension {
    error NotEnoughGasProvidedForVerification();
    error NonVerifiableMessage();
    error NotImplemented();
    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;
    address immutable public MESSAGING_PROTOCOL_CALLER;

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;


    constructor(address sendLostGasTo, address messagingProtocol) IMETimeoutExtension(sendLostGasTo) {
        MESSAGING_PROTOCOL_CALLER = messagingProtocol;
        UNIQUE_SOURCE_IDENTIFIER = bytes32(uint256(111));  // Actual implementation should call to messagingProtocol
    }

    // Verify that the sender is correct.
    modifier onlyMessagingProtocol() {
        require(msg.sender == MESSAGING_PROTOCOL_CALLER);
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
                UNIQUE_SOURCE_IDENTIFIER, 
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
        bytes32 /* feeRecipient */
    ) external override payable {
        revert NotImplemented();
    }

    function onReceive(
        bytes32 chainIdentifier,
        bytes calldata sourceImplementationIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) onlyMessagingProtocol external {
        // _onReceive(chainIdentifier, rawMessage, feeRecipient);
        uint256 gasLimit = gasleft();
        bytes memory receiveAck = _handleMessage(chainIdentifier, sourceImplementationIdentifier, rawMessage, feeRecipient, gasLimit);

        // Send ack:
        _sendPacket(chainIdentifier, sourceImplementationIdentifier, receiveAck);
        // * For an actual implementation, the _sendPacket might also be implemented as a return value for onReceive like:
        // * return ReturnStruct?({chainIdentifier: chainIdentifier, message: receiveAck});
    }

    // The escrow manages acks, so any message can be directly provided to _onReceive.
    function onAck(
        bytes32 chainIdentifier,
        bytes calldata destinationImplementationIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        isVerifiedMessageHash[keccak256(rawMessage)] = VerifiedMessageHashContext({
            chainIdentifier: chainIdentifier,
            implementationIdentifier: destinationImplementationIdentifier
        });
        _handleAck(chainIdentifier, destinationImplementationIdentifier, rawMessage, feeRecipient, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeout(
        bytes32 chainIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        _handleTimeout(chainIdentifier, rawMessage, feeRecipient, gasLimit);
    }

    // * Send to messaging_protocol 
    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        MockOnRecvAMB(MESSAGING_PROTOCOL_CALLER).sendPacket(
            destinationChainIdentifier,
            destinationImplementation,
            abi.encodePacked(
                message
            )
        );
        return 0;
    }
}