// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICrossChainReceiver {
    /**
     * @notice Handles the acknowledgement from the destination
     * @dev acknowledgement is exactly the output of receiveMessage except if receiveMessage failed, then it is error code (0xff or 0xfe) + original message.
     * If an acknowledgement isn't needed, this can be implemented as {}.
     * - This function can be called by someone else again! Ensure that if this endpoint is called twice with the same message nothing bad happens.
     * - If the application expects that the maxGasAck will be provided, then it should check that it got enough and revert if it didn't.
     * Otherwise, it is assumed that you didn't need the extra gas.
     * @param destinationIdentifier An identifier for the destination chain.
     * @param messageIdentifier A unique identifier for the message. The identifier matches the identifier returned when escrowed the message.
     * This identifier can be mismanaged by the messaging protocol.
     * @param acknowledgement The acknowledgement sent back by receiveMessage. Is 0xff if receiveMessage reverted.
     */
    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) external;

    /**
     * @notice receiveMessage from a cross-chain call.
     * @dev The application needs to check the fromApplication combined with sourceIdentifierbytes to figure out if the call is authenticated.
     * - If the application expects that the maxGasDelivery will be provided, then it should check that it got enough and revert if it didn't.
     * Otherwise, it is assumed that you didn't need the extra gas.
     * @return acknowledgement Information which is passed to receiveAck. 
     *  If you return 0xff, you cannot know the difference between Executed but "failed" and outright failed.
     */
    function receiveMessage(bytes32 sourceIdentifierbytes, bytes32 messageIdentifier, bytes calldata fromApplication, bytes calldata message) external returns(bytes memory acknowledgement);
}