# Threat Model

## Actors

| Actor | Capabilities | Assumed behavior |
|---|---|---|
| User (borrower) | Deposit, mint, redeem, repay, permit-style DSC transfers | Self-interested, may be careless; not trusted to keep positions healthy |
| Liquidator / MEV searcher | Calls `liquidate` on any eligible position, any time | Rational profit-maximizer; reacts within one block of eligibility, including right after `unpause` |
| Owner (multisig, TBD) | Schedule/execute risk changes, set guardian, pause/unpause | Trusted but fallible: timelock + bounds contain a misclick or key misuse, not collusion |
| Guardian | `pause` only | Semi-trusted hot key; cannot unpause or move funds (compromise blast radius = liveness only) |
| Chainlink feeds | Price data per collateral | Trusted for liveness/accuracy within heartbeat; may go stale or post bad data (handled by reverts, not by trust) |
| Collateral token contracts | ERC20 logic incl. possible fee-on-transfer or hooks | Untrusted code: credited by measured balance delta, settlement guarded by `nonReentrant` |

Out of scope: DSC secondary-market peg defense, governance attacks on the
(ownerless-yet) timelock target, and L2 sequencer outages (no L2 deployment).

## Trust assumptions

1. A majority of Chainlink oracles per feed is honest and live; otherwise the
   affected collateral's actions revert (fail-closed).
2. The owner key is a multisig with a 48h timelock consumer; a single stolen EOA
   cannot change risk parameters instantly.
3. At least one rational liquidator monitors the protocol; positions rely on
   liquidation, not on borrower diligence.
4. Collateral tokens are allowlisted ERC20s without rebasing balances. Rebasing
   tokens are unsupported; fee-on-transfer tokens are credited correctly but
   still discouraged.

## Assets at risk

- Deposited collateral (theft via reentrancy, mispricing, or malicious upgrade).
- Peg solvency (bad debt realized on-chain in `s_badDebt`, covered only by
  voluntary `coverBadDebt`; no insurance fund yet — insolvency socializes to
  DSC holders via under-collateralization).

## Attack surface and mitigations

| Surface | Mitigation | Residual risk |
|---|---|---|
| Underwater liquidation brick (H-01) | Cap seizure at balance; residual → `s_badDebt` | Bad debt needs recapitalization path (stability pool = future work) |
| Decimal mispricing (H-02) | Per-collateral token/feed decimals | Tokens with >18 decimals rejected; must re-check on `addCollateral` |
| Pause trapping users (M-01) | Asymmetric pause: repay/deposit/liquidate stay open | Mint/redeem frozen during pause (accepted: prevents risk expansion) |
| Instant param rug (M-02) | 48h timelock + bounds + coupling check | Owner can still schedule hostile values; users get 48h to exit |
| Bad oracle data (M-03) | `answer > 0`, per-feed heartbeat, round-completeness | No min/max circuit breaker, no sequencer check |
| Stale-feed DoS (M-04) | Skip zero-balance feeds | All-held-feeds-stale still freezes that user (fail-closed by design) |
| Hook-token reentry (L-01) | `nonReentrant` on all settlement entry points | New entry points must copy the modifier (review checklist item) |
| Fee-on-transfer (L-04) | Balance-delta crediting | Tokens with >100% fee or blocklisted engine still DoS deposits |

## Accepted risks (explicit)

- L-02: no `MIN_DEBT` floor or close factor; dust liquidations may be uneconomical.
- Single-oracle design; no TWAP/Pyth fallback yet.
- No stability fee or insurance fund; `s_badDebt` accounting exists but
  recapitalization is voluntary.
