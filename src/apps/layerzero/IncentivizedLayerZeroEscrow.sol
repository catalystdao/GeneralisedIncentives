// SPDX-License-Identifier: DO-NOT-USE
pragma solidity ^0.8.22;

import { ILayerZeroEndpointV2, MessagingParams, MessagingFee, MessagingReceipt, Origin } from "LayerZero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroExecutor } from "LayerZero-v2/messagelib/contracts/interfaces/ILayerZeroExecutor.sol";
import { IMessageLibManager, SetConfigParam } from "LayerZero-v2/protocol/contracts/interfaces/IMessageLibManager.sol";
import { PacketV1Codec } from "LayerZero-v2/protocol/contracts/messagelib/libs/PacketV1Codec.sol";

import { IncentivizedMessageEscrow } from "../../IncentivizedMessageEscrow.sol";
import { UlnConfig } from "./interfaces/IUlnBase.sol";
import { IReceiveUlnBase, UlnConfig, Verification } from "./interfaces/IUlnBase.sol";

/**
 * @notice Always returns 0 to any job.
 * @dev We have set ourself as the executor. As a result, we need to implement the executor interfaces.
 */
contract ExecutorZero is ILayerZeroExecutor {
    function assignJob(
        uint32 /* _dstEid */,
        address /* _sender */,
        uint256 /* _calldataSize */,
        bytes calldata /* _options */
    ) external pure returns (uint256 price) {
        return price = 0;
    }

    function getFee(
        uint32 /* _dstEid */,
        address /* _sender */,
        uint256 /* _calldataSize */,
        bytes calldata /* _options */
    ) external pure returns (uint256 price) {
        return price = 0;
    }
}

/**
 * @title Incentivized LayerZero Messag Escrow
 * @notice Provides an alternative pathway to incentivize LayerZero message relaying.
 * While Layer Zero has a native way to incentivize message relaying, it lacks:
 * - Gas refunds of unspent gas.
 *   No gas refunds increase the cost of cross-chain messages by ~10% to ~20%.
 *   That is before accounting for the fact that the cross-chain gas prices are fixed
 *   and charged a margin on.
 *
 * - Payment conditional on execution.
 *   By not allowing anyone to claim messaging payment, the relaying incentive becomes
 *   a denial-of-service vector. If the relayer specified in the LZ config does not
 *   relay the message, it likely won't get relayed. It is even built directly into LZ
 *   that some relayers (the default included) may adjust their quotes depending on the
 *   application. While permissionwise, it is 1/N, the economic security is 1/1.
 *
 * @dev This contract only allows messages smaller than or equal to 65536 bytes to be sent.
 * This implementation works by breaking the LZ endpoint flow. It relies on the
 * `.verfiyable` check on the ULN. When a cross-chain message is verified (step 2)
 * `commitVerification` is called and it deletes the storage for the verification: https://github.com/LayerZero-Labs/LayerZero-v2/blob/1fde89479fdc68b1a54cda7f19efa84483fcacc4/messagelib/contracts/uln/uln302/ReceiveUln302.sol#L56
 * this exactly `verfiyable: true -> false`.
 * We break this making the subcall `EndpointV2::verify` revert on _initializable:
 * https://github.com/LayerZero-Labs/LayerZero-v2/blob/1fde89479fdc68b1a54cda7f19efa84483fcacc4/protocol/contracts/EndpointV2.sol#L340
 * That is the purpose of `allowInitializePath`.
 *
 * Then we can use `verfiyable` to check if a message has been verified by DVNs.
 */
