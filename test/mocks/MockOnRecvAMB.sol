// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Mock On Recv AMB implementation
 */
contract MockOnRecvAMB {

    event Message(
        bytes32 destinationIdentifier,
        bytes recipient,
        bytes message
    );

    function sendPacket(
        bytes32 destinationIdentifier,
        bytes calldata recipient,
        bytes calldata message
    ) external {
        emit Message(
            destinationIdentifier,
            recipient,
            message
        );
    }
}


