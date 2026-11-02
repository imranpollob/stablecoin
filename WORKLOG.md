# WORKLOG

Running log of the portfolio-hardening work. Entries state their timezone.

Earlier entries are retained as historical notes. Current verification scope and
results below supersede their test counts, blanket baseline-reproduction claims,
and static-analysis summary.


## 2026-11-01 (America/New_York) — Portfolio and verification review

- Rewrote the README around scope, attribution, security evidence, reproducible
  setup, current limitations, and a clear route through the research artifacts.
- Aligned architecture, threat model, original self-review, and property
  specification with the code. Removed unsupported claims about universal
  liquidation liveness, a deployed multisig, independently verified findings,
  and drop-in regression compatibility with historical tags.
- Found and addressed L-06: inherited `burnFrom` could reduce DSC supply without
  updating engine debt. Added holder/spender regressions and a valid repayment
  case. Removing the override makes both access-control regressions fail;
  restoring it passes all three cases.
- Rebuilt both invariant handlers: four funded borrowers, real engine minting,
  borrower approvals, explicit action selectors, and debt/custody assertions.
  The adversarial fixture also seeds successful liquidation and realized bad
  debt before randomized price changes. Fixed-price health is asserted only in
  the fail-on-revert model.
- Strengthened the oracle regressions to assert the exact invalid-price error.
  Extended H-01 to settle and cover residual debt while paused.
- Pinned Solidity 0.8.19, Paris, optimizer settings, and Foundry v1.8.4 in CI.
  Added a 256-run/128-call invariant profile. Replaced dependency-removal/update
  defaults with pinned submodule initialization and a non-destructive check target.
- Added the MIT license file, contribution guidance, and a project security
  policy. Retained upstream attribution and historical tags.
- Reproduced Slither 0.11.3: **18 results — 0 High, 4 Medium, 8 Low,
  2 Informational, 4 Optimization**. Preserved a compact result snapshot with
  source hashes and replaced the previous unsupported all-informational triage.
  CI retains raw JSON and gates High results; lower severities remain visible.

Validation (current working tree):

- `make check`: formatting and optimized size build pass; **75 tests pass**,
  0 failures, 0 skipped (including aggregate invariant reporting).
- `make invariant`: both campaigns pass at **256 runs × 128 calls** each;
  **32,768 calls per campaign**, zero reverts in the valid-action campaign.
- `forge script script/DeployDSC.s.sol:DeployDSC`: local execution completes;
  no transactions broadcast.
- `L06DirectBurnTest` with the override removed: 2 failures, 1 pass;
  restored implementation: 3 passes.
- Final Slither command with `--fail-high`: exit 0; archived detector output
  matches the final scan and source hashes.
- Relative Markdown links and workflow YAML syntax verified.

Foundry emits optional invariant-configuration probe warnings because the pinned
older `forge-std` does not implement `targetInterfaces`/`excludeSelectors`. The
explicit action-selector campaigns still run with the expected call metrics.
No GitHub-hosted workflow execution is claimed for these local changes.

## 2026-11-02 (UTC) — Earlier hardening session (historical notes)

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
10. **Flaky-invariant incident (same session).** A fresh-clone `forge test`
    failed once in `StopOnRevertInvariants` (`DSCEngine__TransferFailed` on a
    single `mintAndDepositCollateral`). Reproduced deterministically: the fuzz
    `sender` had collided with the engine address, turning the deposit into a
    zero-delta self-transfer — which the L-04 balance-delta check correctly
    rejects, and `fail_on_revert` counted as a breach. Fix: `excludeSender
    (address(dsce))` in both invariant suites (the engine is never a user).
    Verified at 4× runs (256) green; behavior itself is covered by TempRepro
    reasoning (since removed). Lesson recorded: every new `received`-style
    check needs a sender-exclusion review in fail-on-revert suites.

## Follow-ups (tracked, not done)

- Mainnet-fork tests with real Chainlink feeds + real WBTC (needs RPC).
- Medusa/Echidna campaign config; Halmos symbolic checks on pricing math.
- Certora spec for debt-conservation invariants; Gambit mutation score.
- Stability pool / insurance fund to recapitalize `s_badDebt`.
