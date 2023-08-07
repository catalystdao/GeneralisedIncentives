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


```js
struct IncentiveDescription {
    uint maxGasDelivery;
    uint maxGasAck;
    address refundGasTo;
    uint priceOfDeliveryGas;
    uint priceOfAckGas;
    uint targetDelta;
}
```

The incentive is defined by 6 variables:
- maxGasDelivery: The maximum gas used* by the contract on the destination chain.
- maxGasAck: The maximum gas used* by the contract on the source chain (ack).
- refundGasTo: Any unspent incentive should refunded to this address.
- priceOfDeliveryGas: The price of gas on the destination chain in source chain currency.
- priceOfAckGas: The price of gas on the source chain in source chain currency.
- targetDelta: The Ideal time between execution on destination chain and ack.



Relaying incentives are stored strictly on the source chain with no communication to the destination chain except from maxGasDelivery.



### *Definition of gas

There are many complexities with gas: How is gas measured, how is gas priced, and how is the gas limit enforced?

It is not possible to measure the exact gas cost used by a transaction call on EVM. Likewise, it is also not possible to enforce a strict limit on the gas spent within the call (and still having additional logic execute). For non-EVM chains this is very unlikely to be different.

**Gas enforecement** is done by limiting the external call to exactly maxGas<Delivery/Ack>. On EVM this can be enforced by setting a gas limit on the external call.

**Gas spent** is measured from the first possible time to the last possible time and always includes the external call. This is not a perfect measure because: There is always logic before and after the gas cost can be measured. Furthermore, since only maxGas<Delivery/Ack> has been paid for, any excess (say the application used exactly maxGas) is not directly paid for by the incentives.

**Gas pricing** is always in source chain currency. This simplifies the experience and still allows for a lot of flexiblity. For low priority 


### Sole Relayer

If both the source-to-destination relayer and the destination-to-source relayers are the same, the full incentive amount is sent to the relayer without any additional logic. 

### Strong Ack Incentives (opt-in)

 




## Repository Structure

The base implementation can be found in /src/IncentivizedMessageEscrow.sol. This contract is an abstract and is intended to be inherited by a true implementation. Several implementations can be found under /src/apps.  

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
