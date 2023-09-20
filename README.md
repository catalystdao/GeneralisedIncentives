Contracts within this repo have not been audited and should not be used in production.

# Generalized Incentive Escrow

This repository contains an implementation of a generalized Incentive Scheme. 

## Idea

Currently, many AMBs (arbitrary message bridges) have poor and non-standardized relayer incentives. They either miss one or many of the following features:

- Unspent gas is refunded.
Often the gas associated with transaction calls is semi-unknown until immediately before execution. As a result the gas paid by the user often has to be overestimated by 10%, 20%, or even more.
  
- Payment is conditional on execution.
Some relaying schemes require the user or protocol to trust one or a few, sometimes centralized, entities with their gas payment. In cases where these relayers fail to do their job, a new payment has to be initiated.

- Prepay for an ack message
Some applications rely on, or use, acks for application logic, or simply to improve the user experience. If it is not possible to pay for an ack on the source chain in the source currency, the user is overly burdened with figuring out how to acquire additional gas or the application has to do gas management on all the chains they are deployed on.

and this does not mention non-standardized payments, different interfaces, payments in protocol tokens, and address formats.

### Solution

By placing a contract as an intermediary between the applications and the AMBs, it can define how relayers are paid based on the observed (and verified) messages delivered. Since the contract sits on-chain, its logic is governed by the base chain rather than off-chain logic.
This also allows the contract to surround the AMB with additional logic:
- Measuring the gas used by the application
- Reliably sending a message back to the source chain
- Paying the relayer in a standardized token

## Incentive Definition

The incentive variables can vary in size, for EVM they are set so all fit into 2 storage slots. For other implementations, the address size, slot size, or gas price could be defined differently and should result in a different storage layout to optimize for gas.
```js
struct IncentiveDescription {
    uint48 maxGasDelivery;
    uint48 maxGasAck;
    address refundGasTo;
    uint96 priceOfDeliveryGas;
    uint96 priceOfAckGas;
    uint64 targetDelta;
}
```


The incentive is defined by 6 variables:
- `maxGasDelivery`: The maximum gas used* by the contract on the destination chain.
- `maxGasAck`: The maximum gas used* by the contract on the source chain (ack).
- `refundGasTo`: Any unspent incentive should be refunded to this address.
- `priceOfDeliveryGas`: The price of gas on the destination chain in source chain currency.
- `priceOfAckGas`: The price of gas on the source chain in source chain currency.
- `targetDelta`: The Ideal time between execution on destination chain and ack. (Opt-in for strong ack incentives.)

Relaying incentives are stored strictly on the source chain with no communication to the destination chain except `maxGasDelivery`.


### *Definition of gas

There are many complexities with gas: How is gas measured, how is gas priced, and how is the gas limit enforced?

It is not possible to measure the exact gas cost used by a transaction call on EVM. Likewise, it is also not possible to enforce a strict limit on the gas spent within the call (and still have additional logic execute). For non-EVM chains, this is very unlikely to be different.

**Gas enforcement** is done by limiting the external call to exactly `maxGas<Delivery/Ack>`. On EVM this can be enforced by setting a gas limit on the external call.

**Gas spent** is measured from the first possible time to the last possible time and always includes the external call. This is not a perfect measure because: There is always logic before and after the gas cost can be measured. Furthermore, since only `maxGas<Delivery/Ack>` has been paid for, any excess (say the application used exactly `maxGas`) is not directly paid for by the incentives. The gas spent on the destination chain is sent back to the source chain with the ack.
If a chain is incapable of measuring gas, it should return `maxGas` as `gasSpent`.

**Gas pricing** is always in source chain currency. This simplifies the experience and still allows for a lot of flexibility. For low-priority messages, `priceOfDeliveryGas` can be set appropriately or even to 0. Likewise, if an ack is not critical to the application `priceOfAckGas` can be set similarly low. The final relay incentive is then computed as `min(spentGas<Delivery/Ack>, maxGas<Delivery/Ack>) · priceOf<Delivery/Ack>Gas` for both Delivery and Ack. The difference between the sum of both and the maximum is refunded to `refundGasTo`.

### Single Relayer

If both the source-to-destination relayer and the destination-to-source relayers are the same, the full incentive amount is sent to the relayer without any additional logic. The transfer should be a single transfer rather than 2.

### Strong Ack Incentives (opt-in)

