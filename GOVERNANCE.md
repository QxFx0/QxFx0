# Governance

## Project model

QxFx0 is currently maintainer-led.

## Roles

- Maintainer:
  - defines release criteria
  - approves architecture changes
  - manages contract gates and release tags
- Contributors:
  - submit PRs with tests and gate evidence
  - follow architecture and generation contracts

## Decision process

1. Technical proposals must include:
   - affected modules
   - migration impact
   - gate/test impact
2. Backward-incompatible changes require explicit maintainer approval.
3. Release decisions are based on gate evidence, not discussion-only consensus.

## Escalation

Security issues follow `SECURITY.md`. All other disputes are resolved by
maintainer decision after review of code and evidence.
