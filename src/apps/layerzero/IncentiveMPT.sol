// SPDX-License-Identifier: BUSL-1.1

// TODO: Check if we can upgrade solidity version
// pragma solidity 0.7.6;
pragma solidity ^0.8.13;

import "./utility/LayerZeroPacket.sol";
import "./utility/UltraLightNodeEVMDecoder.sol";
import "./interfaces/IValidationLibraryHelperV2.sol";
import "./interfaces/ILayerZeroValidationLibrary.sol";

contract MPTValidator01 is ILayerZeroValidationLibrary, IValidationLibraryHelperV2 {
    using RLPDecode for RLPDecode.RLPItem;
    using RLPDecode for RLPDecode.Iterator;

    uint8 public constant proofType = 1;
    uint8 public constant utilsVersion = 4;
    bytes32 public constant PACKET_SIGNATURE = 0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82;

    function validateProof(bytes32 _receiptsRoot, bytes calldata _transactionProof, uint _remoteAddressSize) external view override returns (LayerZeroPacket.Packet memory packet) {
        require(_remoteAddressSize > 0, "ProofLib: invalid address size");
        (bytes[] memory proof, uint[] memory receiptSlotIndex, uint logIndex) = abi.decode(_transactionProof, (bytes[], uint[], uint));

        ULNLog memory log = _getVerifiedLog(_receiptsRoot, receiptSlotIndex, logIndex, proof);
        require(log.topicZeroSig == PACKET_SIGNATURE, "ProofLib: packet not recognized"); //data

        packet = LayerZeroPacket.getPacketV2(log.data, _remoteAddressSize, log.contractAddress);

        return packet;
    }

    function _getVerifiedLog(bytes32 hashRoot, uint[] memory paths, uint logIndex, bytes[] memory proof) internal pure returns (ULNLog memory) {
        require(paths.length == proof.length, "ProofLib: invalid proof size");
        require(proof.length > 0, "ProofLib: proof size must > 0");
        RLPDecode.RLPItem memory item;
        bytes memory proofBytes;

        for (uint i = 0; i < proof.length; i++) {
            proofBytes = proof[i];
            require(hashRoot == keccak256(proofBytes), "ProofLib: invalid hashlink");
            item = RLPDecode.toRlpItem(proofBytes).safeGetItemByIndex(paths[i]);
            if (i < proof.length - 1) hashRoot = bytes32(item.toUint());
        }

        // burning status + gasUsed + logBloom
        RLPDecode.RLPItem memory logItem = item.typeOffset().safeGetItemByIndex(3);
        RLPDecode.Iterator memory it = logItem.safeGetItemByIndex(logIndex).iterator();
        ULNLog memory log;
        log.contractAddress = bytes32(it.next().toUint());
        log.topicZeroSig = bytes32(it.next().safeGetItemByIndex(0).toUint());
        log.data = it.next().toBytes();

        return log;
    }

    function getUtilsVersion() external view override returns (uint8) {
        return utilsVersion;
    }

    function getProofType() external view override returns (uint8) {
        return proofType;
    }

    function getVerifyLog(bytes32 hashRoot, uint[] memory receiptSlotIndex, uint logIndex, bytes[] memory proof) external pure override returns (ULNLog memory) {
        return _getVerifiedLog(hashRoot, receiptSlotIndex, logIndex, proof);
    }

    function getPacket(bytes memory data, uint sizeOfSrcAddress, bytes32 ulnAddress) external pure override returns (LayerZeroPacket.Packet memory) {
        return LayerZeroPacket.getPacketV2(data, sizeOfSrcAddress, ulnAddress);
    }
}
