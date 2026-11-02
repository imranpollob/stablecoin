# Attribution and source provenance

## Protocol foundation

Portions of the engine, DSC token, deployment scripts, and test fixtures derive
from [Cyfrin's Foundry DeFi Stablecoin repository](https://github.com/Cyfrin/foundry-defi-stablecoin-cu),
authored by Patrick Collins and contributors. This acknowledgment consolidates
the source-credit references previously included in individual contract comments.

DSC's current implementation includes protocol-specific risk controls,
liquidation and debt-accounting changes, pricing validation, and verification
infrastructure maintained in this repository. The security reports document
these changes and their test evidence.

## Dependencies

Third-party source remains in its respective submodule. Its copyright notices,
SPDX identifiers, and license terms are retained there.

| Dependency | Location |
| --- | --- |
| OpenZeppelin Contracts | `lib/openzeppelin-contracts` |
| Chainlink contracts | `lib/chainlink-brownie-contracts` |
| Forge Standard Library | `lib/forge-std` |

Repository code retains its existing MIT SPDX identifiers. See [LICENSE](LICENSE)
for the project license and each dependency for its applicable license notices.