For applications that are reliant on acks for more than a user experience improvement, strong ack incentives are needed. Without stronger ack incentives, relayers can keep the acks for an indefinite duration and when source gas is low, cash in all of the deliveries. This could be desirable (in which case don't opt in) but it could also be undesirable. (in which case do opt-in).

The idea is that an ideal execution time between execution on destination and the delivery of the ack exists: `targetDelta`. If more time than `targetDelta` has passed, then the ack should be more incentivised. At the same time, if less time has passed then the delivery incentive should be higher. The following pseudo code is how the code should treat the 2 cases (less and more time):

```javascript
ackFee = spentGasAck * priceOfAckGas
deliveryFee = spentGasDelivery * priceOfDeliveryGas
// If the time it took to get the ack back is exactly targetDelta, then exactly the 2 fees are delivered.
if (ackExecutionTime == targetDelta) {
    return (deliveryFee, ackFee)
}
// If less time than expected, then the deliveryFee should be linearly higher compared to the time passed.
if (ackExecutionTime < targetDelta) {
    return (
        deliveryFee + ackFee * (targetDelta - ackExecutionTime)/targetDelta,
        ackFee - ackFee * (targetDelta - ackExecutionTime)/targetDelta,
    )
}
// If more time than expected, then the ackFee should be linearly higher compared to the time passed.
if (ackExecutionTime > targetDelta) {
    // If it took more time than 200% of targetDelta then the deliveryfee should be 0.
    if (ackExecutionTime >= targetDelta * 2) {
        return (0, ackFee + deliveryFee)
    }
    return (
        deliveryFee - deliveryFee * (ackExecutionTime - targetDelta)/targetDelta,
        ackFee + deliveryFee * (ackExecutionTime - targetDelta)/targetDelta,
    )
}
```
The exact implementation is allowed to vary slightly to optimize for gas.

When using this scheme, it is very important that `targetDelta` is set to more than the time it takes for messages to get confirmed on the destination chain as otherwise some of the delivery gas is always given to the ack relayer.

This definition works well in combination with the single relayer addition: If a single relayer is prompt, then not only do they get the full delivery and ack fee but they also save gas because of the lower complexity associated with a single transaction.

It is very important to remember that the ack "clock" starts ticking from when the destination call has been executed not when the first message was emitted. As a result, if it takes 30 days to send the message from the source to the destination but the ack from the destination to the source only takes 10 seconds, then it is those 10 seconds that are counted against `targetDelta`. As a result, the base `maxGasDelivery` will incentivize the delivery of the message to the destination until it has been delivered.

## Message structure

The messages structure can be found in src/MessagePayload.sol. 2 message types are defined: `SourcetoDestination` and `DestinationtoSource` which can be identified by the first byte of the message as 0x00 and 0x01 respectively.

## Implementation Asterisks

The implementation is not perfect. Below the most notable implementation strangenesses are documented.

### Bad execution (or out of gas)

If a message reverts, ran out of gas, or otherwise failed to return an ack the implementation should do its best to not revert but instead send the original message back prepended with 0xff as the acknowledgment.

For EVM this is currently limited by [Solidity #13869](https://github.com/ethereum/solidity/issues/13869). Calls to contracts which doesn't implement the proper endpoint will fail.
- Relayers should emulate the call before calling the function to avoid wasting gas.
- If contracts expect the call to execute (or rely on the ack), contracts need to make sure they are calling a contract that implements proper interfaces for receiving calls.

### Ack out of gas

Ack calls are not limited by the bad execution named above. As a result, if the ack gas limit is not properly set and the ack runs out of gas the application could lose out on critical information.

As a result, a fallback function that allows acks to be executed as many times as needed exists. Applications should ensure that critical logic cannot be executed twice in acks by resubmitting the ack message.

### Invalid gas destination addresses are sent to a collection address

If one of the following addresses is incapable of receiving source chain tokens, the tokens will instead be sent to a centralized EOA:
- Source to Destination Relayer
- Refund Gas To

The destination-to-source relayer will result in the message reverting. They should resubmit the transaction with a proper relaying address.

### Relayer identification (bytes32)

"Only" 32 bytes are used to identificate the source-to-destination relayer on the source chain. For some chains, this is not enough. For implementations where this is not enough, a registry should be created on the source implementation which can convert a bytes32 identifier to an address. The bytes32 identifier must be based on the address (say `hash(address)`).

### Other-chain deployments

Because of the centralization associated with adding new chains / deployments, applications has to opt-in to these new chains. To understand the issue better, examine the following flow:

1. An escrow with honest logic with no flaws exist on chain Alpha. 
2. An application on chain Alpha can be drained by sending the fradulent key `0xabcdef` to the source chain. Ordinarly this never happens. This application trusts Alpha.
3. The administrator adds another deployment on chain Beta with same address as Alpha but with another bytecode deployed. Specifically, when the administrator calls this contract it sends `0xabcdef` to the application.
4. The application adds chain Beta to the allow list since the address matches the Beta address (thinking the byte code deployed must be the same).
5. The fradulent deployment on Beta sends `0xabcedf` to the application on chain Alpha
6. On Alpha the message is verified.

As a result, each application needs to tell the escrow where the other escrow sits and which escrow is allowed to send it messages. These mappings are 1:1, each chain identifier is only allowed a single escrow deployment.

If on the destination chain, the application which is being called hasn't set the escrow implementation as the sending address of the message, the message will be sent back with a failure identifier (`0xfe`)

## Failure Codes & Fallback

If a message fails, a failure code is prepended to the original message and sent back. Below a list of failure codes can be found:
- `0xff`: Generic application logic failure. Destination application couldn't be called, reverted or out of gas.
- `0xfe`: Sending escrow implementation is not authenticated to call the application.

## Repository Structure

The base implementation can be found in /src/IncentivizedMessageEscrow.sol. This contract is an abstract and is intended to be inherited by a true implementation. AMB implementations can be found under /src/apps.

## Testing

This repository uses Foundtry for testing. A mock implementation can be found in /src/apps/mock/IncentivizedMessageEscrow.sol which requires messages to be signed by a designated signer. This contract is preferably used for testing to simplify tests.

To run tests, do:
```
forge tests
```

To view coverage, run:
```
forge coverage --ir-minimum
```

This will return a coverage report. You can also add `--report lcov` and use a suitable program to view the coverage report graphically. VS Code has `Coverage Gutters` but other online tools also exist.

Note that the coverage report isn't perfect. Several lines which are tested are reported as untested. It is unknown if this is caused by the `--ir-minimum` flag or bad test configuration.
