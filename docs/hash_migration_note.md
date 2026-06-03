# Governance / Essence Hash Migration Note

## Scope

The hardening contour migrated the primary integrity-bearing governance and
essence hashes from weak FNV/sum-style schemes to `sha256:`-prefixed hashes.

Affected surfaces:

- governance payload hash
- governance event hash
- governance projection checksum
- governance perspective registry hash
- governance history fingerprint
- essence witness hash

## Protected Property

- tamper evidence for canonical governance history
- deterministic replay identity for derived governance projections
- non-commutative witness identity for essence commitments

## Threat Model

- `attacker_model`: actor with write access to persisted governance/event state or
  replay artifacts attempting to reorder, substitute, or collide payloads while
  preserving superficially valid chain structure
- `protected_property`: chain integrity and witness identity must not depend on
  trivially composable or commutative hashes
- `compatibility_rule`: legacy persisted governance events with `fnv1a64:` hashes
  remain acceptable during replay/normalization when their stored values are
  internally consistent
- `failure_behavior_on_unsupported_legacy_hash_version`: fail closed during
  normalization / replay validation

## Compatibility Policy

- new governance and essence hashes are emitted as `sha256:`
- legacy governance events carrying `fnv1a64:` continue to validate through
  scheme-preserving normalization
- mixed histories are accepted only when stored chain equality remains valid
- unknown hash prefixes are rejected during governance normalization

## Operational Rule

Governance/essence hashes are not interchangeable with advisory local
fingerprints such as non-authoritative PGF/cache fingerprints. Only the
governance/essence integrity surfaces are covered by this migration policy.
