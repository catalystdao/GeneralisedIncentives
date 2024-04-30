// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { MockOnRecvAMB } from "../../../test/mocks/MockOnRecvAMB.sol";
import "../../MessagePayload.sol";

// This is an example contract which exposes an onReceive interface. This is for messaging protocols
// where messages are delivered directly to the messaging protocol's contract rather than this contract.
// Comments marked by * imply that an integration point should be changed by external contracts.
contract OnRecvIncentivizedMockEscrow is IncentivizedMessageEscrow {
    error NonVerifiableMessage();
    error NotImplemented();
    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;
    address immutable public MESSAGING_PROTOCOL_CALLER;

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;


    constructor(address sendLostGasTo, address messagingProtocol) payable IncentivizedMessageEscrow(sendLostGasTo) {
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

    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal pure returns(uint64) {
        return 0;
    }

    function _verifyPacket(bytes calldata /* _metadata */, bytes calldata _message) internal view override returns (bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        VerifiedMessageHashContext storage _verifiedMessageHashContext = isVerifiedMessageHash[keccak256(_message)];
        sourceIdentifier = _verifiedMessageHashContext.chainIdentifier;
        implementationIdentifier = _verifiedMessageHashContext.implementationIdentifier;
        
        if (sourceIdentifier == bytes32(0)) revert NonVerifiableMessage();

        message_ = _message;
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32 sourceIdentifier) {
        return sourceIdentifier = UNIQUE_SOURCE_IDENTIFIER;
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

    // Disable reemit since the AMB manages this flow.
    function reemitAckMessage(
        bytes32 /* sourceIdentifier */,
        bytes calldata /* implementationIdentifier */,
        bytes calldata /* receiveAckWithContext */
    ) external payable override {
        revert NotImplemented();
    }

    // Disable timeout since the AMB manages this flow.
    function timeoutMessage(
        bytes32 /* sourceIdentifier */,
        bytes calldata /* implementationIdentifier */,
        uint256 /* originBlockNumber */,
        bytes calldata /* message */
    ) external payable override {
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
        _sendPacket(chainIdentifier, sourceImplementationIdentifier, receiveAck, 0);
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
        VerifiedMessageHashContext storage _verfiedMessageHashContext = isVerifiedMessageHash[keccak256(rawMessage)];
        _verfiedMessageHashContext.chainIdentifier = chainIdentifier;
        _verfiedMessageHashContext.implementationIdentifier = destinationImplementationIdentifier;
        
        _handleAck(chainIdentifier, destinationImplementationIdentifier, rawMessage, feeRecipient, gasLimit);
    }

    // For timeouts, we need to construct the message.
    function onTimeout(
        bytes32 chainIdentifier,
        bytes calldata rawMessage,
        bytes32 feeRecipient
    ) onlyMessagingProtocol external {
        uint256 gasLimit = gasleft();
        bytes32 messageIdentifier = bytes32(rawMessage[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        address fromApplication = address(uint160(bytes20(rawMessage[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END])));
        _handleTimeout(chainIdentifier, messageIdentifier, fromApplication, rawMessage[CTX0_MESSAGE_START: ], feeRecipient, gasLimit);
    }

    // * Send to messaging_protocol 
    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message, uint64 /* deadline */) internal override returns(uint128 costOfsendPacketInNativeToken) {
        MockOnRecvAMB(MESSAGING_PROTOCOL_CALLER).sendPacket(
            destinationChainIdentifier,
            destinationImplementation,
            bytes.concat(
                message
            )
        );
        return 0;
    }
}