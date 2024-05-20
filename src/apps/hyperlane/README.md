# Hyperlane Generalised Incentives

This is a Hyperlane implementation of Generalised Incentives. It works by using the Hyperlane Mailbox to emit messages but instead of using the Hyperlane mailbox to verify messages, messages are to be delivered directly to this contract for verification and execution.

The messages are still delivered to the Hyperlane Mailbox for emitting.


# Address encoding:

Hyperlane uses 32 bytes to represent addresses.

EVM -> EVM
```solidity

function _to_bytes32(address target) internal returns(bytes memory) {
    return abi.encode(target);
}

```