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
 * Ideally we would revert when the sender is not us. However, that assumes that people would trust random
 * contracts and set them as their executor. That shouldn't happen. As a result, we save the gas and don't check.
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
 *
 * Before using a deployed version of this contract `initConfig` has to be called to set ourself as
 * the executor. This has to be done for every remote chain & ULN.
 *
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

    /** @notice Executor config type. We use this when we set ourself as the executor on the endpoint. */
    uint32 private constant CONFIG_TYPE_EXECUTOR = 1;

    /** @notice Only allow messages of size 65536 bytes and smaller. */
    uint32 constant MAX_MESSAGE_SIZE = 65536;

    /** @notice LZ Config type struct for setting an executor. */
    struct ConfigTypeExecutor {
        uint32 maxMessageSize;
        address executorAddress;
    }

    // Errors specific to this contract.
    error LayerZeroCannotBeAddress0();
    error IncorrectDestination();
    error NoReceive();

    // Errors inherited from LZ.
    error LZ_ULN_Verifying();
    error LZ_ULN_InvalidPacketHeader();
    error LZ_ULN_InvalidPacketVersion();
    error LZ_ULN_InvalidEid();

    /** @notice LZ messaging options. This is the option type and has to be set. */
    uint16 private constant TYPE_3 = 3;
    /** @notice Set the LayerZero options. Needs to be 2 bytes with a version for the optionsSplit Library to process. */
    bytes private constant LAYERZERO_OPTIONS = abi.encodePacked(TYPE_3);

    /** @notice The Layer Zero Endpoint. It is the destination for packages & configuration */
    ILayerZeroEndpointV2 public immutable ENDPOINT;

    /** @notice chainid is immutable on LayerZero endpoint, so we read it and store it likewise. */
    uint32 public immutable chainId;

    /** @notice Only allow LZ to send value to this contract. */
    uint8 internal allowExternalCall = 1;

    /**
     * @param sendLostGasTo Address to get gas that could not get sent to the recipitent.
     * @param lzEndpointV2 LayerZero endpount. It is used for sending messages.
     */
    constructor(address sendLostGasTo, address lzEndpointV2) IncentivizedMessageEscrow(sendLostGasTo) {
        if (lzEndpointV2 == address(0)) revert LayerZeroCannotBeAddress0();
        // Load the LZ endpoint. This is the contract we will be sending events to.
        ENDPOINT = ILayerZeroEndpointV2(lzEndpointV2);
        // Set chainId.
        chainId = ENDPOINT.eid();
    }

    /** @notice LayerZero identifies chains based on "eid"s. */
    function _uniqueSourceIdentifier() override internal view returns(bytes32) {
        return bytes32(uint256(chainId));
    }

    /**
     * @notice LayerZero proofs are by default non-expiring. However, the administrator can set
     * a new receiveLibrary. When they do this, they invalidate the previous receiveLibrary and
     * any associated proofs. As a result, the owners of the endpoint can determine when and if
     * proofs should be invalidated.
     * On one hand, you could arguemt that this warrant a timeout of 0, since these messages could
     * be recovered and ordinary usage would imply unlimited. However, since the structure of
     * LayerZero generally does not encorage 'recovery', it has been set to 30 days ≈ 1 month.
     */
    function _proofValidPeriod(bytes32 /* destinationIdentifier */) override internal pure returns(uint64 timestamp) {
        return 30 days;
    }

    /**
     * @notice Set ourself as executor on all (provided) remote chains. This is required before anyone
     * can send message to any chain..
     * @dev sendLibrary is not checked. It is assumed that any endpoint will accept anything as long as it is somewhat sane.
     * The reference LZ endpoint requires that sendLibrary is a owner approved once and that fits the requirement.
     * This call also sets maxMessageSize to MAX_MESSAGE_SIZE.
     * The reason why we can't read the sendLibrary is because it may depend on the EID.
     * @param sendLibrary sendLibrary to configure to use this contract as executor.
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
     * This contract relies on a `verifiyable` call on the LZ receiveULN. In an ordinary config, when
     * `verifiyable` returns true, the package state can progress by calling `commitVerification` and
     * `verifiyable` switched from true to false. This breaks our flow. The LZ Endpoint calls `allowInitializePath`
     * during this flow and this function is intended to break that.
     * As a result, when `verifiyable` switches from false => true it cannot be switched true => false.
     */
    function allowInitializePath(Origin calldata /* _origin */) external pure returns(bool) {
        return false;
    }

    function _estimateAdditionalCost(uint32 destEid) view internal returns(uint256 amount) {
        MessagingParams memory params = MessagingParams({
            dstEid: uint32(destEid),
            receiver: bytes32(0), // Is unused by LZ.
            message: hex"", // Is sent to the executor as length. We don't care about it so set it as small as possible.
            options: LAYERZERO_OPTIONS,
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
        (asset, amount) = estimateAdditionalCost(bytes32(uint256(chainId)));
    }

    /**
     * @notice Get an exact quote. LayerZero charges based on the destination chain.
     */
    function estimateAdditionalCost(bytes32 destinationChainId) public view returns(address asset, uint256 amount) {
        amount = _estimateAdditionalCost(uint32(uint256(destinationChainId)));
        asset =  address(0);
    }

    /**
     * @notice Verification of LayerZero packages. This function takes the whole LZ package
     * as _packet rather than splitting the package in two.
     * The function works by getting the defaultReceiveLibrary from the endpoint. We never set a specific receiveLibrary
     * so we use the default. Getting the defaultReceiveLibrary directly is slightly cheaper.
     *
     * On the receiveLibrary, `verifiable` is called to check if it has been verified. 
     * If not, it is checked if a timeoutLibrary (the receiveLibrary has recently been changed) is available
     * and then `verifiable` is checked on the timeoutLibrary.
     */
    function _verifyPacket(bytes calldata /* context */, bytes calldata _packet) view internal override returns(bytes32 sourceIdentifier, bytes memory implementationIdentifier, bytes calldata message_) {
        _assertHeader(_packet.header());

        // Get the source chain.
        uint32 srcEid = _packet.srcEid();

        bytes32 _headerHash = keccak256(_packet.header());
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
            (address timeoutULN, uint256 expiry) = ENDPOINT.defaultReceiveLibraryTimeout(srcEid);
            if (timeoutULN == address(0) || expiry < block.timestamp) revert LZ_ULN_Verifying();
            verifyable = IReceiveUlnBase(timeoutULN).verifiable(_config, _headerHash, _payloadHash);
            if (!verifyable) revert LZ_ULN_Verifying();
        }

        // Get the source chain
        sourceIdentifier = bytes32(uint256(srcEid));
        // Get the sender
        implementationIdentifier = abi.encode(_packet.sender());
        // Get the message
        message_ = _packet.message();
    }

    /** @notice Delivers a package to the LZ endpoint. */
    function _sendPacket(bytes32 destinationChainIdentifier, bytes memory destinationImplementation, bytes memory message, uint64 /* deadline */) internal override returns(uint128 costOfsendPacketInNativeToken) {

        MessagingParams memory params = MessagingParams({
            dstEid: uint32(uint256(destinationChainIdentifier)),
            receiver: bytes32(destinationImplementation),
            message: message,
            options: LAYERZERO_OPTIONS,
            payInLzToken: false
        });

        // Handoff package to LZ.  We are getting a refund on any excess value we sent. Then 
        // receipt.fee.nativeFee is the fee we paid.
        allowExternalCall = 2; // Allow refunds from LZ
        MessagingReceipt memory receipt = ENDPOINT.send{value: msg.value}(
            params,
            address(this)
        );
        allowExternalCall = 1; // Disallow other refunds.

        // Set the cost of the sendPacket to msg.value 
        costOfsendPacketInNativeToken = uint128(receipt.fee.nativeFee);

        return costOfsendPacketInNativeToken;
    }

    // Allow LZ refunds to come in while disallowing randoms from sending to this contract.
    // It won't stop abuses but it is the best we can do.
    receive() external payable {
        // allowExternalCall is hot so it shouldn't be expensive to read.
        if (allowExternalCall == 1) revert NoReceive();
    }

    /**
     * @notice Validate the package header. Similar to the LZ version except
     * This function doesn't check length (it is enforced by library) and
     * it checks if we are the receiver.
     */
    function _assertHeader(bytes calldata _packetHeader) internal view {
        // assert packet header version is the same as ULN
        if (_packetHeader.version() != PacketV1Codec.PACKET_VERSION) revert LZ_ULN_InvalidPacketVersion();
        // assert the packet is for this endpoint
        if (_packetHeader.dstEid() != chainId) revert LZ_ULN_InvalidEid();
        // Check that we are the receiver
        if (_packetHeader.receiverB20() != address(this)) revert IncorrectDestination();
    }
}