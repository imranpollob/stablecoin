# Protocol properties and verification scope

This specification separates tested properties from design goals and residual
risks. Passing a bounded fuzz campaign is evidence within its model, not a proof
for every token, oracle, actor, or execution sequence.

## Stateful campaign model

Both campaigns use four known borrower addresses, mock collateral tokens with
standard transfers, fresh positive mock prices, and default risk parameters.
They begin with funded positions and nonzero DSC supply. Explicit selector lists
exclude inherited test utilities and getters from the generated action set.
A separate liquidator is funded with DSC transferred from the borrowers.

| Campaign | Actions | Reverts | Assertions |
| --- | --- | --- | --- |
| `StopOnRevertInvariants` | Deposit, mint, repay, redeem, transfer | Unexpected; amounts are bounded to valid preconditions | Debt conservation, collateral custody, borrower health at fixed prices |
| `ContinueOnRevertInvariants` | Same actions with adversarial requests, plus price updates, liquidation, bad-debt coverage | Allowed for invalid requests | Debt conservation and collateral custody |

The adversarial setup first exhausts one borrower's collateral and realizes bad
debt. Price changes stay positive and do not advance time. Invalid observations,
staleness, pause, callbacks, and governance are covered separately by targeted
tests, rather than composed into the stateful campaigns.

Defaults: **64 runs × 64 calls**. CI profile: **256 runs × 128 calls**.

## Asserted accounting properties

1. **Active debt equals borrower debt.** For the campaign's complete actor set,
   `sum(userDebt) == engine.getTotalActiveDebt()`.
2. **Accounted debt equals supply.** `sum(userDebt) + badDebt == dsc.totalSupply()`.
   Liquidation moves uncovered residual debt into bad debt rather than deleting
   the obligation. Repayment and bad-debt coverage burn matching DSC.
3. **Collateral ledger matches custody in the model.** For each mock token,
   `sum(userDeposits) == token.balanceOf(engine)`.
4. **Valid user actions preserve health at fixed prices.** Every actor remains at
   or above the minimum health factor in the fail-on-revert campaign.

Properties 1–3 are checked after calls in both campaigns; property 4 applies
only to the fixed-price campaign. A real account can become unhealthy because
prices or risk parameters change without borrower action.

The custody equality assumes no unsolicited transfers or rebases. With direct
token donations, the intended backing relation is `custody >= creditedDeposits`.
Neither campaign models fee-on-transfer, rebasing, or arbitrary malicious tokens.

## Focused regression evidence

| Area | Tested behavior | Evidence |
| --- | --- | --- |
| Liquidation | A 10 ETH / 10,000 DSC position settles after a price fall to $1,050; residual debt is recorded | [H-01](../test/poc/H01_LiquidationUnderflow.t.sol) |
| Decimals | One 8-decimal collateral token is valued and converted back using an 8-decimal feed | [H-02](../test/poc/H02_CollateralDecimals.t.sol) |
| Pause | Deposits and repayment remain available; unit suite checks blocked mint/withdrawal and role permissions | [M-01](../test/poc/M01_AsymmetricPause.t.sol), [controls](../test/unit/DSCEnginePausableTest.t.sol) |
| Risk changes | Delay, bounds, exact tuple, cancellation, and authorization | [M-02](../test/poc/M02_RiskTimelock.t.sol), [controls](../test/unit/DSCEnginePausableTest.t.sol) |
| Oracle observations | Exact rejection of zero/negative prices; stale and future timestamps rejected | [M-03](../test/poc/M03_OracleValidation.t.sol), [oracle unit tests](../test/unit/OracleLibTest.t.sol) |
| Unrelated stale feed | A stale feed for zero held balance does not block an ETH-only position | [M-04](../test/poc/M04_UnusedStaleFeed.t.sol) |
| Callback defense | Reentrant settlement calls hit the guard | [L-01](../test/poc/L01_ReentrancyGuard.t.sol) |
| Constructor | Duplicate collateral rejected | [L-03](../test/poc/L03_ConstructorValidation.t.sol) |
| Deposit credits | A 10% transfer fee reduces credited collateral accordingly | [L-04](../test/poc/L04_FeeOnTransferAccounting.t.sol) |
| Ownership | Engine and token require ownership acceptance | [L-05](../test/poc/L05_TwoStepOwnership.t.sol) |
| Token supply | Holders and approved spenders cannot use `burnFrom` outside engine accounting; engine repayment still works | [L-06](../test/poc/L06_DirectBurn.t.sol) |
| Rounding | A selected fractional health-factor example floors, and zero debt returns the sentinel | [I-01](../test/poc/I01_HealthFactorPrecision.t.sol) |

## Unproven or open properties

- Liquidation liveness for arbitrary multi-collateral positions, dust amounts, and severe price shocks.
- Complete decimal/rounding correctness across every supported token/feed pair.
- Economic solvency or peg stability under arbitrary market moves.
- Accounting under nonstandard outgoing transfer fees, rebases, blocklists, or token upgrades.
- Campaign composition with governance changes, pause, oracle outages, and callbacks.
- Compatibility of the current regression suite with historical vulnerable interfaces.

These gaps are tracked in the [roadmap](../plan.md) and [threat model](threat-model.md).
