# Decentralized Stablecoin

This project is a decentralized stablecoin system designed to maintain a stable value pegged to USD. It leverages Chainlink price feeds and allows users to mint stablecoins by collateralizing crypto assets such as wETH and wBTC.

## Features

1. Pegged to USD
    - Chainlink price feed integration
    - Functions to exchange ETH & BTC to USD
2. Algorithmic
    - Minting only allowed with sufficient collateral
3. Collateral - exogenous (Crypto)
    - wETH
    - wBTC

## Architecture

The stablecoin system consists of smart contracts that manage collateral deposits, minting, and redemption of the stablecoin. It ensures over-collateralization and uses price oracles to maintain the peg.

## How it works

- Users deposit collateral (wETH or wBTC).
- The system uses Chainlink price feeds to determine the USD value of the collateral.
- Users can mint stablecoins up to a certain collateralization ratio.
- The system enforces algorithmic rules to maintain stability and solvency.

## Testing

- Fuzzing tests include:
    - Stateless fuzzing
    - Stateful fuzzing (invariant testing)

## Installation

To get started, clone the repository and install dependencies. Use Foundry or your preferred Solidity development environment to compile and test the contracts.

---