# DSC Stablecoin security review — baseline v0

| Field | Scope |
| --- | --- |
| Baseline | [`5525018`](https://github.com/imranpollob/stablecoin/commit/5525018b6568013b6aae0491fdb3d0eeea99a202), tag `v0-vulnerable` |
| Contracts | `DSCEngine.sol`, `DecentralizedStableCoin.sol`, `libraries/OracleLib.sol` |
| Approach | Manual review, targeted Foundry regressions, unit tests, and static analysis |
| Severity | Self-assessed High / Medium / Low / Informational; no independent adjudication |
| Current evidence | Tests linked below target the current interfaces; see [properties](../docs/properties.md) for campaign boundaries |

This internal review documents protocol failure modes, implemented mitigations,
and remaining assumptions. Findings and severity ratings are maintained with
executable regression evidence. Independent review has not been performed.

The historical `v1-fixed` tag records an earlier remediation snapshot. It does
not include every subsequent change. The current tests are not guaranteed to
compile against the baseline; a compatible differential harness is future work.

## High severity

### H-01 — Insufficient collateral can block liquidation

**Trigger and impact.** The requested collateral seizure includes a bonus. When
it exceeds the borrower's balance, checked subtraction reverts. An unconditional
health-factor improvement requirement can also prevent progress on deeply
underwater positions, delaying settlement when debt is already distressed.

**Mitigation.** Cap the seizure at the selected balance and cover only its
bonus-discounted value. If all collateral is exhausted, move remaining debt to
an explicit bad-debt ledger. If only one type is exhausted, permit subsequent
settlement without requiring this step to improve health.

**Evidence.** [H-01 regression](../test/poc/H01_LiquidationUnderflow.t.sol):
10 ETH backs 10,000 DSC, then the price falls from $2,000 to $1,050. Settlement
exhausts collateral and preserves the debt/supply accounting identity.

**Residual risk.** Recording bad debt does not eliminate the loss. Dust rounding,
oracle failure, liquidity, gas costs, and liquidator account checks can still
prevent settlement. This is not a universal liquidation-liveness proof.

### H-02 — Fixed decimal assumptions misprice collateral

**Trigger and impact.** Treating token amounts as 18 decimals and feed answers as
8 decimals undervalues an 8-decimal token by a factor of `1e10`. Mocks with only
18-decimal token balances hide the mismatch.

**Mitigation.** Cache token/feed decimals at construction and normalize USD
values. Reject token/feed decimals above 18.

**Evidence.** [H-02 regression](../test/poc/H02_CollateralDecimals.t.sol):
`1e8` units of an 8-decimal token at $30,000 is worth `30_000e18`, and conversion
back returns `1e8`. Broader decimal-pair and rounding exploration remains open.

## Medium severity

### M-01 — Symmetric pause blocks protective actions

Pausing deposits, repayment, and liquidation prevents users from reducing debt
while collateral prices continue to move. The current pause blocks minting and
withdrawals while preserving standalone deposits, repayment, and liquidation.
Other checks still apply, and withdrawals remain blocked after repayment.

Evidence: [M-01 regression](../test/poc/M01_AsymmetricPause.t.sol) and
[pause/access-control unit tests](../test/unit/DSCEnginePausableTest.t.sol).

### M-02 — Immediate and unbounded risk changes

An owner could change liquidation terms without notice or safe bounds. The
engine now enforces a 48-hour schedule/execute delay, tuple matching, cancellation,
threshold `[10,80]`, bonus `[0,20]`, minimum factor `[1e18,2e18]`, and a
threshold/bonus coupling check.

Evidence: [M-02 regression](../test/poc/M02_RiskTimelock.t.sol) and
[control unit tests](../test/unit/DSCEnginePausableTest.t.sol). Owner trust remains;
the delay does not guarantee users can exit during pauses or oracle failures.

### M-03 — Oracle observations are insufficiently validated

Non-positive prices and incomplete observations must not enter collateral math.
`OracleLib` rejects non-positive prices, incomplete rounds, zero/future timestamps,
and observations older than the supplied heartbeat.

Evidence: [M-03 regressions](../test/poc/M03_OracleValidation.t.sol) assert exact
errors for zero and negative answers; [oracle tests](../test/unit/OracleLibTest.t.sol)
exercise stale and future timestamps. Each config stores a heartbeat but currently
receives the same three-hour default. No setter, sequencer check, fallback oracle,
or price-deviation circuit breaker is implemented.

### M-04 — Unused stale feeds block unrelated accounts

Querying every feed before checking the account's token balance lets an unused
stale feed block valuation. Current valuation skips zero-balance tokens.

Evidence: [M-04 regression](../test/poc/M04_UnusedStaleFeed.t.sol). A stale feed
for collateral actually held by the account can still block health checks.

## Low severity

| ID | Observation | Current treatment and evidence |
| --- | --- | --- |
| L-01 | Inconsistent settlement reentrancy guards | Guards applied to settlement paths; [callback regression](../test/poc/L01_ReentrancyGuard.t.sol) pins the guard error. This is defense-in-depth evidence, not a demonstrated theft exploit. |
| L-02 | Dust debt may be uneconomical to liquidate | Open design issue: no minimum debt or close-factor policy; permissionless liquidation alone does not ensure profitability. |
| L-03 | Constructor accepts duplicate/zero addresses | Reject zero addresses and duplicate tokens; [regression](../test/poc/L03_ConstructorValidation.t.sol) exercises duplicates. |
| L-04 | Nominal deposit credits ignore transfer fees | Credit measured balance delta; [regression](../test/poc/L04_FeeOnTransferAccounting.t.sol) checks a 10% ingress fee. Full support for arbitrary fee/rebasing tokens is not claimed. |
| L-05 | Single-step ownership can strand control | Two-step ownership on engine and DSC; [regression](../test/poc/L05_TwoStepOwnership.t.sol) exercises acceptance. |

A later review identified **L-06**, inherited `burnFrom` bypassing engine debt
accounting. It is documented separately in the [accounting follow-up](review-2026-11.md).

## Informational observations

- **I-01:** health-factor precision and conservative rounding. Current
  [regression](../test/poc/I01_HealthFactorPrecision.t.sol) checks a fractional
  example and the zero-debt sentinel; it is not an exhaustive error-bound proof.
- **I-02:** settlement observability. The engine emits deposit, redemption,
  mint, burn, liquidation, and bad-debt events.
- **I-03:** redundant unsigned-value checks and legacy helper cleanup.
- **I-04:** documentation must reflect actual governance, collateral, and oracle
  capabilities. The current README, architecture, and threat model describe
  implemented behavior and distinguish future work.

## Verification and limitations

Current execution results and test commands are recorded in the
[accounting follow-up](review-2026-11.md). The [property specification](../docs/properties.md)
defines the bounded campaigns. The [static-analysis report](static-analysis.md)
records actual detector severities and manual triage; tool output alone is not a
security conclusion.

No fork campaign, symbolic proof, mutation score, independent audit, or economic
solvency guarantee is claimed. The [roadmap](../README.md#development-roadmap) tracks those gaps.
