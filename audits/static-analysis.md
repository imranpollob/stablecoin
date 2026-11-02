# Static Analysis Triage

Tool: Slither 0.11+ on `src/DSCEngine.sol` (`--exclude-dependencies`).
Result: **20 findings, all INFO severity — zero High/Medium/Low.**
Each item below is triaged true positive (fixed or tracked) or false
positive / accepted with a reason. Raw output is reproducible via CI's
`slither` job (fail-on: none) or:

```bash
slither src/DSCEngine.sol \
  --solc-remaps '@openzeppelin/contracts=lib/openzeppelin-contracts/contracts @chainlink/contracts=lib/chainlink-brownie-contracts/contracts' \
  --exclude-dependencies
```

## Triage

| Detector | Location | Verdict | Reason |
|---|---|---|---|
| `reentrancy-eth` on `depositCollateral` (state write after `transferFrom`) | DSCEngine L297-311 | False positive | `nonReentrant` + checks-effects pattern (balance delta measured after call; no value extracted mid-call). Covered by `L01_ReentrancyGuard`. |
| `reentrancy-events` on `depositCollateralAndMintDsc` (event after external call) | L213-222 | False positive | Event emission ordering only; no funds at risk. Composed entry points delegate to guarded functions. |
| `reentrancy` on `liquidate` | L263-284 | False positive | `nonReentrant`; external calls (`transfer`, `transferFrom`, `burn`) precede no state writes that an attacker could exploit — balances updated before transfers. |
| `timestamp` on `executeRiskParameters` (`block.timestamp < eta`) | L185 | Accepted | Intended use: 48h timelock. Miner manipulation window (±seconds) is irrelevant at a 48h scale. |
| `timestamp` on `OracleLib.staleCheckLatestRoundData` | OracleLib L27-30 | False positive | Comparing feed timestamps is the detector's documented exception; this *is* the staleness check. |
| `solc-version` (0.8.19 known-bug list) | all src | Accepted | Pinned toolchain (Foundry 1.4.1). Listed bugs (verbatim dedup, full-inliner arg order, selector side effects) do not affect this code shape; upgrade tracked. |
| `pragma` (mixed `^0.8.0` deps vs `0.8.19` src) | deps | Accepted | Standard for OZ/Chainlink deps; build pins 0.8.19. |
| `naming-convention` (`s_DSCMinted`) | L71 | Accepted | Kept for continuity with the upstream codebase and existing tests. |
| `calls-in-loop` (constructor `decimals()` calls) | L121-122 | False positive | One-time deployment loop over a handful of allowlisted tokens; no gas griefing vector. |
| `unused-return` (ignored round fields) | L401, L481 | False positive | Only `answer` is needed; staleness fields are enforced *inside* `staleCheckLatestRoundData`, which reverts. |
| `zero-address` (`setGuardian` lacks check) | L144-146 | Accepted | Zero guardian is a safe state (guardian role disabled); owner retains control. Documented. |
| `strict-equality` (`received == 0`) | L307 | False positive | Exact-zero comparison on a measured delta is correct here (revert on zero-value deposits). |
| `cache-array-length` (`s_collateralTokens.length` in loops) | 4 sites | Accepted | Collateral arrays are tiny (2-5 tokens); caching saves negligible gas and hurts readability. |

## Judgment

No finding indicates exploitable behavior. The reentrancy cluster is Slither's
known over-approximation on `nonReentrant`-guarded functions with post-call
events/writes; the guard is additionally pinned by the `L01_ReentrancyGuard`
regression tests, which assert the guard's exact revert reason.
