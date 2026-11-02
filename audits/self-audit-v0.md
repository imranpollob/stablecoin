# Self-Audit: DSC Stablecoin (`v0-vulnerable` → fixed)

| Field | Value |
|---|---|
| Scope | `src/DSCEngine.sol`, `src/DecentralizedStableCoin.sol`, `src/libraries/OracleLib.sol` at [`5525018`](https://github.com/imranpollob/stablecoin/commit/5525018b6568013b6aae0491fdb3d0eeea99a202) (tag `v0-vulnerable`) |
| Methodology | Manual review, Slither, Foundry unit + invariant tests, per-finding PoCs |
| Risk scale | Code4rena/CodeHawks style: High / Medium / Low / Informational |
| Status | All Highs and Mediums fixed; L-02 and L2-sequencer noted as accepted/future work |

Original codebase: Cyfrin Updraft `foundry-defi-stablecoin` course project
(author Patrick Collins), itself the subject of CodeHawks First Flight
`2023-07-foundry-defi-stablecoin`. Findings below are my own; where they
overlap published contest results is noted per finding.

## Findings

### H-01 — Liquidation bricks below (100 + bonus)% collateralization [High, fixed]

`liquidate` paid the liquidator `debtToCover + bonus` out of the user's balance
with an unchecked subtraction, and unconditionally required the health factor to
improve. Once collateral fell below debt-plus-bonus, every liquidation reverted
and the bad debt could never be cleared.
*Fix:* cap the seizure at the user's balance (bonus shrinks to what exists);
write any remaining debt to `s_badDebt` with `BadDebtRealized`; skip the
improvement check when a collateral type is exhausted so follow-up liquidations
make progress. *PoC:* `test/poc/H01_LiquidationUnderflow.t.sol`.

### H-02 — Price math assumes 18-decimal tokens and 8-decimal feeds [High, fixed]

Hard-coded `ADDITIONAL_FEED_PRECISION = 1e10` mispriced any collateral whose
decimals differ (8-decimal WBTC valued at 1e-10 of reality). The mocks hid this
by using 18 decimals everywhere.
*Fix:* store `tokenDecimals`/`feedDecimals` per collateral at allowlisting and
normalize both to 18. *PoC:* `test/poc/H02_CollateralDecimals.t.sol` (8-decimal
mock valued exactly).

### M-01 — Pause traps users and blocks liquidations [Medium, fixed]

`whenNotPaused` on deposit, repay, and liquidation let prices move during a
pause while nobody could react; MEV bots harvested users at `unpause`.
*Fix:* asymmetric pause — only `mintDsc` and collateral withdrawal stop;
`depositCollateral`, `burnDsc`, and `liquidate` stay open. Unpause is
owner-only. *PoC:* `test/poc/M01_AsymmetricPause.t.sol`.

### M-02 — Instant, unbounded risk parameters [Medium, fixed]

The owner could set threshold to 0/1 (brick or liquidate everyone) or bonus
combinations that make liquidation unprofitable, in one transaction.
*Fix:* 48h schedule→execute timelock, hard bounds (threshold [10,80], bonus ≤
20, minHF in [1e18, 2e18]) plus a threshold/bonus coupling check.
*PoC:* `test/poc/M02_RiskTimelock.t.sol`.

### M-03 — Oracle validation gaps [Medium, fixed]

Negative/zero answers cast to `uint256` (a negative wraps into a huge price);
single global 3h timeout; no round-completeness check; no sequencer check.
*Fix:* `require(answer > 0)`, per-feed heartbeat, `answeredInRound < roundId`
rejection. Sequencer uptime check deferred to L2 deployment.
*PoC:* `test/poc/M03_OracleValidation.t.sol` (zero + negative cases).

### M-04 — One stale feed freezes the whole protocol [Medium, fixed]

`getAccountCollateralValue` queried every feed even for zero balances, so an
ETH-only user was frozen by a stale WBTC feed.
*Fix:* skip zero-balance tokens before touching the oracle.
*PoC:* `test/poc/M04_UnusedStaleFeed.t.sol`.

### L-01 — Missing `nonReentrant` on two settlement paths [Low, fixed]

`redeemCollateralForDsc` and `burnDsc` lacked the guard (harmless with plain
ERC20s, exploitable with hook tokens).
*Fix:* `nonReentrant` on all settlement entry points.
*PoC:* `test/poc/L01_ReentrancyGuard.t.sol` (callback token; asserts the guard's
revert reason so the test fails on unguarded code).

### L-02 — No minimum debt or close factor [Low, accepted]

Dust positions may cost more to liquidate than the bonus pays.
*Decision:* accepted. Liquidation is permissionless and the bonus scales with
size; a `MIN_DEBT` floor would add mint-path griefing surface. Revisit with a
stability pool.

### L-03 — Constructor accepted duplicates/zero addresses [Low, fixed]

A duplicate token double-counted collateral. Now rejected (`ZeroAddress`,
`DuplicateCollateral`). *PoC:* `test/poc/L03_ConstructorValidation.t.sol`.

### L-04 — Fee-on-transfer credited by nominal amount [Low, fixed]

Now credits the measured balance delta (`balanceAfter - balanceBefore`).
*PoC:* `test/poc/L04_FeeOnTransferAccounting.t.sol`.

### L-05 — Single-step ownership [Low, fixed]

`Ownable2Step` on engine and DSC. *PoC:* `test/poc/L05_TwoStepOwnership.t.sol`.

### Informational (fixed)

I-01 divide-before-multiply → `Math.mulDiv` with protocol-favoring rounding
(`I01_HealthFactorPrecision`); I-02 missing events → `DscMinted`/`DscBurned`/
`Liquidated`/`BadDebt*` events, `amount` un-indexed; I-03 dead code (`_amount
<= 0` on `uint256`, unused `getTimeout` param); I-04 README/NatSpec rewritten
to describe the system as built.

## Invariant results

`forge test` (Foundry 1.4.1): all suites pass on the fixed code, including the
solvency invariant (`collateral value ≥ total DSC`) and non-reverting getters
under both fail-on-revert and continue-on-revert handlers. The H-01 and M-04
properties fail on `v0-vulnerable` by construction (underflow revert; stale-feed
revert on zero balances) and pass after the fix.

## Limitations

Unaudited experimental code; no external review. No insurance fund backing
`s_badDebt`; no fallback oracle; no L2 sequencer handling. Fork tests against
real feeds/WBTC, Medusa/Echidna campaigns, and Halmos symbolic checks are
tracked as follow-ups in `plan.md`.
