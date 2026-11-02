# Architecture

## Contracts

- **`src/DSCEngine.sol`** — all protocol logic: collateral custody, mint/burn,
  health-factor checks, liquidation, pause, timelocked risk changes, bad-debt
  ledger. Owns the DSC token (`Ownable2Step` on both sides).
- **`src/DecentralizedStableCoin.sol`** — plain ERC20 with owner-gated
  `mint`/`burn`. The engine is its owner after `acceptDscOwnership`.
- **`src/libraries/OracleLib.sol`** — Chainlink guard: rejects non-positive
  answers, incomplete rounds, future timestamps, and per-feed stale data.

## Collateral bookkeeping

Each allowlisted token has a `CollateralConfig`:

```text
priceFeed, heartbeat, liquidationThreshold, liquidationBonus,
tokenDecimals, feedDecimals, enabled
```

Pricing normalizes both sides to 18 decimals:

```text
usdValue = amount * (answer * 1e18 / 10^feedDecimals) / 10^tokenDecimals
```

Risk terms (`threshold`, `bonus`) are currently global values mirrored into
each config by `executeRiskParameters`; per-collateral risk tuning is the
natural next step (debt ceilings included).

## Liquidation flow

```text
liquidate(collateral, user, debtToCover)
  1. require HF(user) < min                    (else HealthFactorOk)
  2. debtToCover = min(debtToCover, debt[user])
  3. quote: base = usdToToken(debt); want = base * (100 + bonus) / 100
     if want > balance[user]: seize all, cover only its bonus-discounted value
  4. move collateral to liquidator; burn DSC from liquidator against user's debt
  5. if debt remains and user has NO collateral left anywhere:
       write off to s_badDebt                   (BadDebtRealized)
     elif this call exhausted the named collateral but other types remain:
       skip the HF-improvement check (progress toward full clearance)
     else: require HF improved                   (else HealthFactorNotImproved)
```

The old code did step 3 as an unchecked subtraction and always enforced the
improvement check, so positions below `(100 + bonus)%` collateralization could
never be touched. The new flow always makes progress and accounts the
remainder explicitly.

## Pause semantics (asymmetric)

```text
PAUSED blocks:  mintDsc, redeemCollateral, redeemCollateralForDsc
PAUSED allows:  depositCollateral, burnDsc, liquidate, coverBadDebt
```

Rationale: a pause must not trap borrowers (unable to save themselves) or
freeze liquidators (letting bad debt grow). Only risk-*increasing* actions
stop. `pause` is guardian-or-owner; `unpause` is owner-only.

## Risk-change lifecycle

```text
scheduleRiskParameters(t, b, m)  -- validates bounds + coupling, stores hash, eta = now + 48h
cancelRiskParameters()           -- owner clears a queued change
executeRiskParameters(t, b, m)   -- after eta, hash must match; mirrors values into configs
```

Bounds: threshold in [10, 80], bonus ≤ 20, minHealthFactor in [1e18, 2e18],
and `threshold * (100 + bonus) < 100 * 100` so liquidation stays mathematically
profitable at the margin.

## Invariant-test wiring

`test/fuzz/*` drives the engine through `StopOnRevertHandler` (fail-on-revert)
and `ContinueOnRevertHandler`, asserting solvency
(`collateral value ≥ total DSC`) and non-reverting getters. `test/poc/*` holds
one focused regression test per audit finding.
