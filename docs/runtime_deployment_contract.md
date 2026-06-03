# QxFx0 Runtime / Deployment Contract

This document is the canonical runtime/deployment contract source for the
current hardening milestone.

## Primary Surface

- Primary blocking runtime surface: installed Cabal artifact
- Required acceptance contour:
  - run outside the repository checkout as current working directory
  - do not depend on implicit `cwd/scripts` discovery
  - do not require `QXFX0_ROOT` to point at the checkout

## Artifact Surface Matrix

| Surface | Status | Contract |
|---|---|---|
| checkout runtime | informational_only | developer contour; not the primary acceptance surface |
| installed Cabal artifact | blocking | primary blocking runtime surface |
| container artifact | supported_non_blocking | must honor canonical env semantics and packaged sidecar/resource resolution |
| Nix artifact | supported_non_blocking | must honor canonical env semantics and packaged sidecar/resource resolution |

## Canonical Commands

- Canonical Python test command:

```bash
python3 -m unittest discover -s test -p 'test_*.py'
```

- Fast Haskell contour:

```bash
cabal test qxfx0-test-fast
```

- Architecture gate:

```bash
bash scripts/check_architecture.sh
```

## Parser Contract

- Production parser variant: `B`
- Canonical production parser backend: local rule-based parser
- The historical Python `spaCy` bridge is not part of the supported production
  runtime contract in this milestone.

Machine-readable parser trace fields:

- `parser_backend`
- `parser_status`
- `parser_degradation_reason`
- `parser_latency_ms`

## Canonical Environment Names

| Entity | Canonical name | Notes |
|---|---|---|
| SQLite DB path | `QXFX0_DB` | `QXFX0_DB_PATH` is a deprecated compatibility alias |
| Resource root | `QXFX0_RESOURCE_ROOT` | explicit packaged/resource-root override; `QXFX0_ROOT` remains compatibility/root alias |
| Runtime mode | `QXFX0_RUNTIME_MODE` | `strict` or `degraded` |
| HTTP host | `QXFX0_HTTP_HOST` | Python sidecar still accepts legacy `QXFX0_HOST` fallback |
| HTTP port | `QXFX0_HTTP_PORT` | Python sidecar still accepts legacy `QXFX0_PORT` fallback |
| HTTP sidecar script override | `QXFX0_HTTP_RUNTIME` | Explicit override only |
| Session locking | `QXFX0_SESSION_LOCK` | default `on`; `off` is degraded/test-only |
| Session lock cap | `QXFX0_MAX_SESSION_LOCKS` | default `4096` |
| Session token auth | `QXFX0_REQUIRE_SESSION_TOKEN` | defaults to `1` when API key is configured |
| Concepts override | `QXFX0_CONCEPTS_PATH` | optional explicit override for `semantics/concepts.nix` |

## External LLM Guardrails

- External LLM transport is optional and must never become the primary decision
  path.
- Official endpoint allowlist:
  - `api.mistral.ai`
  - `api.fireworks.ai`
- Allowlist validation pins the HTTPS authority to the default TLS port; custom
  ports are rejected unless the operator intentionally switches to a separate
  explicitly overridden endpoint contract.
- Untrusted-host overrides require `QXFX0_LLM_ALLOW_UNTRUSTED_HOST=1` plus
  either explicit dev/test context or
  `QXFX0_LLM_ALLOW_UNTRUSTED_HOST_CONFIRM=1`.
- Timeout envs `QXFX0_LLM_TIMEOUT_MS`, `QXFX0_MISTRAL_TIMEOUT_MS`, and
  `QXFX0_FIREWORKS_TIMEOUT_MS` are clamped to `1000..30000` ms.
- Max outbound LLM query size: `4096` chars.
- Max encoded outbound LLM request size: `16384` bytes.
- Max inbound LLM response size: `65536` bytes.
- Raw upstream body telemetry is truncated to `4096` chars and upstream error
  bodies remain redacted.

## Session Truth Model

- Python sidecar owns:
  - HTTP transport session registry
  - session token registry
  - session TTL / eviction
  - live worker lifecycle
- Haskell runtime owns:
  - runtime session state
  - persisted session state
  - semantic / dialogue truth

Ownership rule:

- a malformed request must not claim session ownership;
- a fresh authenticated `/turn` establishes ownership only on a successful
  `200 OK` turn response;
- fresh claims are rolled back on first-turn failure.

## Session Lock Contract

- Session locking is enabled by default.
- `QXFX0_SESSION_LOCK=off` is accepted only in degraded/test contours.
- In strict runtime the effective contract is fail-closed: session locking stays
  enabled even if `off` is requested.

## Worker Protocol

- Version: `1`
- Spec: `docs/worker_protocol_v1.md`

## Resource Contract Matrix

- Resource matrix: `docs/resource_contract_matrix.md`
- `semantics/concepts.nix` is a validated policy catalog surface; schema,
  canonical family/layer mapping, and `prohibitedIf` referential integrity are
  checked by `scripts/check_concepts_schema.py` in verification/CI gates.

GF-map specific contract:

- GF map load failure is fail-closed for authoritative GF linearization.
- When `lexicon_funmap.tsv` is unavailable or unparseable, render paths must
  fall back explicitly instead of silently pretending a healthy GF lexeme map.
- When topic resolution falls back to the generic GF lexeme, the render artifact
  must stay non-authoritative and surface explicit `gf_default_lexeme` /
  `gf_default_lexeme_explicit` derivation tags rather than silently passing as
  full GF coverage.

## Singleton / Hash Artifacts

- Remaining justified global singletons: `docs/singleton_register.md`
- Governance / essence hash migration note: `docs/hash_migration_note.md`

## State / Persistence Contract

- State/persistence seam contract: `docs/state_persistence_contract.md`
