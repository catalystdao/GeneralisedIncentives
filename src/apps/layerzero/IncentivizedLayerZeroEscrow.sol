// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.13;

import { ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IMessageLibManager, SetConfigParam } from "LayerZero-v2/protocol/contracts/interfaces/IMessageLibManager.sol";
import { PacketV1Codec } from "LayerZero-v2/protocol/contracts/messagelib/libs/PacketV1Codec.sol";

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { UlnConfig } from "./interfaces/IUlnBase.sol";
import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

/**
 * @notice LayerZero escrow.
 */
contract IncentivizedLayerZeroEscrow is IncentivizedMessageEscrow {
    using PacketV1Codec for bytes;
    uint32 CONFIG_TYPE_EXECUTOR = 1;
    uint32 MAX_MESSAGE_SIZE = 4096;

    struct ConfigTypeExecutor {
        uint32 maxMessageSize;
        address executorAddress;
    }

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


    /**
     * @param sendLostGasTo Address to get gas that could not get sent to the recipitent.
     * @param lzEndpointV2 LayerZero endpount. Is used for sending messages.
     * @param ULN LayerZero Ultra Light Node. Used for verifying messages.
     */
    constructor(address sendLostGasTo, address lzEndpointV2, address ULN) IncentivizedMessageEscrow(sendLostGasTo) {
        if (lzEndpointV2 == address(0) || ULN == address(0)) revert LayerZeroCannotBeAddress0();

        // Load the LZ endpoint. This is the contract we will be sending events to.
        ENDPOINT = ILayerZeroEndpointV2(lzEndpointV2);
        // Set chainId.
        chainId  = ENDPOINT.eid();
        // Set the ultra light node. This is the contract we will be verifying packages against.
        ULTRA_LIGHT_NODE = IReceiveUlnBase(ULN);
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32) {
        return bytes32(uint256(chainId));
    }

    function _proofValidPeriod(bytes32 destinationIdentifier) override internal pure returns(uint64 timestamp) {
        return 0;
    }

    /**
     * @notice Set ourself as executor on all (provided) remote chains. This is required before we anyone
     * can send message out of that chain.
     * @dev sendLibrary is not checked. It is assumed that any endpoint will accept anything as long as it is somewhat sane.
     * @param sendLibrary Contract to set config on.
     * @param remoteEids List of remote Eids to set config on.
     */
    function initConfig(address sendLibrary, uint32[] calldata remoteEids) external {
        unchecked {

        bytes memory configExecutorBytes = abi.encode(ConfigTypeExecutor({
            maxMessageSize: MAX_MESSAGE_SIZE,
            executorAddress: address(this)
        }));

        uint256 numEids = remoteEids.length;
        SetConfigParam[] memory params = new SetConfigParam[](numEids);
        for (uint256 i = 0; i < numEids; ++i) {
            SetConfigParam memory configParam = SetConfigParam({
                eid: remoteEids[i],
                configType: CONFIG_TYPE_EXECUTOR,
                config: configExecutorBytes
            });
            params[i] = configParam;
        }
        ENDPOINT.setConfig(address(this), sendLibrary, params);

        }
    }

    /**
     * @notice Block any calls from the LZ endpoint so that no messages can ever get "verified" on the endpoint.
     * This is very important, as otherwise, the package status can progress on the LZ endpoint which causes
     * `verifiyable` which we rely on to be able to switch from true to false by commiting the proof to the endpoint.
     * While this function is not intended for this use case, it should work.
     */
    function allowInitializePath(Origin calldata /* _origin */) external pure returns(bool) {
        return false;
    }

    // TODO: load interface and correct implement then return 0 regardless of parameters.
    function getFee() external pure returns(uint256 fee) {
        return fee = 0;
    }

    // TODO:: We might have to update this ABI to take into consideration where the message is going
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
            dstEid: uint32(uint256(0)), // TODO:: figure out a replacement.
            receiver: bytes32(0), // TODO:: figure out a replacement.
            message: hex"",
            options: hex"",
            payInLzToken: false
        });
        MessagingFee memory fee = ENDPOINT.quote(params, address(this));
        amount = fee.nativeFee;
        asset =  address(0);
    }

    function _verifyPacket(bytes calldata _packetHeader, bytes calldata _packet) internal view override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        _assertHeader(_packetHeader);

        // Check that we are the receiver
        address receiver = _packetHeader.receiverB20();
        if (receiver != address(this)) revert IncorrectDestination(receiver);

        // Get the source chain.
        uint32 srcEid = _packetHeader.srcEid();

        bytes32 _headerHash = keccak256(_packetHeader);
        bytes32 _payloadHash = _packet.payloadHash();
        UlnConfig memory _config = ULTRA_LIGHT_NODE.getUlnConfig(address(this), srcEid);

        // Verify the message on the LZ ultra light node.
        // Note that this can could technically be DoS except that allowInitializePath returning false denies this DoS
        // vector. As a result, this should always return true and can never turn false.
        if (!ULTRA_LIGHT_NODE.verifiable(_config, _headerHash, _payloadHash)) revert LZ_ULN_Verifying();

        // Get the source chain
        sourceIdentifier = bytes32(uint256(srcEid));
        // Get the sender
        implementationIdentifier = abi.encode(_packetHeader.sender());
        // Get the message
        message_ = _packet.message();
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message, uint64 deadline) internal override returns(uint128 costOfsendPacketInNativeToken) {

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