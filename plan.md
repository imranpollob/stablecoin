# DSC Stablecoin: Portfolio Upgrade Plan

> Goal: turn this repo into a portfolio piece for a **blockchain security researcher** role.
> This review is written from the point of view of a hiring manager or recruiter at an audit firm
> (Cyfrin, Trail of Bits, OpenZeppelin, Spearbit, Code4rena/Sherlock wardens).

---

## 1. How a reviewer at an audit firm will see this repo

**First impression (about 30 seconds):**
This is the Cyfrin Updraft `foundry-defi-stablecoin` course project. The script headers still say
`@author Patrick Collins`. Security hiring managers have seen this codebase hundreds of times, and
it was also a public CodeHawks First Flight contest (`2023-07-foundry-defi-stablecoin`) with
published findings. If the repo stays as it is, the message is "finished a course", not "can find
bugs".

**What's good:**
- Foundry, unit tests, mocks, and both stop-on-revert and continue-on-revert invariant suites.
- You added Pausable and admin-tunable risk parameters, so you've started to change the course code.
- NatSpec is present and consistent.

**What hurts it:**
- Your own additions (pause, admin setters) **introduce new vulnerabilities**, and none of the
  tests catch them. A reviewer will find these within minutes, and it counts against you.
- The known findings from the original contest are still present. A security candidate should
  have found and fixed them.
- A fresh clone **does not build**. `lib/` is gitignored and no submodule gitlinks are committed,
  so `forge install` / `git submodule update` restores nothing. The Makefile also uses
  `--no-commit`, which current Forge (1.x) has removed.
- The README makes claims the code doesn't support. "No governance" sits next to an `Ownable`
  admin that can change liquidation parameters instantly. "Flexible collateral types" has no
  function to add collateral.

**The way to make it stand out:** present it as *"I took a well-known codebase, extended it, then
audited it like a client engagement. Here is the report, PoCs that fail on the vulnerable tag,
fixes, and a property-based test suite that would have caught every bug."* That is the core work
of a security researcher, and it turns the "it's a course project" objection into a strength.
Credit the original openly and make your own contribution obvious.

---

## 2. Findings (self-audit of current `master`)

Severity follows the Code4rena/CodeHawks style (High / Medium / Low / Info).
Line numbers refer to `src/DSCEngine.sol` unless stated otherwise.

| ID | Title | Severity |
|----|-------|----------|
| H-01 | Liquidation reverts when collateral ratio < 100% + bonus, so bad debt can never be cleared | High |
| H-02 | Price math assumes 18-decimal tokens and 8-decimal feeds, so WBTC (8 decimals) is mispriced by 1e10 | High |
| M-01 | `pause()` blocks repay, deposit and liquidate; users can't save positions and get liquidated on unpause | Medium |
| M-02 | Owner can change risk parameters instantly and without safe bounds, enabling a mass-liquidation rug | Medium |
| M-03 | Oracle validation incomplete: no `price > 0`, one global heartbeat, no L2 sequencer check | Medium |
| M-04 | One stale feed freezes the whole protocol, including users who hold none of that collateral | Medium |
| L-01 | `redeemCollateralForDsc` and `burnDsc` lack `nonReentrant`; external transfer happens before the health check | Low |
| L-02 | No minimum debt or close factor, so dust positions are unprofitable to liquidate | Low |
| L-03 | Constructor accepts duplicate or zero-address tokens; a duplicate double-counts collateral | Low |
| L-04 | Fee-on-transfer and rebasing tokens are credited by the requested amount, not the amount received | Low |
| L-05 | Single-step `Ownable` on both contracts | Low |
| I-01 | Divide-before-multiply precision loss in `_calculateHealthFactor` | Info |
| I-02 | Missing events (mint, burn, liquidation); `amount` is indexed in `CollateralDeposited` | Info |
| I-03 | `_amount <= 0` on `uint256` in `DecentralizedStableCoin.sol`; unused param in `OracleLib.getTimeout` | Info |
| I-04 | README and NatSpec contradict the code (governance, flexible collateral, 10% bonus is now variable) | Info |

