// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

/**
 * @title Example application contract
 */
contract MockApplication is ICrossChainReceiver {
    
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

    function receiveAck(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) pure external {
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata fromApplication, bytes calldata message) pure external returns(bytes memory acknowledgement) {
        acknowledgement = abi.encodePacked(keccak256(bytes.concat(message, fromApplication)));
        return acknowledgement;
    }

    receive() external payable {}
}
