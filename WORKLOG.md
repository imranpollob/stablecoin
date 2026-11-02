# WORKLOG

Running log of the portfolio-hardening work. Dates in UTC.

## 2026-11-02 — Audit fixes, PoCs, docs, hygiene (this session)

Context: repo arrived with the core H/M fixes already implemented but
uncommitted (extended `DSCEngine`, `OracleLib`, mocks, 7 PoC stubs) plus an
untracked `plan.md`. All 65 existing tests passed on Foundry 1.4.1.

1. **Verified baseline.** `forge build` clean (only `unsafe-typecast` lint
   notes on `uint256(answer)` sites already guarded by `answer > 0`);
   `forge test` 65/65 green.
2. **Phase 0 hygiene.**
   - `.gitignore`: removed `lib/` ignore so submodule gitlinks are committable;
     fresh clones build.
   - `Makefile`: dropped `--no-commit` (removed in Forge 1.x); replaced the
     auto-committing `remove` target with a non-committing variant.
   - Added `.github/workflows/ci.yml` (`forge fmt --check`, `forge build
     --sizes`, `forge test`, Slither). `forge fmt --check` passes locally.
3. **PoC/regression gaps closed** (`test/poc/`, 16 tests green):
   - `M02_RiskTimelock.t.sol` — timelock delay, bounds, coupling, cancel.
   - `L01_ReentrancyGuard.t.sol` — hook-token callback; pins the guard's exact
     revert reason so it fails on unguarded code. (First draft wrongly expected
     the *outer* call to revert; fixed by bubbling the inner revert reason —
     the guard stops the inner call while the outer settlement aborts loudly.)
   - `L05_TwoStepOwnership.t.sol` — two-step transfer on engine + DSC.
   - `I01_HealthFactorPrecision.t.sol` — rounding floors in the protocol's
     favor. (First draft used debt `3 ether`, which floors to 0 by scale, not
     by order; corrected to debt `3` so the 1/3 fraction is the assertion.)
   - Extended `M03_OracleValidation` with a negative-price (wrap-around) case.
   - Judgment call: L-02 (no `MIN_DEBT`/close factor) left as documented
     accepted risk rather than rushed in — a mint-path floor adds griefing
     surface and deserves its own design (stability pool). Same for sequencer
     checks and fallback oracles (L2/future work).
4. **Docs.** `docs/properties.md` (13 properties mapped to tests),
   `docs/threat-model.md` (actors, trust assumptions, residual risks),
   `docs/architecture.md` (liquidation flow, asymmetric pause, timelock
   lifecycle, invariant wiring).
5. **Audit artifacts.** `audits/self-audit-v0.md` (scoped to `5525018`, all
   findings with fix + PoC links), `audits/static-analysis.md` (Slither: 20
   info-level, 0 High/Medium/Low, each triaged).
6. **README rewritten** to lead with the security narrative (findings table,
   commands, tags).
7. **Verification.** Full `forge test` + PoC suite green; Slither triaged;
   `forge fmt --check` clean. L01 discrimination reasoned from revert paths
   (guard string vs panic 0x11), not re-run against stripped code.
8. **Ship.** Committed in scoped chunks, tagged `v0-vulnerable` (base
   `5525018`) and `v1-fixed`, pushed to GitHub.
9. **Submodule reinstall.** `lib/` held plain copies with no git metadata, so
   `rm -rf lib` + the four pinned `forge install`s re-registered real
   submodules (gitlinks now committed). `forge fmt` applied to new PoCs;
   final: `fmt --check` clean, **74/74 tests green** (65 existing + 9 new).

## Follow-ups (tracked, not done)

- Mainnet-fork tests with real Chainlink feeds + real WBTC (needs RPC).
- Medusa/Echidna campaign config; Halmos symbolic checks on pricing math.
- Certora spec for debt-conservation invariants; Gambit mutation score.
- Stability pool / insurance fund to recapitalize `s_badDebt`.
