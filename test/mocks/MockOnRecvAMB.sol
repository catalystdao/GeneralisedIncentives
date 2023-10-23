// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Mock On Recv AMB implementation
 */
contract MockOnRecvAMB {

    event Message(
        bytes32 destinationIdentifier,
        bytes recipitent,
        bytes message
    );

    function sendMessage(
        bytes32 destinationIdentifier,
        bytes calldata recipitent,
        bytes calldata message
    ) external {
        emit Message(
            destinationIdentifier,
            recipitent,
            message
        );
    }
}


