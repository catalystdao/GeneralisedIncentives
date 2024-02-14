// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";

import { Ownable2Step } from "openzeppelin/access/Ownable2Step.sol";

// This is a mock contract which should only be used for testing.
contract IncentivizedMockEscrow is IncentivizedMessageEscrow, Ownable2Step {
    error NotEnoughGasProvidedForVerification();
    bytes32 immutable public UNIQUE_SOURCE_IDENTIFIER;
    uint256 public costOfMessages;
    uint256 public accumulator = 1;

    uint64 immutable PROOF_PERIOD;

    event Message(bytes32 destinationIdentifier, bytes recipient, bytes message);

    constructor(address sendLostGasTo, bytes32 uniqueChainIndex, address signer, uint256 costOfMessages_, uint64 proofPeriod) IncentivizedMessageEscrow(sendLostGasTo) {
        UNIQUE_SOURCE_IDENTIFIER = uniqueChainIndex;
        _transferOwnership(signer);
        costOfMessages = costOfMessages_;
        PROOF_PERIOD = proofPeriod;
    }

    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        asset =  address(0);
        amount = costOfMessages;
    }

    function collectPayments() external {
        payable(owner()).transfer(accumulator - 1);
        accumulator = 1;
    }
    
    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal view returns(uint64) {
        return PROOF_PERIOD;
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32 sourceIdentifier) {
        return sourceIdentifier = UNIQUE_SOURCE_IDENTIFIER;
    }

    function _verifyPacket(bytes calldata _metadata, bytes calldata _message) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {

        // Get signature from message payload
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(_metadata, (uint8, bytes32, bytes32));

        // Get signer of message
        address messageSigner = ecrecover(keccak256(_message), v, r, s);

        // Check signer is the same as the stored signer.
        require(messageSigner == owner(), "!signer");

        // Load the identifier for the calling contract.
        implementationIdentifier = _message[0:32];

        // Local "supposedly" this chain identifier.
        bytes32 thisChainIdentifier = bytes32(_message[64:96]);

        // Check that the message is intended for this chain.
        require(thisChainIdentifier == UNIQUE_SOURCE_IDENTIFIER, "!Identifier");

        // Local the identifier for the source chain.
        sourceIdentifier = bytes32(_message[32:64]);

        // Get the application message.
        message_ = _message[96:];
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {
        emit Message(
            destinationChainIdentifier,
            destinationImplementation,
            abi.encodePacked(
                UNIQUE_SOURCE_IDENTIFIER,
                destinationChainIdentifier,
                message
            )
        );
        uint256 verificationCost = costOfMessages;
        if (verificationCost > 0) {
            if (msg.value < verificationCost) revert NotEnoughGasProvidedForVerification();
            accumulator += verificationCost;
        }
        return costOfsendPacketInNativeToken = uint128(verificationCost);
    }
}