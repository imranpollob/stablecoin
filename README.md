# DSC Stablecoin — Security Research Case Study

> I took a well-known codebase, extended it, then audited it like a client
> engagement. This repo contains the findings, PoCs that fail on the vulnerable
> tag, fixes, and the property-based suite that would have caught every bug.

**Original:** Cyfrin Updraft `foundry-defi-stablecoin` course project (script
headers credit Patrick Collins). **Mine:** the hardening, the self-audit, and
every test under `test/poc/`. See [`plan.md`](plan.md) for the full roadmap,
[`audits/self-audit-v0.md`](audits/self-audit-v0.md) for the report, and
[`WORKLOG.md`](WORKLOG.md) for the build log.

## Findings (all Highs/Mediums fixed)

| ID | Title | Severity | PoC |
|----|-------|----------|-----|
| H-01 | Liquidation bricked below (100 + bonus)% collateralization; bad debt uncleanable | High | [`H01_LiquidationUnderflow`](test/poc/H01_LiquidationUnderflow.t.sol) |
| H-02 | Price math assumed 18-decimal tokens / 8-decimal feeds (WBTC off by 1e10) | High | [`H02_CollateralDecimals`](test/poc/H02_CollateralDecimals.t.sol) |
| M-01 | Pause trapped users and blocked liquidators | Medium | [`M01_AsymmetricPause`](test/poc/M01_AsymmetricPause.t.sol) |
| M-02 | Instant, unbounded risk-parameter changes (mass-liquidation rug) | Medium | [`M02_RiskTimelock`](test/poc/M02_RiskTimelock.t.sol) |
| M-03 | Oracle gaps: no `price > 0`, one global heartbeat | Medium | [`M03_OracleValidation`](test/poc/M03_OracleValidation.t.sol) |
| M-04 | One stale feed froze every user | Medium | [`M04_UnusedStaleFeed`](test/poc/M04_UnusedStaleFeed.t.sol) |
| L-01 | Two settlement paths lacked `nonReentrant` | Low | [`L01_ReentrancyGuard`](test/poc/L01_ReentrancyGuard.t.sol) |
| L-03 | Constructor accepted duplicates / zero addresses | Low | [`L03_ConstructorValidation`](test/poc/L03_ConstructorValidation.t.sol) |
| L-04 | Fee-on-transfer credited by nominal amount | Low | [`L04_FeeOnTransferAccounting`](test/poc/L04_FeeOnTransferAccounting.t.sol) |
| L-05 | Single-step ownership | Low | [`L05_TwoStepOwnership`](test/poc/L05_TwoStepOwnership.t.sol) |
| I-01 | Health-factor rounding direction | Info | [`I01_HealthFactorPrecision`](test/poc/I01_HealthFactorPrecision.t.sol) |

Accepted risk: L-02 (no minimum-debt/close factor), L2 sequencer checks, and
fallback oracles — documented in [`docs/threat-model.md`](docs/threat-model.md).

Key design changes: bad-debt ledger (`s_badDebt` + `BadDebtRealized`) instead of
reverting liquidations; asymmetric pause (repay/deposit/liquidate stay open);
48h timelocked risk changes with bounds + coupling check; per-collateral
decimals and heartbeats; `Ownable2Step` throughout.

## Test suite

```bash
forge build
forge test                                    # unit + PoC + invariants (fail & continue-on-revert)
forge test --match-path "test/poc/*"          # one regression test per finding
forge fmt --check && forge build --sizes
```

Static analysis: Slither reports zero High/Medium/Low (20 info-level notes,
each triaged in [`audits/static-analysis.md`](audits/static-analysis.md)).
Properties spec: [`docs/properties.md`](docs/properties.md). Architecture and
liquidation flow: [`docs/architecture.md`](docs/architecture.md).

## Getting started

Prerequisites: [Foundry](https://book.getfoundry.sh/getting-started/installation), Git.

```bash
git clone --recurse-submodules <repository-url>
cd stablecoin
forge build
forge test
```

Submodules are committed as gitlinks, so a fresh clone builds. Deploy:

```bash
forge script script/DeployDSC.s.sol                          # local (anvil)
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

Tags: `v0-vulnerable` (pre-fix baseline — every PoC fails here), `v1-fixed`.

## What this demonstrates

Auditing my own code: two Highs I reproduced and fixed, with the invariant
suite (`collateral value ≥ total DSC`, non-reverting getters, liquidatability)
that would have caught them. Interview walkthroughs in `plan.md` §5.

## License

MIT
