// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IncentivizedMessageEscrow} from "../../IncentivizedMessageEscrow.sol";
import "../../MessagePayload.sol";

/// @notice Scaffolding for Polymer Escrows
abstract contract APolymerEscrow is IncentivizedMessageEscrow {
    error NonVerifiableMessage();
    error NotImplemented();

    struct VerifiedMessageHashContext {
        bytes32 chainIdentifier;
        bytes implementationIdentifier;
    }

    mapping(bytes32 => VerifiedMessageHashContext) public isVerifiedMessageHash;

    constructor(address sendLostGasTo)
        IncentivizedMessageEscrow(sendLostGasTo)
    {}

    function estimateAdditionalCost() external pure returns (address asset, uint256 amount) {
        asset = address(0);
        amount = 0;
    }

    function _uniqueSourceIdentifier() internal view override returns (bytes32 sourceIdentifier) {
        return sourceIdentifier = bytes32(block.chainid);
    }

    function _proofValidPeriod(bytes32 /* destinationIdentifier */ ) internal pure override returns (uint64) {
        return 0;
    }

    /** @dev Disable processPacket */
    function processPacket(
        bytes calldata, /* messagingProtocolContext */
        bytes calldata, /* rawMessage */
        bytes32 /* feeRecipitent */
    ) external payable override {
        revert NotImplemented();
    }

    /** @dev Disable reemitAckMessage. Polymer manages the entire flow, so we don't need to worry about expired proofs. */
    function reemitAckMessage(
        bytes32 /* sourceIdentifier */,
        bytes calldata /* implementationIdentifier */,
        bytes calldata /* receiveAckWithContext */
    ) external payable override {
        revert NotImplemented();
    }

    /** @dev Disable timeoutMessage */
    function timeoutMessage(
        bytes32 /* sourceIdentifier */,
        bytes calldata /* implementationIdentifier */,
        uint256 /* originBlockNumber */,
        bytes calldata /* message */
    ) external payable override {
        revert NotImplemented();
    }

    /// @notice This function is used to allow acks to be executed twice (if the first one ran out of gas)
    /// This is not intended to allow processPacket to work.
    function _verifyPacket(bytes calldata, /* messagingProtocolContext */ bytes calldata _message)
        internal
        view
        override
        returns (bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_)
    {
        sourceIdentifier = isVerifiedMessageHash[keccak256(_message)].chainIdentifier;
        implementationIdentifier = isVerifiedMessageHash[keccak256(_message)].implementationIdentifier;

        if (sourceIdentifier == bytes32(0)) revert NonVerifiableMessage();

        message_ = _message;
    }
}
