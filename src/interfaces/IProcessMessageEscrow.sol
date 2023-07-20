// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import { IIncentivizedMessageEscrow } from "./IIncentivizedMessageEscrow.sol";


interface IProcessMessageEscrow is IIncentivizedMessageEscrow {
   /**
     * @notice Deliver a message which has been *signed* by a messaging protocol.
     * @dev This function is intended to be called by off-chain agents.
     *  Please ensure that feeRecipitent can receive gas token: Either it is an EOA or a implement fallback() / receive().
     *  Likewise for any non-evm chains. Otherwise the message fails (ack) or the relay payment is lost (call).
     *  You need to pass in incentive.maxGas(Delivery|Ack) + messaging protocol dependent buffer, otherwise this call might fail.
     * @param messagingProtocolContext Additional context required to verify the message by the messaging protocol.
     * @param rawMessage The raw message as it was emitted.
     * @param feeRecipitent An identifier for the the fee recipitent. The identifier should identify the relayer on the source chain.
     *  For EVM (and this contract as a source), use the bytes32 encoded address. For other VMs you might have to register your address.
     */
    function processMessage(
        bytes32 chainIdentifier,
        bytes calldata messagingProtocolContext,
        bytes calldata rawMessage,
        bytes32 feeRecipitent
    ) virtual external;
}