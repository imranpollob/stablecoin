# Security policy

DSC Stablecoin is a collateral-backed stablecoin protocol under active
development. An independent audit and production deployment validation are
required before use with real funds.

## Scope

The security scope is `src/DSCEngine.sol`,
`src/DecentralizedStableCoin.sol`, and `src/libraries/OracleLib.sol`.
Only the current development branch is maintained. Historical tags are development
snapshots and do not receive fixes.

Known limitations are recorded in the [threat model](docs/threat-model.md).
The [security review](audits/security-review-v0.md) and
[accounting follow-up](audits/review-2026-11.md) describe existing findings.

## Reporting an issue

For a new issue, use the repository's GitHub **Security → Report a vulnerability**
option if private reporting is enabled. Otherwise, open an issue describing the
problem in the protocol. Include:

- The affected commit and contract/function.
- Preconditions, expected behavior, and actual impact.
- A minimal Foundry reproduction and the command used to run it.
- Any proposed fix and relevant assumptions.

Do not include private keys, credentials, or unrelated third-party exploit details.
There is no bug bounty or guaranteed response-time commitment.
