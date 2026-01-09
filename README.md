# Crypto Stablecoin

A decentralized, overcollateralized, and algorithmically stablecoin protocol built with Foundry. This system maintains a 1:1 USD peg for the Stablecoin (DSC) using exogenous collateral (WETH & WBTC), inspired by the MakerDAO DSS architecture.

This protocol creates a stablecoin (DSC) anchored to the US Dollar. The system ensures stability through:
1.  **Overcollateralization**: All minted DSC is backed by more than 100% value in collateral (WETH/WBTC).
2.  **Liquidation Mechanism**: Undercollateralized positions are liquidated to solvency, incentivizing liquidators with a bonus.
3.  **Algorithmic Control**: No centralized entity controls the peg; it is maintained by market incentives and protocol rules.

## ✨ Key Features

-   **Dollar Pegged**: 1 DSC ≈ $1 USD.
-   **Multi-Collateral**: Supports WETH and WBTC.
-   **Overcollateralized**: Enforces a minimum collateralization ratio (default 200%).
-   **Pausable (Emergency Stop)**: Owner can pause contract operations in emergencies.
-   **Dynamic Parameters**: Risk parameters (Liquidation Threshold, Bonus, Health Factor) can be adjusted by governance without redeployment.
-   **Oracle Integrated**: Uses Chainlink Data Feeds for secure, real-time pricing.

## 🏗 Architecture

The system relies on two core smart contracts:

### 1. `DSCEngine.sol` (The Core)
The engine handles all logic:
-   **Deposits**: Users deposit WETH/WBTC.
-   **Minting**: Users mint DSC against their collateral.
-   **Health Factor**: Calculates user solvency. If `Health Factor < 1`, the user is liquidatable.
-   **Liquidations**: Allows third parties to pay off debt for undercollateralized users in exchange for discounted collateral.

### 2. `DecentralizedStableCoin.sol` (The Token)
-   An ERC20 Burnable token owned by `DSCEngine`.
-   Only `DSCEngine` has the authority to mint or burn tokens.

## 🛡 Security & Governance

The system facilitates "Solid MVP" security standards:

-   **Emergency Stop**: The `pause()` function halts `deposit`, `mint`, `redeem`, and `liquidate` actions if a bug or oracle failure is detected.
-   **Dynamic Governance**: The contract owner (or DAO) can tune:
    -   `Liquidation Threshold`: (Default 50%) Level at which collateral is valued.
    -   `Liquidation Bonus`: (Default 10%) Reward for liquidators.
    -   `Min Health Factor`: (Default 1e18) Minimum solvency ratio.
-   **Reentrancy Protection**: All state-changing external functions use `nonReentrant`.

## 🚀 Getting Started

### Prerequisites
-   [Foundry](https://getfoundry.sh/)
-   [Git](https://git-scm.com/)

### Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/imranpollob/stablecoin
    cd stablecoin
    ```

2.  Install dependencies:
    ```bash
    forge install
    ```

3.  Build the project:
    ```bash
    forge build
    ```

## 🛠 Usage

### Local Development (Anvil)
Start a local blockchain node:
```bash
anvil
```

Deploy to local node:
```bash
forge script script/DeployDSC.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <PRIVATE_KEY>
```

## 🧪 Testing

The project has comprehensive test coverage including unit tests and invariant (fuzz) tests.

Run all tests:
```bash
forge test
```

Run specific test file:
```bash
forge test --mt <TEST_FUNCTION_NAME>
```

Get test coverage report:
```bash
forge coverage
```

## 📦 Deployment

### Deploy to Sepolia Testnet
Create a `.env` file with `SEPOLIA_RPC_URL` and `PRIVATE_KEY`.

```bash
make deploy ARGS="--network sepolia"
```

## 📄 License

This project is licensed under the MIT License.