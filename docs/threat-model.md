# Threat model

## Scope and deployment assumptions

The research scope covers the engine, DSC token, and oracle validation library.
Local tests use mocks. There is no demonstrated production deployment, external
audit, proxy upgrade system, multisig deployment, or external timelock integration.
Collateral and price feeds are fixed at construction.

The engine values DSC debt at $1. Secondary-market liquidity, peg maintenance,
and automated recapitalization are outside the current implementation.

## Actors and authority

| Actor | Capabilities and trust |
| --- | --- |
| Borrower | Deposits, mints, repays, withdraws, and transfers DSC; may submit adversarial transactions |
| Liquidator | Permissionless settlement; needs DSC, allowance, a valid quote, and acceptable own-account health |
| Engine owner | Deployer initially; schedules/executes bounded risk changes, manages guardian, pauses/unpauses, and initiates ownership transfer |
| Guardian | Can pause; cannot unpause, change risk parameters, or withdraw collateral using the guardian role |
| Price feeds | Trusted for price accuracy; invalid/stale observations are rejected, but a fresh positive wrong price can still be accepted |
| Collateral contracts | Allowlisted at deployment; assumed compatible with supported ERC20 transfer and metadata semantics |

There is no ERC20 permit interface. Ownership transfer requires acceptance on
both engine and DSC. The token's engine owner has no public forwarding function
for arbitrary token ownership changes or allowance-based burns.

## Assets and accounting

Deposited collateral backs active borrowing. DSC holders are exposed to
under-collateralization when market moves exceed liquidation capacity. Realized
bad debt is recorded explicitly, but accounting for a loss does not recapitalize
it. `coverBadDebt` requires a voluntary holder to burn DSC without receiving
collateral in return.

The intended accounting relation is `activeDebt + badDebt == DSC supply` when
all mint/burn activity passes through the engine. L-06 closes an inherited
`burnFrom` route that previously bypassed this relation.

## Attack surfaces and remaining assumptions

| Surface | Implemented control | Remaining limitation |
| --- | --- | --- |
| Insufficient collateral at liquidation | Capped seizure and explicit residual debt | No automatic insurance; dust can round a quote to zero; liquidations are not universally guaranteed |
| Token/feed decimal mismatch | Cache and normalize decimals; reject >18 | Boundary combinations and rounding need broader fuzzing; cached metadata assumes stable decimals |
| Emergency pause | Repay, deposit, liquidation, and bad-debt coverage stay open | Withdrawals remain blocked, even after full repayment; other checks or oracle failures can still stop settlement |
| Privileged parameter changes | Engine-enforced 48h delay, bounds, tuple matching | Owner remains trusted; pause, guardian, and ownership changes are not delayed; an exit is not guaranteed during a pause or oracle outage |
| Oracle observations | Positive answer, round/timestamp checks, heartbeat | No price-deviation bounds, fallback oracle, or L2 sequencer feed; default three-hour heartbeat cannot be configured after deployment |
| Unused stale feeds | Skip tokens with zero account balances | A stale feed for any held collateral can still block health checks and liquidation |
| Callback tokens | Shared `nonReentrant` guard on settlement paths | Read-only calls can observe intermediate state; arbitrary malicious token behavior is outside supported assumptions |
| Transfer fees | Deposit credited by received balance delta | This does not establish full support for fee-on-transfer tokens; outgoing fees and unusual balance changes remain unsupported |
| Dust liquidation | Permissionless execution and configurable bonus | No minimum debt; gas costs can exceed collateral incentives; no close-factor policy |

## Token and oracle assumptions

Use allowlisted, non-rebasing tokens with boolean-returning ERC20 transfers,
stable decimals, and dependable transferability. Blocklists, hooks, upgrades,
rebases, and outgoing transfer taxes can break operational assumptions. A passing
fee-on-transfer deposit test is limited evidence about ingress accounting.

A fresh Chainlink-style observation is assumed to reflect the intended asset in
USD. Code validation does not establish that a feed address is correct or that a
reported positive price is economically accurate. Per-config heartbeat storage
currently receives the same three-hour default for every collateral; deployment
needs feed-specific review before real use.

## Verification limits

Invariant campaigns use a bounded actor set and standard mock tokens. They do
not prove profitable liquidation, continuous solvency, or peg stability. Fork
testing, differential reproduction against historical interfaces, symbolic
verification, and independent review remain future work. See the
[property specification](properties.md) and [roadmap](../plan.md).
