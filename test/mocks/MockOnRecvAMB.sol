// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";
import { OnRecvIncentivizedMockEscrow } from "../../src/apps/mock/onRecvIncentivizedMockEscrow.sol";


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


