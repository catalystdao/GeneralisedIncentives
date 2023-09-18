// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

/**
 * @title Example application contract
 */
contract MockSpendGas is ICrossChainReceiver {
    IIncentivizedMessageEscrow immutable MESSAGE_ESCROW;

    constructor(address messageEscrow_) {
        MESSAGE_ESCROW = IIncentivizedMessageEscrow(messageEscrow_);
    }

    function escrowMessage(
        bytes32 destinationIdentifier,
        bytes calldata destinationAddress,
        bytes calldata message,
        IIncentivizedMessageEscrow.IncentiveDescription calldata incentive
    ) external payable returns(uint256 gasRefund, bytes32 messageIdentifier) {
        (gasRefund, messageIdentifier) = MESSAGE_ESCROW.escrowMessage{value: msg.value}(
            destinationIdentifier,
            destinationAddress,
            message,
            incentive
        );
    }

    function ackMessage(bytes32 destinationIdentifier, bytes32 messageIdentifier, bytes calldata acknowledgement) external view {
        this.receiveMessage(destinationIdentifier, messageIdentifier, abi.encodePacked(bytes1(0x00)), acknowledgement);
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata message) public pure returns(bytes memory acknowledgement) {
        uint16 iterators = uint16(bytes2(message[0:2]));
        bytes memory comp_hash = abi.encodePacked(keccak256(abi.encodePacked(iterators)));
        for (uint i = 0; i < iterators; ++i) {
            comp_hash = abi.encodePacked(keccak256(comp_hash));
        }
        require(abi.decode(comp_hash, (uint256)) > 0, "Zero keccak256 hash found O.o");
        return message;
    }

}
