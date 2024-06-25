# NewStableCoin: A Simplified Overcollateralized Stablecoin System

## Overview

NewStableCoin (NSC) is a decentralized stablecoin pegged to 1 USD, similar to DAI but with a focus on simplicity and security. The NSC system is designed to always be overcollateralized using only WETH and WBTC as collateral assets. This repository contains the core smart contracts that govern the minting, redeeming, and liquidation processes of the NSC stablecoin.

## Contracts

### NSCEngine

The `NSCEngine` contract handles the core logic for the NSC system, including collateral management, NSC minting and burning, and liquidation processes.

Key features include:

- **Collateral Management:** Users can deposit and redeem collateral tokens (WETH, WBTC).
- **NSC Minting and Burning:** Users can mint NSC against their collateral and burn NSC to redeem their collateral.
- **Liquidation:** Users can liquidate undercollateralized positions and earn a liquidation bonus.
- **Health Factor:** Ensures the system remains overcollateralized at all times.

### NewStableCoin

The `NewStableCoin` contract implements the ERC20 standard with additional functionalities for minting and burning tokens. It is the token contract for NSC.

## Functions

### NSCEngine Contract

- **depositCollateralAndMintToken:** Deposits collateral and mints NSC in a single transaction.
- **depositCollateral:** Allows users to deposit collateral tokens.
- **redeemCollateralForNSC:** Burns NSC and redeems underlying collateral.
- **redeemCollateral:** Redeems a specified amount of collateral.
- **burnNSC:** Burns a specified amount of NSC.
- **mintNSC:** Mints a specified amount of NSC.
- **liquidate:** Allows users to liquidate undercollateralized positions.

### NewStableCoin Contract

- **burn:** Burns a specified amount of NSC.
- **mint:** Mints a specified amount of NSC to a given address.

## Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/yourusername/NewStableCoin.git
   cd NewStableCoin
   ```
