# Generalized Incentive Escrow

This repository contains a base implementation of the Generalized Incentive Scheme in Solidity. The specification description can currently be found [here](https://catalabs.notion.site/Generalised-Relayer-Incentive-Scheme-cfaa1ccd2bf94d82b1c54b9f483baf05?pvs=4).

## Idea

The idea behind the generalized incentive escrow is simple:
- Simplify the integration experience of new messaging protocols
- Standardize the relaying incentive scheme
- Deliver an ack back to the source chain which can execute fallback logic



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