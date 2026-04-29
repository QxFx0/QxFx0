# QxFx0

QxFx0 is a Russian-language philosophical dialogue runtime with:
- canonical R5 routing (`CanonicalMoveFamily`, `IllocutionaryForce`)
- constitutional Nix guard
- session-aware SQLite persistence
- Agda/Haskell constructor sync checks
- CLI and HTTP machine interfaces

## Canonical Sources

- R5 contract vocabulary: `spec/R5Core.agda`, `src/QxFx0/Types/Domain.hs`
- Decision/state/observability contracts: `src/QxFx0/Types/Decision.hs`, `src/QxFx0/Types/State.hs`, `src/QxFx0/Types/Observability.hs`
- Closed sovereignty proof layer: `spec/Sovereignty.agda`
- Layer-safe shared types: `src/QxFx0/Types/Orbital.hs`, `src/QxFx0/Types/IdentityGuard.hs`
- SQL contract: `spec/sql/schema.sql`
- Lexicon raw source: `spec/sql/lexicon/schema.sql`, `spec/sql/lexicon/seed_ru_core.sql`
- GF lexicon artifacts (generated): `spec/gf/QxFx0Lexicon.gf`, `spec/gf/QxFx0LexiconRus.gf`
- Agda lexicon artifacts (generated): `spec/LexiconData.agda`, `spec/LexiconProof.agda`
- Haskell runtime lexicon map (generated): `src/QxFx0/Lexicon/Generated.hs`
- Operational policy/template texts: `src/QxFx0/Policy/Templates.hs` (not canonical lexicon contour)
- Runtime SQL mirror: `src/QxFx0/Bridge/EmbeddedSQL.hs`
- Runtime-critical schema contract: `spec/sql/runtime_critical_contract.tsv`
- Runtime invariants: `docs/runtime_invariants.md`
- Schema contract playbook: `docs/schema_contract_playbook.md`
- Commit preparation guide: `docs/commit_preparation.md`
- Release gate: `scripts/release-smoke.sh`

## Quick Start

```bash
cabal build all
cabal test qxfx0-test
bash scripts/check_architecture.sh
python3 scripts/check_schema_contract.py
bash scripts/check_lexicon.sh
bash scripts/check_generated_artifacts.sh
python3 scripts/verify_agda_sync.py
bash scripts/verify.sh
bash scripts/release-smoke.sh
```

Lexicon artifacts are generated from SQL:

```bash
python3 scripts/export_lexicon.py
bash scripts/check_lexicon.sh
```

Canonical direction is strict: `SQL -> morphology JSON + GF + Agda`.
Do not edit generated GF files manually.

If you want local guardrails before every commit:

```bash
git config core.hooksPath .githooks
```

## CLI

```bash
cabal run qxfx0-main -- --healthcheck
cabal run qxfx0-main -- --state-json
cabal run qxfx0-main -- --turn-json "Что такое свобода?"
cabal run qxfx0-main -- --turn-json --semantic "Что такое свобода?"
```

Backward-compatible aliases are supported:
- `--session` (`--session-id`)
- `--input` (`--turn-json`)
- `--json` (`--state-json`)
- `--health` (`--healthcheck`)

## HTTP Sidecar

From CLI:

```bash
cabal run qxfx0-main -- --serve-http 9170
```

Direct script launch:

```bash
QXFX0_BIN="$(cabal list-bin qxfx0-main)" \
QXFX0_ROOT="$(pwd)" \
python3 scripts/http_runtime.py --host 127.0.0.1 --port 9170
```

Endpoints:
- `GET /sidecar-health` (canonical sidecar liveness endpoint)
- `GET /runtime-ready` (backend readiness probe via side-effect free `qxfx0-main --runtime-ready`)
- `GET /health` (deprecated compatibility alias for `/sidecar-health`, returns `X-QXFX0-Deprecated`)
- `POST /turn` with `{"session_id":"abc","input":"Что такое свобода?"}`

HTTP auth perimeter:
- if `QXFX0_API_KEY` is configured, `/sidecar-health`, `/health`,
  `/runtime-ready`, and `/turn` all require `X-API-Key`
- non-loopback bind requires explicit `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1`
  (`0.0.0.0` is treated as non-loopback)

Live session contract (`/turn`):
- `session_id` maps to one live persistent Haskell runtime worker (`--worker-stdio`)
- first `/turn` for new `session_id` boots a new worker and runtime epoch
- subsequent `/turn` requests for that `session_id` are handled by the same live worker
- turn execution is serialized per session (no concurrent turns inside one session)
- if worker is evicted/crashes, a new worker is created with a new `runtime_epoch`
- response includes `runtime_epoch`, `runtime_turn_index`, `worker_mode`
- if API-key-backed session-token enforcement is active, the first successful
  turn also returns `session_token`; subsequent turns for that session must send
  `X-QXFX0-Session-Token`
