// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IncentivizedMessageEscrow} from "../IncentivizedMessageEscrow.sol";


contract IncentivizedHyperlaneEscrow is IncentivizedMessageEscrow {


    function _verifyMessage(bytes32 sourceIdentifier, bytes calldata messagingProtocolContext, bytes calldata message) internal override {

    }

    function _sendMessage(bytes32 destinationIdentifier, bytes memory target, bytes memory message) internal override {

    }
}