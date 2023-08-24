// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface SmallStructs {

	struct SmallVM {
		// uint8 version;
		// uint32 timestamp;
		// uint32 nonce;
		uint16 emitterChainId;
		bytes32 emitterAddress;
		// uint64 sequence;
		// uint8 consistencyLevel;

		uint32 guardianSetIndex;
	}
}