# Static analysis and triage

Review date: **November 1, 2026 (America/New_York)**. Tool: **Slither 0.11.3**.
Scope: production contracts, excluding results located in `lib/`, `test/`, and
`script/`. Compilation uses the pinned Foundry configuration.

## Reproduced result

| Slither impact | Results |
| --- | ---: |
| High | 0 |
| Medium | 4 |
| Low | 8 |
| Informational | 2 |
| Optimization | 4 |
| **Total** | **18** |

These are tool classifications, separate from the manually assigned severities
in the security review. They replace the previous unsupported claim that all detector
results were informational. Zero High results does not imply absence of defects.

The [compact output snapshot](artifacts/slither-summary.json) contains each
result's detector, impact, confidence, and description, plus source SHA-256
hashes. It omits the full report's AST/source metadata. CI retains the complete
JSON as the `slither-report` artifact.

## Reproduce

With Foundry and initialized submodules:

```bash
python -m pip install slither-analyzer==0.11.3
slither . --filter-paths 'lib/|test/|script/' \
  --exclude-dependencies --fail-high --json slither-report.json
```

Alternatively, use `uv tool run --from slither-analyzer==0.11.3 slither` with
the same arguments. Use a fresh output filename when rerunning JSON export.
CI fails on High results or analysis/build errors; lower-severity results remain
visible and require review. It does not currently enforce a detector-baseline
comparison for new Medium or Low results.

## Manual triage

| Detector | Impact / count | Location | Assessment |
| --- | --- | --- | --- |
| `incorrect-equality` | Medium / 1 | `depositCollateral`: `received == 0` | Expected exact-zero rejection on a measured deposit delta. Positive deposits do not depend on reaching an attacker-controlled equality target. |
| `reentrancy-no-eth` | Medium / 1 | `liquidate` | Transfers occur before later debt/bad-debt writes. State-changing settlement entry points share the reentrancy guard. Retain for review: this is not a checks-effects-interactions-only flow, and view calls can observe intermediate state. |
| `unused-return` | Medium / 2 | `_getUsdValue`, `getTokenAmountFromUsd` | Callers use only the answer. `OracleLib` checks round/timestamp fields internally before returning, so discarding them does not discard the validation. |
| `missing-zero-check` | Low / 1 | `setGuardian` | Zero intentionally disables the guardian role; owner authority remains. |
| `calls-loop` | Low / 2 | Constructor token/feed `decimals()` | Deployment-only calls to configured token/feed addresses. A bad dependency can revert deployment; it is not an unbounded user-controlled runtime loop. |
| `reentrancy-benign` | Low / 2 | `liquidate`, `depositCollateral` | Post-call writes are protected by the shared guard. Balance-delta deposit accounting requires observing the external transfer. Callback regression tests exercise guard rejection, without proving every malicious-token behavior safe. |
| `reentrancy-events` | Low / 1 | `depositCollateralAndMintDsc` | Composition delegates to individually guarded deposit/mint functions. Review event ordering and intermediate observations when changing this path. |
| `timestamp` | Low / 2 | Risk execution; oracle validation | Deliberate use for a 48-hour delay and feed freshness. Timestamp boundary conditions remain relevant to tests and deployment assumptions. |
| `solc-version` | Informational / 1 | Solidity 0.8.19 | Tool flags known compiler issues. Pinning makes builds reproducible; it does not resolve compiler bugs. The configured build uses the standard optimizer, without via-IR or a custom Yul optimizer sequence. Compiler upgrade/bug applicability review remains maintenance work. |
| `naming-convention` | Informational / 1 | `s_DSCMinted` | Storage naming convention; no accounting consequence. |
| `cache-array-length` | Optimization / 4 | Collateral iteration loops | Runtime arrays are constructor-fixed. Caching may reduce gas; scaling the collateral list also needs a gas/liveness review. |

The reentrancy assessments rely on the current shared guard and supported token
assumptions; they are not blanket dismissals of external-call risk. Refer to the
[callback tests](../test/poc/L01_ReentrancyGuard.t.sol) and
[threat model](../docs/threat-model.md). The [accounting follow-up](review-2026-11.md)
also illustrates an inherited API issue found by manual inspection, outside this
scan's reported detector results.
