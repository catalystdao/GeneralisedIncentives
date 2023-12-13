# Wormhole Generalised Incentives

This is a Wormhole implementation of Generalised INcentives. It works by Hijacking the Wormhole contract. It relies on the Wormhole state while re-implementing the verification logic in a way that is cheaper.

# Address encoding

Wormhole uses 32 bytes to represent addresses.

EVM -> EVM

```solidity

function _to_bytes32(address target) internal returns(bytes memory) {
    return abi.encode(target);
}

```