contract IncentivizedLayerZeroEscrow is IncentivizedMessageEscrow, ExecutorZero {
    using PacketV1Codec for bytes;
    uint32 CONFIG_TYPE_EXECUTOR = 1;
    uint32 MAX_MESSAGE_SIZE = 65536;

    struct ConfigTypeExecutor {
        uint32 maxMessageSize;
        address executorAddress;
    }

    // Errors specific to this contract.
    error LayerZeroCannotBeAddress0();
    error IncorrectDestination(address actual);

    // Errors inherited from LZ.
    error LZ_ULN_Verifying();
    error LZ_ULN_InvalidPacketHeader();
    error LZ_ULN_InvalidPacketVersion();
    error LZ_ULN_InvalidEid();

    uint16 internal constant TYPE_3 = 3;
    /** @notice Set the LayerZero options. Needs to be 2 bytes with a version for the optionsSplit Library to process. */
    bytes constant LAYERZERO_OPTIONS = abi.encodePacked(TYPE_3);

    /** @notice The Layer Zero Endpoint. It is the destination for packages & configuration */
    ILayerZeroEndpointV2 immutable ENDPOINT;

    /** @notice chainid is immutable on LayerZero endpoint, so we read it and store it likewise. */
    uint32 public immutable chainId;

    /** @notice Only allow LZ to send value to this contract  */
    uint8 allowExternalCall = 1;

    /**
     * @param sendLostGasTo Address to get gas that could not get sent to the recipitent.
     * @param lzEndpointV2 LayerZero endpount. It is used for sending messages.
     */
    constructor(address sendLostGasTo, address lzEndpointV2) IncentivizedMessageEscrow(sendLostGasTo) {
        if (lzEndpointV2 == address(0)) revert LayerZeroCannotBeAddress0();

        // Load the LZ endpoint. This is the contract we will be sending events to.
        ENDPOINT = ILayerZeroEndpointV2(lzEndpointV2);
        // Set chainId.
        chainId  = ENDPOINT.eid();
    }

    function _uniqueSourceIdentifier() override internal view returns(bytes32) {
        return bytes32(uint256(chainId));
    }

    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal pure returns(uint64 timestamp) {
        return 0; // TODO: Set to something like 1 month.
    }

    /**
     * @notice Set ourself as executor on all (provided) remote chains. This is required before we anyone
     * can send message out of that chain.
     * @dev sendLibrary is not checked. It is assumed that any endpoint will accept anything as long as it is somewhat sane.
     * @param sendLibrary Contract to set config on.
     * @param remoteEids List of remote Eids to set config on.
     // TODO: read sendLibrary from Endpoint maybe.
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

    function _estimateAdditionalCost(uint32 destEid) view internal returns(uint256 amount) {
        MessagingParams memory params = MessagingParams({
            dstEid: uint32(destEid),
            receiver: bytes32(0), // Is unused by LZ.
            message: hex"",
            options: LAYERZERO_OPTIONS, // TODO: Are these options important?
            payInLzToken: false
        });

        MessagingFee memory fee = ENDPOINT.quote(params, address(this));
        amount = fee.nativeFee;
    }

    /**
     * @notice Get a very rough estimate of the additional cost to send a message.
     * Layer Zero requires knowing the destination chain and that is not possible with this function signature.
     * For a better quote, use the function overload.
     */
    function estimateAdditionalCost() external view returns(address asset, uint256 amount) {
        amount = _estimateAdditionalCost(chainId);
        asset =  address(0);
    }

    /**
     * @notice Get an exact quote.
     */
    function estimateAdditionalCost(uint256 destinationChainId) external view returns(address asset, uint256 amount) {
        amount = _estimateAdditionalCost(uint32(destinationChainId));
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

        // The ULN may not be constant since it depends on the srcEid. :(
        // We need to read the ULN from the endpoint.
        IReceiveUlnBase ULN = IReceiveUlnBase(ENDPOINT.defaultReceiveLibrary(srcEid));

        UlnConfig memory _config = ULN.getUlnConfig(address(this), srcEid);

        // Verify the message on the LZ ultra light node.
        // Without any protection, this is a DoS vector. It is protected by setting allowInitializePath to return false
        // As a result, once this returns true it should return true perpetually.
        bool verifyable = ULN.verifiable(_config, _headerHash, _payloadHash);
        if (!verifyable) {
            // LayerZero may have migrated to a new receive library. Check the timeout receive library.
            (address timeoutULN, ) = ENDPOINT.defaultReceiveLibraryTimeout(srcEid);
            ULN = IReceiveUlnBase(timeoutULN);
            verifyable = ULN.verifiable(_config, _headerHash, _payloadHash);
            if (!verifyable) revert LZ_ULN_Verifying();
        }

        // Get the source chain
        sourceIdentifier = bytes32(uint256(srcEid));
        // Get the sender
        implementationIdentifier = abi.encode(_packetHeader.sender());
        // Get the message
        message_ = _packet.message();
    }

    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message, uint64 /* deadline */) internal override returns(uint128 costOfsendPacketInNativeToken) {

        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(destinationChainIdentifier)),
            receiver: bytes32(destinationImplementation),
            message: message,
            options: LAYERZERO_OPTIONS,
            payInLzToken: false
        });

        // Handoff package to LZ.
        // We are getting a refund on any excess value we sent. We can get the native fee by subtracting it from
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