### H-01: Liquidation is impossible once a position is under ~110% collateralised
**Where:** `liquidate()` L297-328, `_redeemCollateral()` L393.
**Issue:** The liquidator is always paid `debtToCover + bonus` worth of collateral. If the user's
collateral is worth less than that, `s_collateralDeposited[user][token] -= amount` underflows and
the call reverts. A partial liquidation that leaves the position with a worse ratio also hits
`HealthFactorNotImproved`. In a fast crash, the positions most in need of liquidation can't be
liquidated, and the bad debt stays in the system forever.
**PoC idea:** deposit 10 ETH at $2000, mint the maximum, drop ETH to $1050, then call `liquidate`
for the full debt. It reverts.
**Fix:**
- Cap the redeemed collateral at the user's balance, so the bonus shrinks to whatever is available.
- If collateral is exhausted and debt remains, write it off to a `s_badDebt` accumulator and emit
  `BadDebtRealized`. This sets up the insurance/stability pool feature in section 4.
- Skip the `HealthFactorNotImproved` check when the position is fully closed.

### H-02: Decimal assumptions break non-18-decimal collateral
**Where:** `_getUsdValue()` L466-480, `getTokenAmountFromUsd()` L575-590.
**Issue:** The code hard-codes `ADDITIONAL_FEED_PRECISION = 1e10` (assumes the feed has 8
decimals) and treats `amount` as 18 decimals. Mainnet WBTC has 8 decimals, so 1 WBTC is valued at
1e-10 of its real value, and liquidation amounts are 1e10 too large. The README advertises WBTC,
yet the mocks hide this because `ERC20Mock` uses 18 decimals.
**Fix:** when a collateral token is added, store `IERC20Metadata(token).decimals()` and
`feed.decimals()` and normalise both to 18. Add a mock with 8 decimals and a mainnet-fork test with
real WBTC.

### M-01: The emergency pause harms users and can create bad debt
**Where:** `whenNotPaused` on `depositCollateral`, `burnDsc`, `liquidate`, `redeemCollateralForDsc`.
**Issue:** While the protocol is paused, prices keep moving. Users can't add collateral or repay,
and liquidators can't liquidate. On `unpause()`, MEV bots liquidate users who never had a chance to
fix their positions, and positions that went underwater during the pause become bad debt.
**Fix:** use an asymmetric pause. Pause only the actions that add risk (`mintDsc`,
`redeemCollateral`). Keep `depositCollateral`, `burnDsc` and `liquidate` always open. If you
also want to pause liquidations, add a post-unpause **liquidation grace period** (as Aave v3 does)
so users get time to recover.

### M-02: Centralised, unbounded risk parameters
**Where:** `setLiquidationThreshold` L184, `setLiquidationBonus` L191, `setMinHealthFactor` L199.
**Issue:** The owner can take three harmful actions in a single transaction:
- Set the threshold to `1`, or set `minHealthFactor` to `type(uint256).max`. This makes every
  position liquidatable, and the owner can then liquidate them all for the bonus.
- Set the threshold to `0`. This makes every health factor 0.
- Set threshold and bonus so that `threshold * (100 + bonus) >= 100 * 100`. Liquidation then
  becomes unprofitable or reverts at the margin.

There is no timelock, and nothing protects existing positions.
**Fix:** enforce hard min/max bounds plus a coupling check between threshold and bonus. Route
parameter changes through a `TimelockController` (e.g. 48h), make the owner a multisig, and
document the trust assumptions. Changes that only make the protocol safer, such as lowering the
mint LTV, may take effect immediately. Changes that make it riskier must wait for the timelock.

### M-03: Oracle validation gaps
**Where:** `OracleLib.staleCheckLatestRoundData` and `uint256(price)` casts.
**Issue:**
- A negative or zero `answer` is cast straight to `uint256`. A negative answer wraps to a huge
  price.
- One global `TIMEOUT` of 3h ignores per-feed heartbeats (1h for many mainnet feeds, 24h for
  others).
- There is no Arbitrum/OP/Base sequencer uptime check, which matters if you deploy to an L2.
- `answeredInRound` is deprecated.
- There is no `minAnswer`/`maxAnswer` circuit-breaker awareness (the LUNA-style failure).

