// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.13;

import { ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "LayerZero-v2/protocol/contracts/messagelib/libs/PacketV1Codec.sol";

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { UlnConfig } from "./interfaces/IUlnBase.sol";
import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

/**
 * @notice LayerZero escrow.
 */
contract IncentivizedLayerZeroEscrow is IncentivizedMessageEscrow {
    using PacketV1Codec for bytes;

    error LayerZeroCannotBeAddress0();
    error IncorrectDestination(address actual);

    // Errors inherited from LZ.
    error LZ_ULN_Verifying();
    error LZ_ULN_InvalidPacketHeader();
    error LZ_ULN_InvalidPacketVersion();
    error LZ_ULN_InvalidEid();

    // Layer Zero associated addresses
    ILayerZeroEndpointV2 immutable ENDPOINT;
    IReceiveUlnBase immutable ULTRA_LIGHT_NODE;

    // chainid is immutable on LayerZero endpoint, so we read it and store it likewise.
    uint32 public immutable chainId;

    /// @notice Only allow LZ to send 
    uint8 allowExternalCall = 1;


    constructor(address sendLostGasTo, address lzEndpointV2, address ULN) IncentivizedMessageEscrow(sendLostGasTo) {
        if (lzEndpointV2 == address(0)) revert LayerZeroCannotBeAddress0();
        ENDPOINT = ILayerZeroEndpointV2(lzEndpointV2);
        chainId  = ENDPOINT.eid();
        ULTRA_LIGHT_NODE = IReceiveUlnBase(ULN);

        // uint256 srcEID = 0;
        // ENDPOINT.setReceiveLibrary(address(this), srcEID, address(this), 0);
    }

    // function allowInitializePath(Origin calldata /* _origin */) external pure returns(bool) {
    //     return false;
    // }

    // INTERNAL: We might have to update this ABI to take into consideration where the message is going
    /**
     * TODO: Can we set ourself as the executor?
     * We want to do this because the executor is also paid for when we send the message
     * However, this incentive scheme is designed to act as its own incentive model and as such
     * we don't need to paid for another set for relayers. So: Can we set ourself as the exector
     * and will the DVNs continue to be paid and deliver their "proofs/commit" to the destination chain
     * for us to use when calling verifiable?
     */
    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(0)), // INTERNAL: figure out a replacement.
            receiver: bytes32(0), // INTERNAL: figure out a replacement.
            message: hex"",
            options: hex"",
            payInLzToken: false
        });
        MessagingFee memory fee = ENDPOINT.quote(params, address(this));
        amount = fee.nativeFee;
        asset =  address(0);
    }

    function _getMessageIdentifier(
        bytes32 destinationIdentifier,
        bytes calldata message
    ) internal override view returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                msg.sender,
                bytes32(block.number),
                chainId, 
                destinationIdentifier,
                message
            )   
        );
    }

    function _verifyPacket(bytes calldata _packetHeader, bytes calldata _packet) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        _assertHeader(_packetHeader);

        // Check that we are the receiver
        address receiver = _packetHeader.receiverB20();
        if(receiver != address(this)) revert IncorrectDestination(receiver);

        // Get the source chain.
        uint32 srcEid = _packetHeader.srcEid();

        bytes32 _headerHash = keccak256(_packetHeader);
        bytes32 _payloadHash = _packet.payloadHash();
        UlnConfig memory _config = ULTRA_LIGHT_NODE.getUlnConfig(address(this), srcEid);

        
        // TODO: Is calling `verifiable` okay or do we need to call `commitVerification`?
        // 1. `commitVerification` has a lot of side effects compared to just calling `verifyable`.
        // most significantly, it also changes a zero storage slot to non-zero thus is `kind of` expensive.
        // Is the deletion of commits worth it gas wise?
        //
        // 2. Can we block `commitVerification` from being called? verifiable stop returning true whenever
        // `commitVerification` is called. From a quick look at the contracts, there are 2 ways to block the call.
        //    2.1: `isValidReceiveLibrary`. That function can be made to call another contract, which could be this one
        //    We can then force the function to fail making `commitVerification` fail and make sure it can never be called.
        //    2.2: `_initializable` is called which eventually makes a call to ILayerZeroReceiver(_receiver).allowInitializePath(_origin);
        //    We can easily expose allowInitializePath and return false. Thus blocking that call. Is it doable?
        //
        // 3. In case everything breaks, should we also check against the "verified" proof on the endpoint?
        // That will be set after someone calls `commitVerification` and it doesn't revert.
        if (!ULTRA_LIGHT_NODE.verifiable(_config, _headerHash, _payloadHash)) revert LZ_ULN_Verifying();

        // Get the source chain
        sourceIdentifier = bytes32(uint256(srcEid));
        // Get the sender
        implementationIdentifier = abi.encode(_packetHeader.sender());
        // Get the message
        message_ = _packet.message();
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message) internal override returns(uint128 costOfsendPacketInNativeToken) {

        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(destinationChainIdentifier)),
            receiver: bytes32(destinationImplementation),
            message: message,
            options: hex"",
            payInLzToken: false
        });

        // Handoff package to LZ.
        // We are getting a refund on any excess value we sent. We can get the natice fee by subtracting it from
        // the value we sent.
        allowExternalCall = 2;
        MessagingReceipt memory receipt = ENDPOINT.send{value: msg.value}(
            params,
            address(this)
        );
        allowExternalCall = 1;
        // Set the cost of the sendPacket to msg.value 
        costOfsendPacketInNativeToken = uint128(msg.value - receipt.fee.nativeFee);

        return costOfsendPacketInNativeToken;
    }

    // Allow LZ refunds to come in while disallowing randoms from sending to this contract.
    // It won't stop abuses but it is the best we can do.
    receive() external payable {
        // allowExternalCall is hot so it shouldn't be that expensive to read.
        require(allowExternalCall != 1, "Do not send ether to this address");
    }


    function _assertHeader(bytes calldata _packetHeader) internal view {
        // assert packet header is of right size 81
        if (_packetHeader.length != 81) revert LZ_ULN_InvalidPacketHeader();
        // assert packet header version is the same as ULN
        if (_packetHeader.version() != PacketV1Codec.PACKET_VERSION) revert LZ_ULN_InvalidPacketVersion();
        // assert the packet is for this endpoint
        if (_packetHeader.dstEid() != chainId) revert LZ_ULN_InvalidEid();
    }
}