// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { IApplication } from "./interfaces/IApplication.sol";
import { SourcetoDestination, DestinationtoSource } from "./MessagePayload.sol";


abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow {
    error NotEnoughGasProvided(uint256 expected, uint256 actual);
    error InvalidTotalIncentive(uint256 expected, uint256 actual);
    error ZeroIncentiveNotAllowed();
    error MessageAlreadyBountied();
    error NotImplementedError();

    mapping(bytes32 => incentiveDescription) public bounty;

    bytes constant ALT_DEPLOYMENT = bytes("0x12341234");

    mapping(bytes32 => bytes) public destinationToAddress;

    /// @notice Gets this address on the destination chain
    /// @dev Can be overwritten if a messaging router uses some other assumption
    function _getEscrowAddress(bytes32 destinationIdentifier) internal virtual returns(bytes memory) {
        // Try to save gas by not accessing storage. If the most significant bit is set to 1, then return itself
        if (uint256(destinationIdentifier) >> 255 == 1) return convertEVMTo65(address(this));
        if (uint256(destinationIdentifier) >> 254 == 1) return ALT_DEPLOYMENT;
        // TODO Check gas usage of vs
        // if ((destinationIdentifier & 2**255) == 1) return SELF;
        // if ((destinationIdentifier & 2**254) == 1) return ALT_DEPLOYMENT;
        return destinationToAddress[destinationIdentifier];
    }

    /// @notice Verify a message's authenticity.
    /// @dev Should be overwritten by the specific messaging protocol verification structure.
    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata message) virtual internal;

    /// @notice Send the message to the messaging protocol.
    /// @dev Should be overwritten to send a message using the specific messaging protocol.
    function _sendMessage(bytes32 destinationIdentifier, bytes memory target, bytes memory message) virtual internal;

    function convertEVMTo65(address evmAddress) public pure returns(bytes memory) {
        return abi.encodePacked(
            uint8(20),                      // Size of address. Is always 20 for EVM
            bytes32(0),                     // First 32 bytes on EVM are 0
            bytes32(uint256(uint160(evmAddress)))             // Then encode the address in bytes32.
        );
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by other contracts
    /// @param message The message to be sent to the destination. Please ensure the message is semi-unique.
    ///     This can safely be done by appending a counter to the message or adding a number of pesudo-randomized
    ///     bytes like the blockhash. (or difficulty)
    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        incentiveDescription calldata incentive
    ) external payable returns(uint256) {
        // Compute incentive metrics.
        uint256 deliveryGas = incentive.minGasDelivery * incentive.priceOfDeliveryGas;
        uint256 ackGas = incentive.minGasAck * incentive.priceOfDeliveryGas;
        uint256 sum = deliveryGas + ackGas;
        // Check that the provided gas is sufficient and refund the rest
        if (msg.value < sum) revert NotEnoughGasProvided(sum, msg.value);
        
        // Verify that the incentive structure is correct.
        if (sum == 0) revert ZeroIncentiveNotAllowed();
        if (incentive.totalIncentive != sum) revert NotEnoughGasProvided(incentive.totalIncentive, sum);

        // Prepare to store incentive
        bytes32 messageIdentifier = keccak256(message);
        if (bounty[messageIdentifier].totalIncentive != 0) revert MessageAlreadyBountied();
        bounty[messageIdentifier] = incentive;

        bytes memory messageWithContext = abi.encodePacked(
            bytes1(SourcetoDestination),    // This is a sendMessage,
            convertEVMTo65(msg.sender),     // Original sender // TODO: let the sender customize this to deliver the ack to another address? That would let us build messageWithContext out of calldata which could be cheaper.
            destinationAddress,             // The address to deliver the (original) message to.
            incentive.minGasDelivery,       // Send the gas limit to the other chain so we can enforce it
            message                         // The message to deliver to the destination.
        );

        // Send message to messaging protocol
        _sendMessage(
            destinationIdentifier,
            _getEscrowAddress(destinationIdentifier),
            messageWithContext
        );

        // Return excess incentives
        if (msg.value > sum) {
            payable(msg.sender).transfer(msg.value - sum);
            return msg.value - sum;
        }
        return 0;
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by off-chain agents.
    function deliverMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata message) external {
        // Verify message is valid
        _verifyMessage(sourceIdentifier, messagingProtocolContext, message);

        bytes1 context = bytes1(message[0]);

        if (context == SourcetoDestination) {
            _handleSTD(sourceIdentifier, message);
        } else if (context == DestinationtoSource) {
            _handleDTS(message);
        } else {
            revert NotImplementedError();
        }
    }

    function _handleSTD(bytes32 sourceIdentifier, bytes calldata message) internal {
        bytes memory messageWithContext = abi.encodePacked(
            bytes1(DestinationtoSource), // This is a sendMessage
            msg.sender,
            message
        );

        // Send message to messaging protocol
        _sendMessage(sourceIdentifier, _getEscrowAddress(sourceIdentifier), messageWithContext);
    }

    function _handleDTS(bytes calldata message) internal {

    }
}