**Fix:** set a per-feed heartbeat in the collateral config, `require(answer > 0)`, add an optional
sequencer uptime feed with a grace period, and add an optional bounds check.

### M-04: Oracle freeze is global
**Where:** `getAccountCollateralValue()` L560-569.
**Issue:** The loop queries every feed, even for tokens the user has a balance of 0 in. If the
WBTC feed goes stale, ETH-only users can't mint, withdraw, *or be liquidated*.
**Fix:** `if (amount == 0) continue;` before the oracle call. Consider a fallback oracle (Uniswap v3
TWAP or Pyth) with a deviation check against the primary.

### L-01 to L-05 and Info
- **L-01:** add `nonReentrant` to `redeemCollateralForDsc` and `burnDsc`. Today it is harmless with
  plain ERC20s, but becomes exploitable once hook tokens (ERC777/ERC1363) are allowed as collateral.
- **L-02:** add a `MIN_DEBT` floor (a position after any action must be either 0 or at least
  `MIN_DEBT`) and a close factor (e.g. at most 50% per call when HF is above 0.95).
- **L-03:** in the constructor, reject `address(0)`, a duplicate token, or a feed already set.
- **L-04:** credit `balanceAfter - balanceBefore`, or explicitly document that such tokens are
  unsupported and enforce an allowlist.
- **L-05:** use `Ownable2Step` on both contracts.
- **I-01 to I-04:** compute `collateral * threshold * PRECISION / (LIQUIDATION_PRECISION * debt)`
  in one expression. Add `DscMinted`, `DscBurned` and `Liquidated(liquidator, user, collateral,
  debtCovered, collateralSeized)` events. Fix the README.

> Before publishing: **write a failing PoC for every finding above first.** Severity claims without
> a PoC are the main thing reviewers distrust in junior portfolios. Also compare your list to the
> public CodeHawks results for this codebase and note in the report which findings you found
> independently. That calibration is exactly what auditors care about.

---

## 3. Roadmap

### Phase 0: Repo hygiene (½ day) — DONE (2026-11-02, see WORKLOG.md)
- [x] Commit real submodules (removed `lib/` from `.gitignore`, gitlinks committed).
      Fresh `git clone --recurse-submodules && forge build && forge test` works.
- [x] Fix the Makefile: dropped `--no-commit`, replaced the auto-committing `remove` target.
- [x] README credits the original (Cyfrin Updraft / Patrick Collins) and lists my contributions.
- [x] Tagged base commit `5525018` as **`v0-vulnerable`**; fixed code tagged `v1-fixed`.
- [x] GitHub Actions CI: `forge fmt --check`, `forge build --sizes`, `forge test`, Slither.

### Phase 1: PoCs, then fixes (2-3 days)
- [x] `test/poc/` with one file per finding (H-01, H-02, M-01, M-02, M-03, M-04,
      L-01, L-03, L-04, L-05, I-01), each with root cause / impact. L-02 intentionally
      left as documented accepted risk (see self-audit).
- [x] Fixed in order H → M → L (core fixes predated this session; new PoCs committed
      in scoped chunks — one-commit-per-finding was not recoverable retroactively).
- [x] Each PoC is a regression test against the fixed code.
- [x] Tag **`v1-fixed`**.

### Phase 2: Testing that demonstrates security skill (3-5 days)
This is the most important phase for a research role.
- [x] **Properties spec** (`docs/properties.md`): 13 invariants in plain English, each
      mapped to its test — covers all six example properties from the draft
      (debt conservation, custody, HF gates, liquidatability, fresh-oracle getters, solvency).
- [ ] Rewrite the handlers with **ghost variables**, price-movement actions, liquidation, pause and
      unpause, warp time, and multiple actors. (Existing handlers kept; extension tracked.)
- [ ] Show in the README that **the invariant suite fails on `v0-vulnerable`** and passes on
      `v1-fixed`. (H-01/M-04 properties fail on v0 by construction; automated v0-run tracked.)
- [ ] **Medusa or Echidna** campaign for the same properties, with the config committed. (Tracked.)
- [ ] **Halmos** (symbolic) checks for the pure math. (Tracked.)
- [ ] **Mainnet fork tests** with real Chainlink feeds and real WBTC (proves the H-02 fix). (Tracked — needs RPC.)
- [ ] **Mutation testing** (Gambit or `vertigo-rs`). (Tracked.)
- [ ] Stretch goal: Certora CVL spec for invariants 1 and 2. (Tracked.)

