# Generalized Incentive Escrow

This repository contains an implementation of a generaized Incentive Scheme. 

## Idea

Currently, many AMBs have poor and non-standardized relayer incentives. They either miss one or many of the following features:

- Unspent gas is refunded.
Often the gas associated with transaction calls is semi-unknown until immediately before execution. As a result the gas paid by the user often has to be over estimated by 10%, 20% or even more.
  
- Payment is conditional on execution.
Some relaying scheme require the user or protocol to trust one or a few, sometimes centralized, entities with their gas payment. In cases where these relayers fail to do their job, a new payment has to be initiated.

- Prepay for an ack message
Some applications are rely on, or use, acks for application logic, or simply to improve the user experience. If it is not possible to pay for an ack on the source chain in the source currency, the user is overly burdend with figuring out how to aquire additional gas or the application has to do gas management on all the chains they are deployed on.

and this does not mention non-standardized payments, different interface, payments in protocol tokens, and address formats.

### Solution

By placing a contract as an intermediary between the applications and the AMBs, it can define how relayers are paid based on the observed (and verified) messages delivered. Since the contraxt sits on-chain, its logic is governed by the base chain rather than off-chain logic.
This also allows the contract to surround the AMB with additional logic:
- Measuring the gas used by the application
- Reliably sending a message back to the source chain
- Paying the relayer in a standardized token

## Incentive Definition

### Sole Relayer

If both the source to destination relayer and the destination to source relayers are the same, the full incentive amount is sent to the relayer without any additional logic. 

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

This will return a coverage report. You can also add `--report lcov` and use a suitable program to view the coverage report graphically. VS code has `Coverage Gutters` but other online tools also exist.

Note that the coverage report isn't perfect. Several lines which are tested are reported as untested. It is unknown if this is caused by the `--ir-minimum` flag or bad test configuration.
