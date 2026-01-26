# Decentralized Stablecoin (DSC)

A decentralized, algorithmic stablecoin pegged to USD and backed by cryptocurrency collateral. This project implements a MakerDAO-inspired protocol with enhanced security features and oracle protection.

## Overview

The Decentralized Stablecoin system maintains a 1:1 peg with the US Dollar through overcollateralization with crypto assets (WETH and WBTC). The protocol is designed to be minimal, transparent, and entirely algorithmic with no governance.

## Core Features

### Stablecoin Characteristics
- **Exogenous Collateral**: Backed by external crypto assets (WETH, WBTC)
- **Dollar Pegged**: Maintains 1 DSC = $1 USD value
- **Algorithmic Stability**: Decentralized minting mechanism
- **Overcollateralized**: Requires 200% collateralization ratio

### Protocol Features

#### Collateral Management
- Deposit and withdraw supported collateral tokens (WETH/WBTC)
- Real-time USD value tracking via Chainlink price feeds
- Flexible collateral types with configurable price oracles

#### Minting & Burning
- Mint DSC tokens against deposited collateral
- Burn DSC to reduce debt or close positions
- Combined operations: deposit collateral and mint DSC in single transaction
- Redeem collateral by burning DSC

#### Liquidation System
- Automated liquidation of undercollateralized positions
- 10% liquidation bonus for liquidators
- Partial liquidation support
- Health factor monitoring to prevent insolvency

#### Security Features
- **Stale Price Protection**: Oracle library checks for stale Chainlink data (3-hour timeout)
- **Pausable**: Emergency pause functionality for admin
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Health Factor**: Continuous solvency monitoring

#### Admin Controls
- Adjustable liquidation threshold
- Configurable liquidation bonus
- Customizable minimum health factor
- Pause/unpause protocol operations

## Technical Architecture

### Smart Contracts

- **DecentralizedStableCoin.sol**: ERC20 token contract with controlled minting/burning
- **DSCEngine.sol**: Core protocol logic for collateral management, minting, and liquidations
- **OracleLib.sol**: Chainlink oracle wrapper with staleness checks

### Testing Suite

- **Unit Tests**: Comprehensive tests for core functionality
- **Fuzz Tests**: Invariant testing with continue-on-revert and fail-on-revert handlers
- **Mock Contracts**: Complete suite of mocks for isolated testing

## Technology Stack

- **Solidity 0.8.19**: Smart contract development
- **Foundry**: Development framework and testing
- **OpenZeppelin**: Battle-tested contract libraries
- **Chainlink**: Decentralized price oracles

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

```bash
git clone <repository-url>
cd stablecoin
forge install
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/DSCEngineTest.t.sol
```

### Deploy

```bash
# Deploy to local network
forge script script/DeployDSC.s.sol

# Deploy to testnet
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

## Security Considerations

- Always maintain overcollateralization to avoid liquidation
- Monitor health factor regularly
- Be aware of price volatility in collateral assets
- Oracle staleness can freeze the protocol (by design)

## License

MIT