### Phase 3: Features (pick 3-4; each should add *interesting attack surface* you then defend)
| Priority | Feature | Why it signals security skill |
|---|---|---|
| ★★★ | **Per-collateral risk config** (`struct CollateralConfig { feed, decimals, heartbeat, ltv, liqThreshold, liqBonus, debtCeiling }`) + timelocked `addCollateral` | Fixes H-02/M-03 properly; debt ceilings limit damage from any one asset |
| ★★★ | **Bad-debt handling**: insurance fund or stability pool (Liquity-style) that absorbs bad debt | Fixes H-01 at the design level; shows you understand insolvency, not just reverts |
| ★★★ | **Role-based governance**: `AccessControl` with `GUARDIAN` (pause only), `TimelockController` (params), `Ownable2Step` | Fixes M-01/M-02; a common audit theme |
| ★★ | **Robust oracle module**: primary Chainlink + fallback TWAP/Pyth, deviation check, sequencer uptime feed | Oracle manipulation is the #1 DeFi loss category |
| ★★ | **Stability fee** (rate accumulator, as in Maker `rate`/`chi`) | Introduces interest math and rounding-direction pitfalls; good for Halmos |
| ★★ | **Dutch-auction liquidations** (Maker Clipper-style) instead of a fixed bonus | Removes the fixed-bonus cliff; liquidation design shows up often in interviews |
| ★ | **ERC-3156 flash mint** for DSC with a fee and a supply cap | Deliberately adds flash-loan attack surface; write tests for the attacks you defend against |
| ★ | **EIP-2612 `permit`** on DSC | Small; brings signature-replay and front-running of `permit` topics |

Avoid building a frontend. It adds no signal for this role.

### Phase 4: Deliverables reviewers will actually read (1-2 days)
- [x] **`audits/self-audit-v0.md`**: report with summary, scope (`5525018`),
      methodology, risk classification, and per-finding fix + PoC links.
- [x] **`docs/threat-model.md`**: actors, trust assumptions, assets at risk, accepted risks.
- [x] **`docs/architecture.md`**: contract interactions and liquidation flow (text diagrams).
- [x] **Static analysis triage** (`audits/static-analysis.md`): Slither output, every item
      triaged with a reason.
- [ ] **A write-up or blog post**: "Auditing my own stablecoin: 2 Highs I introduced and how
      invariant testing caught them." (Tracked.)
- [x] **README rewrite**: leads with security work — findings table with links, test commands,
      static-analysis result, known limitations. (Coverage/mutation scores tracked.)

---

## 4. Suggested final repo layout
```
src/
  DSCEngine.sol
  DecentralizedStableCoin.sol
  oracle/OracleModule.sol            # per-feed heartbeat, sequencer, fallback
  governance/                        # timelock + roles wiring
test/
  unit/  fork/  poc/  invariant/  symbolic/
audits/
  self-audit-v0.md
  static-analysis.md
docs/
  architecture.md  threat-model.md  properties.md
.github/workflows/ci.yml
medusa.json / echidna.yaml
```

---

## 5. Interview talking points this project should let you answer
- "Walk me through a bug you introduced yourself and how you found it." (M-01, M-02)
- "Why can't you liquidate an underwater position here, and how do real protocols handle bad
  debt?" (H-01: Maker surplus buffer, Liquity stability pool, Aave deficit accounting)
- "What can go wrong with Chainlink?" (stale data, heartbeats, negative answer, min/max answer,
  L2 sequencer, decimals)
- "What invariants would you write for a CDP protocol, and which one caught the bug?"
- "Which direction should each division round, and why?"
- "How does a pause mechanism create risk instead of reducing it?"

---

## 6. Priority order if time is short
1. Phase 0 (it must build from a clean clone).
2. PoCs and fixes for H-01, H-02, M-01, M-02.
3. An invariant suite that fails on `v0-vulnerable`.
4. Self-audit report + README rewrite.
5. Everything else.
