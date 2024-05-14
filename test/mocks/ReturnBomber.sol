// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

/**
 * @title ReturnBomber
 * This contract tries to return bomb (https://github.com/ethereum/solidity/issues/12306) 
 * the incentive contract when receiveAck is called.
 */
contract ReturnBomber is ICrossChainReceiver {
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

        // emit submitMessage(gasRefund, messageIdentifier);
    }

    function receiveAck(bytes32 /* destinationIdentifier */, bytes32 /* messageIdentifier */, bytes calldata /* acknowledgement */) view external {
        // approximate solution to Cmem for new_mem_size_words
        uint256 rsize = sqrt(gasleft() / 2 * 512);
        assembly {
            return(0x0, mul(rsize, 0x20))
        }
    }

    function sqrt(uint x) private pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata /* message */) pure external returns(bytes memory acknowledgement) {
        require(false);
        return acknowledgement = abi.encode();
    }
}
