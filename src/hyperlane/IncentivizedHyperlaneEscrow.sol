// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IncentivizedMessageEscrow} from "../IncentivizedMessageEscrow.sol";


contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow {


    function _verifyMessage() internal override {

    }

    function _sendMessage(bytes32 destinationIdentifier, bytes32 target, bytes memory message) internal override {

    }
}