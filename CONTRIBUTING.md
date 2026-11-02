# Contributing

Changes should improve protocol correctness, security, maintainability, or
reproducibility.

## Development

Use Foundry v1.8.4 and initialize dependencies with
`git submodule update --init --recursive`. Run `make check` before submitting a
change. Run `make invariant` when changing accounting, settlement, or handlers.

Dependencies are pinned by Git submodule commits. Update them explicitly and
explain the reason; the normal setup command does not upgrade dependencies.

## Security changes

Include a focused regression that fails for the affected behavior and passes
with the fix. State the assumptions and impact without overstating severity.
Update the relevant report, threat model, or property specification when the
change affects a documented guarantee.

For invariant changes, identify the modeled actors and actions, explain expected
reverts, and inspect call metrics for meaningful successful transitions. A passing
campaign that never mints or settles debt provides weak evidence.

## Pull requests

Describe the problem, resulting behavior, and validation performed. Distinguish
executed checks from planned work. Preserve upstream attribution and third-party
license notices. See [SECURITY.md](SECURITY.md) for vulnerability reports.
