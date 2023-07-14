// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "./interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "./interfaces/ICrossChainReceiver.sol";
import { SourcetoDestination, DestinationtoSource } from "./MessagePayload.sol";
import { Bytes65 } from "./utils/Bytes65.sol";
import "./MessagePayload.sol";

/**
 * @title Generalised Incentive Escrow
 * @author Alexander @ Catalyst
 * @notice Places transparent incentives on relaying messages.
 * The incentive is released when an ack from a matching implementation on the destination chain
 * is delivered to this contract.
 *
 * The incentive scheme is designed to overload the existing incentive scheme for messaging protocols
 * and streamline intergration by standardizing the interface and the relaying payment.
 *
 * Several quality of life features are implemented like:
 * - Refunds of unused gas.
 * - Seperate gas payments for initial call and ack.
 * - Simple implementation of new messaging protocols.
 */
abstract contract IncentivizedMessageEscrow is IIncentivizedMessageEscrow, Bytes65 {

    bytes1 constant SWAP_REVERTED = 0xff;

    address constant SEND_LOST_GAS_TO = address(0);

    mapping(bytes32 => IncentiveDescription) public _bounty;

    mapping(bytes32 => bool) public _spentMessageIdentifier;

    /// @notice Verify a message's authenticity.
    /// @dev Should be overwritten by the specific messaging protocol verification structure.
    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata rawMessage) virtual internal returns(bytes calldata message);

    /// @notice Send the message to the messaging protocol.
    /// @dev Should be overwritten to send a message using the specific messaging protocol.
    function _sendMessage(bytes32 destinationIdentifier, bytes memory message) virtual internal;

    /// @notice Generates a unique message identifier for a message
    /// @dev Should be overwritten. The identifier should:
    ///  - Be unique over time
    ///     Use blocknumber or blockhash
    ///  - Be unique on destination chain
    ///     Use a unique source identifier 
    ///  - Be unique on the source chain
    ///     Use a unique destinationIdentifier
    ///  - Depend on the message
    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) view internal virtual returns(bytes32);

    /// Getters:
    function bounty(bytes32 messageIdentifier) external view returns(IncentiveDescription memory incentive) {
        return _bounty[messageIdentifier];
    }

   function spentMessageIdentifier(bytes32 messageIdentifier) external view returns(bool hasMessageBeenExecuted) {
        return _spentMessageIdentifier[messageIdentifier];
   }

    /**
     * @notice Increases the bounty for relaying messages
     * @dev It is not possible to increase the gas budget for a message. 
     */
    function increaseBounty(
        bytes32 messageIdentifier,
        uint96 deliveryGasPriceIncrease,
        uint96 ackGasPriceIncrease
    ) external payable {
        if (_bounty[messageIdentifier].refundGasTo == address(0)) revert MessageDoesNotExist();
        // Find incentive scheme.
        IncentiveDescription storage incentive = _bounty[messageIdentifier];

        // Compute incentive metrics.
        uint128 deliveryGas = incentive.maxGasDelivery * deliveryGasPriceIncrease;
        uint128 ackGas = incentive.maxGasAck * ackGasPriceIncrease;
        uint128 sum = deliveryGas + ackGas;
        // Check that the provided gas is exact
        if (msg.value != sum) revert NotEnoughGasProvided(sum, uint128(msg.value));

        // Update storage.
        incentive.priceOfDeliveryGas += deliveryGasPriceIncrease;
        incentive.priceOfAckGas += ackGasPriceIncrease;

        // Emit the event with the increased values.
        emit BountyIncreased(
            messageIdentifier,
            deliveryGasPriceIncrease,
            ackGasPriceIncrease
        );
    }

   function _setBounty(
        bytes32 messageIdentifier, 
        IncentiveDescription calldata incentive
    ) internal returns(uint128 sum){
        if (_bounty[messageIdentifier].refundGasTo != address(0)) revert MessageAlreadyBountied();
        // Compute incentive metrics.
        uint128 deliveryGas = incentive.maxGasDelivery * incentive.priceOfDeliveryGas;
        uint128 ackGas = incentive.maxGasAck * incentive.priceOfAckGas;
        sum = deliveryGas + ackGas;
        // Check that the provided gas is sufficient. The refund will be sent later. (reentry? concern).
        if (sum == 0) revert ZeroIncentiveNotAllowed();
        if (msg.value < sum) revert NotEnoughGasProvided(sum, uint128(msg.value));
        
        _bounty[messageIdentifier] = incentive;
    }


    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by other contracts
    /// Any integrating application should check:
    ///     1. That incentive.maxGasAck is sufficient! Otherwise, an off-chain agent needs to re-submit the ack.
    ///     2. That incentive.maxGasDelivery is sufficient. Otherwise, the call will fail within the try - catch.
    ///     3. The relay incentive is enough to get the message relayed within the expected time. If that is never, then this check is not needed.
    /// @param message The message to be sent to the destination. Please ensure the message is semi-unique.
    ///     This can safely be done by appending a counter to the message or adding a number of pesudo-randomized
    ///     bytes like the blockhash. (or difficulty)
    /// @return gasRefund The amount of excess gas which was paid to this call. The app should handle the excess.
    /// @return messageIdentifier An unique identifier for a message.
    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IncentiveDescription calldata incentive
    ) checkBytes64Address(destinationAddress) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        // Prepare to store incentive
        messageIdentifier = _getMessageIdentifier(
            destinationIdentifier,
            message
        );
        uint128 sum = _setBounty(messageIdentifier, incentive);

        bytes memory messageWithContext = abi.encodePacked(
            bytes1(SourcetoDestination),    // This is a sendMessage,
            messageIdentifier,              // An unique identifier to recover identifier to recover 
            convertEVMTo65(msg.sender),     // Original sender
            destinationAddress,             // The address to deliver the (original) message to.
            incentive.maxGasDelivery,       // Send the gas limit to the other chain so we can enforce it
            message                         // The message to deliver to the destination.
        );

        // Send message to messaging protocol
        _sendMessage(
            destinationIdentifier,
            messageWithContext
        );

        emit BountyPlaced(
            messageIdentifier,
            incentive
        );

        // Return excess incentives
        if (msg.value > sum) {
            payable(msg.sender).transfer(msg.value - sum);
            gasRefund = msg.value - sum;
            return (gasRefund, messageIdentifier);
        }
        return (0, messageIdentifier);
    }

    /// @notice Set a bounty on a message and transfer the message to the messaging protocol.
    /// @dev Called by off-chain agents.
    function processMessage(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage,
        bytes calldata feeRecipitent
    ) checkBytes64Address(feeRecipitent) external {
        uint128 gasLimit = uint128(gasleft());  // 2**128-1 is plenty gas. If this overflows (and then becomes almost 0, then the relayer provided too much gas)

        // Verify that the message is authentic and remove potential context that the messaging protocol added to the message.
        bytes calldata message = _verifyMessage(chainIdentifier, messagingProtocolContext, rawMessage);

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
        bool messageState = _spentMessageIdentifier[messageIdentifier];
        if (messageState) revert MessageAlreadySpent();
        _spentMessageIdentifier[messageIdentifier] = true;


        // Deliver message to application
            // Decode gas limit, application address and sending application
        uint64 minGas = uint64(bytes8(message[CTX0_MIN_GAS_LIMIT_START:CTX0_MIN_GAS_LIMIT_END]));
        address toApplication = address(bytes20(message[CTX0_TO_APPLICATION_START_EVM:CTX0_TO_APPLICATION_END])); 
        bytes calldata fromApplication = message[FROM_APPLICATION_LENGTH_POS:FROM_APPLICATION_END];
            // Execute call to application. Gas limit is set explicitly to ensure enough gas has been sent.
        bytes memory acknowledgement;
        // TODO: If the caller doesn't implement receiveMessage, catch.
        try ICrossChainReceiver(toApplication).receiveMessage{gas: minGas}(sourceIdentifier, fromApplication, message[CTX0_MESSAGE_START: ]) returns(bytes memory returnValue) 
            {acknowledgement = returnValue;} catch {acknowledgement = abi.encodePacked(SWAP_REVERTED);}


        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint48 gasUsed = uint48(gasLimit - gasleft());


        // Encode a new message to send back. This lets the relayer claim their payment.
        bytes memory ackMessageWithContext = abi.encodePacked(
            bytes1(DestinationtoSource),                                        // This is a sendMessage
            messageIdentifier,  // message identifier
            fromApplication,
            feeRecipitent,
            gasUsed,
            uint64(block.timestamp),        // If this overflows, it is fine. It is used in conjunction with a delta.
            acknowledgement
        );

        // Send message to messaging protocol
        _sendMessage(sourceIdentifier, ackMessageWithContext);

        emit MessageDelivered(messageIdentifier);
    }

    function _handleAck(bytes32 destinationIdentifier, bytes calldata message, bytes calldata feeRecipitent, uint128 gasLimit) internal {
        bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
        IncentiveDescription memory incentive = _bounty[messageIdentifier];
        delete _bounty[messageIdentifier];  // The bounty cannot be accessed anymore.

        // Deliver the ack to the application
        address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
        try ICrossChainReceiver(fromApplication).ackMessage{gas: incentive.maxGasAck}(destinationIdentifier, message[CTX1_MESSAGE_START: ]) {} catch {}

        // Get the gas used by these calls:
        uint256 gasSpentOnDestination = uint48(bytes6(message[CTX1_GAS_SPENT_START:CTX1_GAS_SPENT_END]));
        if (incentive.maxGasDelivery < gasSpentOnDestination) gasSpentOnDestination = incentive.maxGasDelivery;  // If more gas was spent then allocated, then only return the allocation.
        // Delay the gas limit computation until as late as possible. This should include the majority of gas spent.
        uint256 gasSpentOnSource = gasLimit - gasleft();
        if (incentive.maxGasAck < gasSpentOnSource) gasSpentOnSource = incentive.maxGasAck;  // If more gas was spent then allocated, then only return the allocation.

        // Find the respective fees for delivery and ack.
        uint256 deliveryFee; uint256 ackFee; uint256 sumFee; uint256 refund;
        unchecked {
            // gasSpentOnDestination < maxGasDelivery => We have done this calculation before.
            deliveryFee = gasSpentOnDestination * incentive.priceOfDeliveryGas;
            // gasSpentOnSource < maxGasAck => We have done this calculation before.
            ackFee = gasSpentOnSource * incentive.priceOfAckGas;
            // deliveryFee + ackFee have been calculated before.
            sumFee = deliveryFee + ackFee;
            // (incentive.priceOfDeliveryGas * incentive.maxGasDelivery + incentive.priceOfDeliveryGas * incentive.maxGasAck) has been caculated before. (see above). then sumFee must be weakly less.
            uint256 maxDeliveryGas = incentive.maxGasDelivery * incentive.priceOfDeliveryGas;
            uint256 maxAckGas = incentive.maxGasAck * incentive.priceOfAckGas;
            uint256 maxSum = maxDeliveryGas + maxAckGas;
            refund = maxSum - sumFee;
        }
        // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
        if(!payable(incentive.refundGasTo).send(refund)) {
            payable(SEND_LOST_GAS_TO).transfer(refund);
        }
        address destinationFeeRecipitent = address(bytes20(message[CTX1_RELAYER_RECIPITENT_START_EVM:CTX1_RELAYER_RECIPITENT_END]));
        address sourceFeeRecipitent = address(bytes20(feeRecipitent[45:]));

        if (destinationFeeRecipitent == sourceFeeRecipitent) {
            payable(sourceFeeRecipitent).transfer(sumFee);
            return;
        }

        uint64 targetDelta = incentive.targetDelta;
        // If targetDelta is 0, then distribute exactly the rewards.
        if (targetDelta == 0) {
            // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
            if(!payable(destinationFeeRecipitent).send(deliveryFee)) {
                payable(SEND_LOST_GAS_TO).transfer(refund);
            }
            payable(sourceFeeRecipitent).transfer(ackFee);
            return;
        }
        // Compute the reward distribution
        // We need to compute how much time it took to deliver the ack back.
        uint64 executionTime;
        unchecked {
            // Underflow is desired in this code chuck. It ensures that the code piece continues working
            // past the time when uint64 stops working. *As long as any timedelta is less than uint64. // TODO: Test
            executionTime = uint64(block.timestamp) - uint64(bytes8(message[CTX1_EXECUTION_TIME_START:CTX1_EXECUTION_TIME_END]));
        }
        // The incentive scheme is as follows: When executionTime = incentive.targetDelta then 
        // The rewards are distributed as per the incentive spec. If the time is less, then
        // more incentives are given to the destination relayer while if the time is more, 
        // then more incentives are given to the sourceRelayer.
        uint256 forDestinationRelayer;
        unchecked {
            // |targetDekta - executionTime| < |2**64 + 2**64| = 2**65 < 2**255 - 1
            int256 timeBetweenTargetAndExecution = int256(uint256(targetDelta)) - int256(uint256(executionTime));
            if (timeBetweenTargetAndExecution <= 0) {
                // Less time than target passed and the destination relayer should get a larger chunk.
                // targetDelta != 0, we checked for that. 
                // max abs timeBetweenTargetAndExecution = targetDelta => ackFee * targetDelta < sumFee * targetDelta
                //  2**127 * 2**64 = 2**191 < 2**256-1
                // Thus the largest this can be is sumFee and that is the sum previously calculated.
                forDestinationRelayer = deliveryFee + ackFee * uint256(- timeBetweenTargetAndExecution) / targetDelta;
            } else {
                // More time than target passed and the ack relayer should get a larger chunk.
                if (uint256(timeBetweenTargetAndExecution) >= targetDelta) {
                    forDestinationRelayer = 0;
                } else {
                    // targetDelta != 0, we checked for that. 
                    // max abs timeBetweenTargetAndExecution = targetDelta since we have the above check
                    // => deliveryFee * targetDelta < sumFee * targetDelta < 2**127 * 2**64 = 2**191 < 2**256-1
                    forDestinationRelayer = deliveryFee - deliveryFee * uint256(timeBetweenTargetAndExecution) / targetDelta;
                }
            }
        }
        // send is used to ensure this doesn't revert. Transfer could revert and block the ack from ever being delivered.
        if(!payable(destinationFeeRecipitent).send(forDestinationRelayer)) {
            payable(SEND_LOST_GAS_TO).transfer(refund);
        }
        uint256 forSourceRelayer = sumFee - forDestinationRelayer;
        payable(sourceFeeRecipitent).transfer(forSourceRelayer);

        emit MessageAcked(messageIdentifier);
        emit BountyClaimed(
            messageIdentifier,
            uint64(gasSpentOnDestination),
            uint64(gasSpentOnSource),
            uint128(forDestinationRelayer),
            uint128(forSourceRelayer)
        );
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
            bytes32 messageIdentifier = bytes32(message[MESSAGE_IDENTIFIER_START:MESSAGE_IDENTIFIER_END]);
            // TODO: Custom Error
            require(_bounty[messageIdentifier].refundGasTo != address(0), "!Hasn't been claimed"); 

            address fromApplication = address(bytes20(message[FROM_APPLICATION_START_EVM:FROM_APPLICATION_END]));
            ICrossChainReceiver(fromApplication).ackMessage(chainIdentifier, message[CTX1_MESSAGE_START: ]);

            emit MessageAcked(messageIdentifier);
        } else {
            revert NotImplementedError();
        }
    }
}
