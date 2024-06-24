// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ICrossChainReceiver } from "../src/interfaces/ICrossChainReceiver.sol";
import { IIncentivizedMessageEscrow } from "../src/interfaces/IIncentivizedMessageEscrow.sol";

/**
 * @title Example application contract
 */
contract SimpleApplication is ICrossChainReceiver {

    event Event(bytes message);
    
    IIncentivizedMessageEscrow immutable MESSAGE_ESCROW;

    constructor(address messageEscrow_) {
        MESSAGE_ESCROW = IIncentivizedMessageEscrow(messageEscrow_);
    }

    function submitMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IIncentivizedMessageEscrow.IncentiveDescription calldata incentive,
        uint64 deadline
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        (gasRefund, messageIdentifier) = MESSAGE_ESCROW.submitMessage{value: msg.value}(
            destinationIdentifier,
            destinationAddress,
            message,
            incentive,
            deadline
        );
    }

    function setRemoteImplementation(bytes32 destinationIdentifier, bytes calldata implementation) external {
        MESSAGE_ESCROW.setRemoteImplementation(destinationIdentifier, implementation);
    } 

    function receiveAck(bytes32 /* destinationIdentifier */, bytes32 /* messageIdentifier */, bytes calldata acknowledgement) external {
        emit Event(acknowledgement);
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata message) external returns(bytes calldata acknowledgement) {
        emit Event(message);
        return message;
    }

    receive() external payable {}
}
