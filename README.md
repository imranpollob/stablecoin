# Foundry DeFi Stablecoin Protocol

This is a decentralized stablecoin protocol built with Foundry (Solidity) that maintains a 1:1 USD peg through overcollateralization with WETH and WBTC, inspired by MakerDAO's DSS system.

## Table of Contents
- [Architecture](#architecture)
- [Overcollateralized Stablecoin System Features](#overcollateralized-stablecoin-system-features)
- [Setup](#setup)
- [Testing](#testing)
- [Deployment](#deployment)

## Architecture

The protocol consists of two main contracts:

1. **DSCEngine**: Core logic contract handling collateral deposits, stablecoin minting, liquidations, and health factor calculations
2. **DecentralizedStableCoin (DSC)**: ERC20 token contract that represents the stablecoin

## Features

### 1. Overcollateralization Ratio (200% requirement)

Maintains a strict 200%+ collateralization requirement to ensure system stability and protect against market volatility.

**Code Implementation:**
```solidity
uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
uint256 private constant MIN_HEALTH_FACTOR = 1e18;
```

The `LIQUIDATION_THRESHOLD = 50` means 50% (or 0.5), meaning you must have collateral worth at least 2x the value of the DSC you're minting.

### 2. Collateral Deposit and Minting Logic

Enables users to deposit supported collateral tokens and mint new stablecoins in a secure manner.

**Code Implementation:**
```solidity
function depositCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) public moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress) {
    s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
    emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
    if (!success) {
        revert DSCEngine__TransferFailed();
    }
}

function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
    s_DSCMinted[msg.sender] += amountDscToMint;
    _revertIfHealthFactorIsBroken(msg.sender);
    bool minted = i_dsc.mint(msg.sender, amountDscToMint);
    if (minted != true) {
        revert DSCEngine__MintFailed();
    }
}
```

### 3. Health Factor Calculation/Validation

Critical safety mechanism that validates collateralization ratios in real-time.

**Code Implementation:**
```solidity
function _healthFactor(address user) private view returns (uint256) {
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
}

function _calculateHealthFactor(
    uint256 totalDscMinted,
    uint256 collateralValueInUsd
) internal pure returns (uint256) {
    if (totalDscMinted == 0) return type(uint256).max;
    uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
}
```

The health factor formula: `(collateralValueInUsd * 50%) / totalDscMinted` must be >= 1e18 to be valid.

### 4. Collateral Value Calculation

Converts collateral tokens to USD value using Chainlink price feeds with proper decimal adjustments.

**Code Implementation:**
```solidity
function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
}
```

### 5. Price Feed Integration with Stale Check

Prevents the use of outdated price data to maintain system security.

**Code Implementation:**
```solidity
function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
    public view returns (uint80, int256, uint256, uint256, uint80) {
    (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
        chainlinkFeed.latestRoundData();

    if (updatedAt == 0 || answeredInRound < roundId) {
        revert OracleLib__StalePrice();
    }
    uint256 secondsSince = block.timestamp - updatedAt;
    if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();
    return (roundId, answer, startedAt, updatedAt, answeredInRound);
}
```

### 6. Automatic Health Factor Validation

Automatically validates that all actions maintain safe collateralization levels.

**Code Implementation:**
```solidity
function _revertIfHealthFactorIsBroken(address user) internal view {
    uint256 userHealthFactor = _healthFactor(user);
    if (userHealthFactor < MIN_HEALTH_FACTOR) {
        revert DSCEngine__BreaksHealthFactor(userHealthFactor);
    }
}
```

This function is called after `depositCollateral`, `mintDsc`, and other operations to ensure the overcollateralization requirement is maintained.

### 7. Stablecoin Minting with Access Control

Secure minting mechanism that only allows the DSCEngine contract to create new DSC tokens.

**Code Implementation:**
```solidity
function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
    if (_to == address(0)) {
        revert DecentralizedStableCoin__NotZeroAddress();
    }
    if (_amount <= 0) {
        revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
    }
    _mint(_to, _amount);
    return true;
}
```

The `onlyOwner` modifier ensures only the DSCEngine contract can mint new DSC tokens, ensuring every DSC is always backed by collateral.

## Setup

Make sure you have Foundry installed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies:

```bash
forge install
```

## Testing

Run the test suite:

```bash
forge test
```

## Deployment

Deploy to a testnet:

```bash
make deploy ARGS="--network sepolia"
```

## Security Features

- Overcollateralization requirement (200%+)
- Liquidation mechanism with 10% bonus
- Health factor monitoring
- Oracle staleness protection (3-hour timeout)
- Reentrancy guards
- Comprehensive validation on all operations

## Supported Collateral

- WETH (Wrapped Ether)
- WBTC (Wrapped Bitcoin)