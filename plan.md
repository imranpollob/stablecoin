# Research roadmap

The current deliverable is a reproducible, documented security case study.
Completed work and planned extensions are separated below. Test success and
static-analysis triage are evidence within the documented model, not a production
security certification.

## Implemented

| Work | Evidence |
| --- | --- |
| Decimal-aware pricing, capped liquidation, explicit bad debt | `src/DSCEngine.sol`, H-01/H-02 regressions |
| Asymmetric pause, bounded delayed risk changes, two-step ownership | M-01/M-02/L-05 regressions and control unit tests |
| Oracle observation checks and zero-balance feed isolation | `OracleLib`, M-03/M-04 regressions |
| Deposit balance-delta accounting and consistent settlement guards | L-01/L-04 regressions |
| Engine-only allowance-based burning | L-06 regression and accounting follow-up |
| Funded stateful campaigns with explicit action selectors | `test/fuzz/`, `docs/properties.md` |
| Pinned dependencies/toolchain, local commands, CI, review documentation | `foundry.toml`, `Makefile`, `.github/workflows/ci.yml` |

## Next research priorities

| Priority | Work | Completion evidence |
| --- | --- | --- |
| 1 | Liquidation liveness and rounding boundaries | Multi-collateral exhaustion, dust/zero-quote cases, and explicit economic limits documented with regressions |
| 2 | Broader pricing properties | Fuzz all supported decimal pairs and boundary prices; assert conservative conversion bounds |
| 3 | Reproducible historical comparisons | A pinned harness that compiles on both vulnerable and fixed interfaces, with recorded before/after results |
| 4 | Mainnet-fork integration | Pinned block and real collateral/feed addresses; reproducible commands using an RPC endpoint |
| 5 | Stateful coverage expansion | Add pause, delayed risk changes, time advancement, and oracle outage sequences; retain call metrics and failure seeds |
| 6 | Independent tools | Pin and run a Medusa/Echidna campaign or symbolic pricing checks; commit configuration and results |

## Design work before deployment

- Feed-specific heartbeat configuration and L2 sequencer checks where applicable.
- Bad-debt recapitalization incentives and loss allocation.
- A documented supported-token policy and validated deployment addresses.
- Operational ownership/guardian setup, monitoring, and independent security review.

No completion is claimed for fork tests, symbolic verification, mutation scores,
external review, or production deployment. Changes to findings and assumptions
should update the [reports](audits/), [properties](docs/properties.md), and
[threat model](docs/threat-model.md).
