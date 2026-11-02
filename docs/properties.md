# Protocol Properties (Invariant Spec)

Plain-English properties the DSCEngine must uphold. Each maps to a test in
`test/fuzz/` or `test/poc/`. A property that held on the vulnerable tag is
marked; the rest fail on `v0-vulnerable` and pass on the fixed code.

## Accounting

1. **Debt conservation.** `sum(s_DSCMinted[u]) + s_badDebt == dsc.totalSupply()`.
   Realized bad debt stays in the accounting identity instead of vanishing.
   Covered by `H01_LiquidationUnderflow`.
2. **Collateral custody.** `collateral.balanceOf(engine) ==
   sum(s_collateralDeposited[u][collateral])` per token. The engine never holds
   unaccounted tokens and never owes tokens it does not hold. (Engine DSC
   balance is transient: deposits on burn, burns immediately.)
3. **No phantom debt.** `s_totalActiveDebt == sum(s_DSCMinted[u])` at all times;
   `coverBadDebt` only reduces `s_badDebt` and burns real DSC.

## Health factor

4. **No under-backed positions by user action.** No user-initiated action
   (mint, redeem, full exit) can leave that user's health factor below
   `minHealthFactor`, except `depositCollateral` (always safe) and `burnDsc`
   (repayment). Enforced by `_revertIfHealthFactorIsBroken`.
5. **Liquidation always possible when it matters.** If a user's health factor is
   below minimum and their debt is non-zero, `liquidate` succeeds for *some*
   `debtToCover` on *some* collateral. This is the property H-01 violated: the
   old code reverted once collateral fell below `debt + bonus`.
6. **Health factor monotonicity in repayment.** `burnDsc` and `depositCollateral`
   never decrease the caller's health factor.

## Oracle and views

7. **Getters never revert on fresh oracles.** `getAccountCollateralValue`,
   `getUsdValue`, and `getTokenAmountFromUsd` succeed while every feed used by
   the query is live. M-04 violated this: one stale feed froze every user.
   Covered by `invariant_gettersCantRevert` and `M04_UnusedStaleFeed`.
8. **No silent mispricing.** Non-positive answers revert (`OracleLib__InvalidPrice`);
   per-collateral heartbeat bounds staleness. Covered by `M03_OracleValidation`.
9. **Decimal safety.** `getUsdValue` / `getTokenAmountFromUsd` round-trip for any
   token/feed decimal combination up to 18. Covered by `H02_CollateralDecimals`.

## Access control and upgrades

10. **Asymmetric pause.** While paused, `depositCollateral`, `burnDsc`, and
    `liquidate` remain callable; only risk-increasing actions
    (`mintDsc`, `redeemCollateral*`) revert. Covered by `M01_AsymmetricPause`.
11. **No instant or unsafe risk changes.** Risk parameters change only via
    schedule → 48h delay → execute, within hard bounds plus a threshold/bonus
    coupling check. Covered by `M02_RiskTimelock`.
12. **Two-step ownership.** Neither the engine nor the DSC token changes owner
    in a single transaction. Covered by `L05_TwoStepOwnership`.

## Rounding

13. **Conservative rounding.** Health-factor math floors; a reported factor never
    exceeds the exact value, so positions cannot look healthier than they are.
    Covered by `I01_HealthFactorPrecision`.

## Accepted (not invariant-enforced)

- **L-02 dust/close factor:** no minimum debt or close factor. Dust positions may
  be unprofitable to liquidate; anyone may still liquidate them and the bonus
  scales with size. Documented as accepted risk in the self-audit.
- **L2 sequencer uptime:** no sequencer check; required before any L2 deployment.
- **Fallback oracle:** single Chainlink feed per collateral; a TWAP/Pyth fallback
  is future work (see `docs/threat-model.md`).
