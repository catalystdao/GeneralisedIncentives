# Mock implementation

This is a very simple mock implementation of how to verify messages. A designated signer is stored in the contract. If the address is signed by that address it is considered good.

# Address encoding

Mock uses 65 bytes to represent addresses. 64 for the address and 1 to describe the length. This is intended to be compatible with the vast majority of chains where 32 bytes might not.

EVM -> EVM

```solidity

function _to_bytes65(address target) internal returns(bytes memory) {
    return abi.encodePacked(
        uint8(20),
        bytes32(0),
        uint256(uint160(target))
    )
}

```