- invalid input is rejected before a new session token is claimed

Continuity semantics:
- live continuity is guaranteed only while the worker epoch is alive
- persisted `SystemState` restores after restart, but is not equal to live epoch continuity
- `runtime_turn_index` is monotonic only inside one live `runtime_epoch` for that session

Failure semantics (`/turn`):
- pre-send failure (worker dead before command send): sidecar may recreate worker and send once
- post-send failure (timeout/protocol/transport after send attempt): no automatic retry of the same turn
- post-send uncertainty returns explicit unknown-outcome contract (`error = "turn_outcome_unknown"`, `result_unknown = true`)
- explicit worker turn error poisons live worker continuity: sidecar drops that worker and next request starts a fresh epoch

Readiness probe semantics:
- `--runtime-ready` / `/runtime-ready` do not bootstrap session and do not write `runtime_sessions`
- legacy `--health` remains for compatibility and is session-bootstrap based
- fresh DB readiness reports `schema_bootstrapable_fresh_db`; current DB readiness reports `schema_ok version=N`
- legacy schema and inconsistent-current-schema cases must be not-ready until bootstrap/migration or explicit repair resolves them
- strict readiness requires the same effective backend contour as strict turn bootstrap
- `nix_policy_present=true` means the policy file resolved; `nix_ok=true` means the constitutional evaluator is operational as well
- `/runtime-ready` JSON exposes `nix_policy_present`, `nix_ok`, and `nix_issues` so operators can separate missing policy from broken Nix infrastructure
- Nix probe compatibility follows runtime behavior: it tries
  `nix-instantiate --restricted` first and falls back to plain eval only when
  `--restricted` is unsupported by the local evaluator

## Runtime Environment

- `QXFX0_ROOT` project root/resource root (recommended in deployment)
- `QXFX0_DB` exact database path
- `QXFX0_STATE_DIR` directory for auto DB path (`qxfx0.db`)
- `QXFX0_SESSION_ID` default session id
- `QXFX0_SESSION_LOCK` enable per-session runtime lock
- `QXFX0_SESSION_TTL_SECONDS` idle TTL for HTTP session workers
- `QXFX0_WORKER_TIMEOUT_SECONDS` hard timeout for one worker command
- `QXFX0_HTTP_HOST` canonical HTTP sidecar bind host (`127.0.0.1` by default;
  direct Python sidecar also accepts legacy `QXFX0_HOST`)
- `QXFX0_HTTP_PORT` canonical HTTP sidecar port (direct Python sidecar also
  accepts legacy `QXFX0_PORT`)
- `QXFX0_API_KEY` shared HTTP API key for `/sidecar-health`, `/health`,
  `/runtime-ready`, and `/turn`
- `QXFX0_REQUIRE_SESSION_TOKEN` enforce per-session ownership token on
  authenticated `/turn` traffic (defaults to `1` when `QXFX0_API_KEY` is set)
- `QXFX0_HTTP_INPUT_MAX` sidecar input length ceiling; must stay aligned with
  runtime `maxInputLength`
- `QXFX0_ALLOW_NON_LOOPBACK_HTTP` explicit opt-in for non-loopback HTTP bind
- `QXFX0_EMBEDDING_BACKEND` `local-deterministic|remote-http`; remote embedding
  is enabled only by this explicit switch, not by `EMBEDDING_API_URL` alone.
  The implicit local deterministic backend is autonomous and strict-ready.
- LLM completion providers are not part of the turn runtime. Low-confidence
  turns use local recovery and persist typed recovery cause/strategy/evidence in
  replay traces.

## Notes

- Post-render safety guard is enforced before final output.
- Local recovery replaces LLM rescue fallback: the system narrows scope,
  exposes uncertainty, asks clarification, or safely recovers without a model
  call.
- User-facing recovery text stays human-readable; typed
  `recoveryCause/recoveryStrategy/recoveryEvidence` remain in replay trace and
  observability fields.
- `scripts/verify.sh` and `scripts/release-smoke.sh` validate replay traces
  against `trcLocalRecoveryPolicy`, `trcRecoveryCause`,
  `trcRecoveryStrategy`, and `trcRecoveryEvidence`.
- `scripts/verify.sh` and `scripts/release-smoke.sh` require Agda by default. Local bypass for `verify.sh` is explicit via `QXFX0_SKIP_AGDA=1`.
- Embedded SQL fallback is disabled unless `QXFX0_ALLOW_EMBEDDED_SQL_FALLBACK=1`.
- `saveState` writes canonical `dialogue_state` plus per-turn projections in one transaction (`turn_quality`, `shadow_divergence_log`).
- Runtime-critical schema objects must be declared in `spec/sql/runtime_critical_contract.tsv` and validated by `scripts/check_schema_contract.py`.
