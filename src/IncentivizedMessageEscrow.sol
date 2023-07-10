// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { IApplication } from "./interfaces/IApplication.sol";
import { SourcetoDestination, DestinationtoSource } from "./MessagePayload.sol";
import "./MessagePayload.sol";


abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow {
    error NotEnoughGasProvided(uint128 expected, uint128 actual);
    error InvalidTotalIncentive(uint128 expected, uint128 actual);
    error ZeroIncentiveNotAllowed();
    error MessageAlreadyBountied();
    error NotImplementedError();
    error feeRecipitentIncorrectFormatted(uint8 expected, uint8 actual);
    error InvalidBytes65Address();
    error MessageAlreadySpent();

    bytes constant ALT_DEPLOYMENT = bytes("0x12341234");

    mapping(bytes32 => incentiveDescription) public bounty;

    mapping(bytes32 => bytes) public destinationToAddress;
    mapping(bytes32 => bool) public spentMessageIdentifier;

    function _checkBytes65(bytes calldata supposedlyBytes65) internal pure returns(bool) {
        return supposedlyBytes65.length == 65;
    }

    modifier checkBytes64Address(bytes calldata supposedlyBytes65) {
        if (!_checkBytes65(supposedlyBytes65)) revert InvalidBytes65Address();
        _;
    }

    /// @notice Gets this address on the destination chain
    /// @dev Can be overwritten if a messaging router uses some other assumption
    function _getEscrowAddress(bytes32 destinationIdentifier) internal virtual returns(bytes memory) {
        // Try to save gas by not accessing storage. If the most significant bit is set to 1, then return itself
        if (uint256(destinationIdentifier) >> 255 == 1) return convertEVMTo65(address(this));
        if (uint256(destinationIdentifier) >> 254 == 1) return ALT_DEPLOYMENT;
        // TODO Check gas usage of vs
        // if ((destinationIdentifier & 2**255) == 1) return convertEVMTo65(address(this));;
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
            uint8(20),                              // Size of address. Is always 20 for EVM
            bytes32(0),                             // First 32 bytes on EVM are 0
            bytes32(uint256(uint160(evmAddress)))   // Encode the address in bytes32.
        );
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by other contracts
    /// @param message The message to be sent to the destination. Please ensure the message is semi-unique.
    ///     This can safely be done by appending a counter to the message or adding a number of pesudo-randomized
    ///     bytes like the blockhash. (or difficulty)
    /// @return gasRefund The amount of excess gas which was paid to this call. The app should handle the excess.
    /// @return messageIdentifier An unique identifier for a message.
    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        incentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        // Compute incentive metrics.
        uint128 deliveryGas = incentive.minGasDelivery * incentive.priceOfDeliveryGas;
        uint128 ackGas = incentive.minGasAck * incentive.priceOfDeliveryGas;
        uint128 sum = deliveryGas + ackGas;
        // Check that the provided gas is sufficient and refund the rest
        if (msg.value < sum) revert NotEnoughGasProvided(sum, uint128(msg.value));
        
        // Verify that the incentive structure is correct.
        if (sum == 0) revert ZeroIncentiveNotAllowed();
        if (incentive.totalIncentive != sum) revert NotEnoughGasProvided(incentive.totalIncentive, sum);

        // Prepare to store incentive
        messageIdentifier = keccak256(bytes.concat(bytes32(block.number), message));
        if (bounty[messageIdentifier].totalIncentive != 0) revert MessageAlreadyBountied();
        bounty[messageIdentifier] = incentive;

        bytes memory messageWithContext = abi.encodePacked(
            bytes1(SourcetoDestination),    // This is a sendMessage,
            messageIdentifier,              // An semi-unique identifier to recover identifier to recover 
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
            gasRefund = msg.value - sum;
            // return [gasRefund, messageIdentifier]
        }
        gasRefund = 0;
        // return [gasRefund, messageIdentifier]
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by off-chain agents.
    function processMessage(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata message,
        bytes calldata feeRecipitent
    ) checkBytes64Address(feeRecipitent) external {
        uint128 gasLimit = uint128(gasleft());  // 2**128-1 is plenty gas. If this overflows (and then becomes almost 0, then the relayer provided too much gas)

        // Verify that the message is authentic.
        _verifyMessage(chainIdentifier, messagingProtocolContext, message);

        bytes1 context = bytes1(message[0]);
        if (context == SourcetoDestination) {
            _handleCall(chainIdentifier, message, feeRecipitent, gasLimit);
        } else if (context == DestinationtoSource) {
            _handleAck(chainIdentifier, message, feeRecipitent, gasLimit);
        } else {
            revert NotImplementedError();
        }
    }

    function _handleCall(bytes32 sourceIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint128 gasLimit) internal {
        // Ensure message is unique and can only be execyted once
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        bool messageState = spentMessageIdentifier[messageIdentifier];
        if (messageState) revert MessageAlreadySpent();
        spentMessageIdentifier[messageIdentifier] = true;


        // Deliver message to application
            // Decode gas limit, application address and sending application
        uint64 minGas = uint64(bytes8(message[CTX0_MIN_GAS_LIMIT_START:CTX0_MIN_GAS_LIMIT_END]));
        address toApplication = address(bytes20(message[CTX0_TO_APPLICATION_START_EVM:CTX0_TO_APPLICATION_END]));
        bytes calldata fromApplication = message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END];
            // Execute call to application. Gas limit is set explicitly to ensure enough gas has been sent.
        bytes memory acknowledgement;
        try IApplication(toApplication).receiveMessage{gas: minGas}(sourceIdentifier, fromApplication, message[CTX0_MESSAGE_START: ]) returns(bytes memory returnValue) 
            {acknowledgement = returnValue;} catch (bytes memory err) {acknowledgement = new bytes(0x00);}

        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint128 gasUsed = uint128(gasLimit - gasleft());

        // Encode a new message to send back. This lets the relayer claim their payment.
        bytes memory messageWithContext = abi.encodePacked(
            bytes1(DestinationtoSource),                                        // This is a sendMessage
            bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]),  // message identifier
            feeRecipitent,
            gasUsed,
            acknowledgement
        );

        // Send message to messaging protocol
        _sendMessage(sourceIdentifier, _getEscrowAddress(sourceIdentifier), messageWithContext);
    }

    function _handleAck(bytes32 destinationIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint128 gasLimit) internal {
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        incentiveDescription memory incentive = bounty[messageIdentifier];
        delete bounty[messageIdentifier];  // The bounty cannot be accessed anymore.

        // Deliver the ack to the application
        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
        try IApplication(fromApplication).ackMessage{gas: incentive.minGasAck}(destinationIdentifier, message[CTX1_MESSAGE_START: ]) {} catch (bytes memory err) {}

        // Get the gas used by these calls:
        uint128 gasSpentOnDestination = uint128(bytes16(message[CTX1_GAS_SPENT_START:CTX1_GAS_SPENT_END]));
        if (incentive.minGasDelivery < gasSpentOnDestination) gasSpentOnDestination = incentive.minGasDelivery;  // If more gas was spent then allocated, then only return the allocation.
        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint128 gasSpentOnSource = uint128(gasLimit - gasleft());
        if (incentive.minGasAck < gasSpentOnSource) gasSpentOnSource = incentive.minGasAck;  // If more gas was spent then allocated, then only return the allocation.

        // Find the respective fees for delivery and ack.
        uint128 deliveryFee; uint128 ackFee; uint128 sumFee;
        unchecked {
            // gasSpentOnDestination < minGasDelivery => We have done this calculation before.
            deliveryFee = gasSpentOnDestination * incentive.priceOfDeliveryGas;
            // gasSpentOnSource < minGasAck => We have done this calculation before.
            ackFee = gasSpentOnSource * incentive.priceOfAckGas;
            // deliveryFee + ackFee must be less than incentive.totalIncentive
            sumFee = deliveryFee + ackFee;

        }
        address destinationFeeRecipitent = address(bytes20(message[CTX1_RELAYER_RECIPITENT_START_EVM:CTX1_RELAYER_RECIPITENT_END]));
        address sourceFeeRecipitent = address(bytes20(feeRecipitent[45:]));

        if (destinationFeeRecipitent == sourceFeeRecipitent) payable(sourceFeeRecipitent).transfer(sumFee);

        // Otherwise, figure out the decay.
        // TODO: Compute
        uint128 forDestinationRelayer = (sumFee * 5*10**17) / 10**18;
        uint128 forSourceRelayer = sumFee - forDestinationRelayer;
        payable(destinationFeeRecipitent).send(forDestinationRelayer);  // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
        payable(sourceFeeRecipitent).transfer(forSourceRelayer);
    }

    /// @notice Allows anyone to re-execute an ack which didn't properly execute. Out of gas?
    function recoverAck(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata message
    ) external {
        _verifyMessage(chainIdentifier, messagingProtocolContext, message);

        bytes1 context = bytes1(message[0]);
        
        // Only allow acks to do this. Normal messages are invalid after first execution.
        if (context == DestinationtoSource) {
            address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
            IApplication(fromApplication).ackMessage(chainIdentifier, message[CTX1_MESSAGE_START: ]);
        } else {
            revert NotImplementedError();
        }
    }
}
