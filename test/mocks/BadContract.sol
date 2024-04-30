// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IIncentivizedMessageEscrow } from "../../src/interfaces/IIncentivizedMessageEscrow.sol";
import { ICrossChainReceiver } from "../../src/interfaces/ICrossChainReceiver.sol";

/**
 * @title BadContract
 */
contract BadContract is ICrossChainReceiver {
    function receiveAck(bytes32 /* destinationIdentifier */, bytes32 /* messageIdentifier */, bytes calldata /* acknowledgement */) pure external {
        require(false);
    }

    function receiveMessage(bytes32 /* sourceIdentifierbytes */, bytes32 /* messageIdentifier */, bytes calldata /* fromApplication */, bytes calldata /* message */) pure external returns(bytes memory acknowledgement) {
        require(false);
        return acknowledgement = abi.encode();
    }
}
