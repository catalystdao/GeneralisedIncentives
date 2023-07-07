// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { IApplication } from "./interfaces/IApplication.sol";
import { SourcetoDestination, DestinationtoSource } from "./MessagePayload.sol";
import "./MessagePayload.sol";


abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow {
    error NotEnoughGasProvided(uint256 expected, uint256 actual);
    error InvalidTotalIncentive(uint256 expected, uint256 actual);
    error ZeroIncentiveNotAllowed();
    error MessageAlreadyBountied();
    error NotImplementedError();
    error feeRecipitentIncorrectFormatted(uint8 expected, uint8 actual);

    bytes constant ALT_DEPLOYMENT = bytes("0x12341234");

    mapping(bytes32 => incentiveDescription) public bounty;


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
            convertEVMTo65(msg.sender),     // Original sender
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
    function processMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata message, bytes calldata feeRecipitent) external {
        uint256 gasLimit = gasleft();
        // Verify message is valid
        _verifyMessage(sourceIdentifier, messagingProtocolContext, message);

        bytes1 context = bytes1(message[0]);

        if (context == SourcetoDestination) {
            _handleCall(sourceIdentifier, message, feeRecipitent, gasLimit);
        } else if (context == DestinationtoSource) {
            _handleAck(sourceIdentifier, message, feeRecipitent, gasLimit);
        } else {
            revert NotImplementedError();
        }
    }

    function _handleCall(bytes32 sourceIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint256 gasLimit) internal {
        
        // We do not check if toApplication is formatted correctly: check if TO_APPLICATION_LENGTH_POS == 20? because this function is not allowed to fail.
        address toApplication = address(bytes20(message[CTX0_TO_APPLICATION_START_EVM:CTX0_TO_APPLICATION_END]));
        bytes calldata fromApplication = message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END];
        // Deliver the message to the application.
        bytes memory acknowledgement = IApplication(toApplication).receiveMessage(sourceIdentifier, fromApplication, message[CTX0_MESSAGE_START: ]);  // TODO: try - catch

        // It is assumed that the length of the address of the feeRecipitent is the same as the fromApplication. Check that feeRecipitent is formatted correctly. //TODO Assumption?
        if (feeRecipitent[0] != fromApplication[0]) revert feeRecipitentIncorrectFormatted(uint8(fromApplication[0]), uint8(feeRecipitent[0]));

        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint256 gasUsed = uint128(gasLimit - gasleft());

        // Encode a new message to send back. This lets the relayer claim their payment.
        bytes memory messageWithContext = abi.encodePacked(
            bytes1(DestinationtoSource), // This is a sendMessage
            feeRecipitent,
            gasUsed,
            acknowledgement
        );

        // Send message to messaging protocol
        _sendMessage(sourceIdentifier, _getEscrowAddress(sourceIdentifier), messageWithContext);
    }

    function _handleAck(bytes32 sourceIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint256 gasLimit) internal {

        // Handle the payment to the user
        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
        IApplication(fromApplication).ackMessage(sourceIdentifier, message[CTX1_MESSAGE_START: ]);  // TODO: try - catch

        // release payment
        address destinationFeeRecipitent = address(bytes20(message[CTX1_RELAYER_RECIPITENT_START_EVM:CTX1_RELAYER_RECIPITENT_END]));
        address sourceFeeRecipitent = address(bytes20(feeRecipitent[45:]));
        uint128 gasSpentOnDestination = uint128(bytes16(message[CTX1_GAS_SPENT_START:CTX1_GAS_SPENT_END]));

        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint256 gasUsed = uint128(gasLimit - gasleft());

        // Payment for relaying message
        destinationFee

    }
}
