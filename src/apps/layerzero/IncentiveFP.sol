// SPDX-License-Identifier: BUSL-1.1

// TODO: Check if we can upgrade solidity version
// pragma solidity 0.7.6;
pragma solidity ^0.8.13;

import "./utility/LayerZeroPacket.sol";
import "LayerZero/interfaces/ILayerZeroValidationLibrary.sol";
import "LayerZero/interfaces/IValidationLibraryHelperV2.sol";

contract FPValidator is ILayerZeroValidationLibrary, IValidationLibraryHelperV2 {
    uint8 public proofType = 2;
    uint8 public utilsVersion = 1;

    function validateProof(bytes32 _packetHash, bytes calldata _transactionProof, uint _remoteAddressSize) external view override returns (LayerZeroPacket.Packet memory packet) {
        require(_remoteAddressSize > 0, "ProofLib: invalid address size");
        // _transactionProof = srcUlnAddress (32 bytes) + lzPacket
        require(_transactionProof.length > 32 && keccak256(_transactionProof) == _packetHash, "ProofLib: invalid transaction proof");

        bytes memory ulnAddressBytes = bytes(_transactionProof[0:32]);
        bytes32 ulnAddress;
        assembly {
            ulnAddress := mload(add(ulnAddressBytes, 32))
        }
        packet = LayerZeroPacket.getPacketV3(_transactionProof[32:], _remoteAddressSize, ulnAddress);

        return packet;
    }

    function getUtilsVersion() external view override returns (uint8) {
        return utilsVersion;
    }

    function getProofType() external view override returns (uint8) {
        return proofType;
    }

    function getVerifyLog(bytes32, uint[] calldata, uint, bytes[] calldata proof) external pure override returns (ULNLog memory log) {}

    function getPacket(bytes memory data, uint sizeOfSrcAddress, bytes32 ulnAddress) external pure override returns (LayerZeroPacket.Packet memory) {
        return LayerZeroPacket.getPacketV3(data, sizeOfSrcAddress, ulnAddress);
    }
}
