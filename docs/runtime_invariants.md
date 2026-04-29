# QxFx0 Runtime Invariants

This document records the invariants that must stay true for the runtime to
behave like one coordinated mechanism rather than a set of loosely coupled
checks. These are release invariants, not aspirational notes.

## Readiness And Strict Startup

- `--runtime-ready` and strict session bootstrap must use the same effective
  health model.
- If `--runtime-ready` reports `status="ok"` and `ready=true` in strict mode,
  a strict `--turn-json` using the same environment must be able to bootstrap.
- If strict bootstrap would fail on schema, Agda, Datalog, embedding, or
  resource readiness, `--runtime-ready` must be not-ready and expose the same
  component class in its JSON payload.
- In strict mode, degraded optional readiness is still not-ready when that same
  optional component would block bootstrap.
- `nix_policy_present` means the policy file resolved; `nix_ok` means the
  constitutional evaluator is operational as well.
- In strict mode the decision path is local-first and explicit in readiness:
  `decision_path_local_only=true`, `network_optional_only=true`,
  `llm_decision_path=false`.
- `morph_backend_local=true` is required for strict local-first readiness.
- `--runtime-ready` is side-effect free for session state: it must not create
  `runtime_sessions` rows and must not mutate live session bookkeeping.
- A missing DB file is allowed to report `schema_bootstrapable_fresh_db` because
  the first real bootstrap can create the canonical schema.

## Schema Contract

- `spec/sql/schema.sql` is the canonical SQL shape.
- `src/QxFx0/Bridge/EmbeddedSQL.hs` is a generated mirror and must stay in sync
  with `spec/sql/schema.sql`.
- `migrations/*.sql` must cumulatively produce the same object shape as the
  canonical schema.
- Runtime health and mutating bootstrap must both validate
  `QxFx0.Bridge.SQLite.SchemaContract`.
- `spec/sql/runtime_critical_contract.tsv` lists objects whose absence must
  make health/bootstrap fail: tables, migration-added columns, indexes,
  triggers, and FTS objects.
- A future runtime-critical SQL object must be added to all three places:
  canonical SQL, `SchemaContract.hs`, and `runtime_critical_contract.tsv`.

## Migration Semantics

- Runtime migrations are explicit, idempotent steps.
- A schema version marker may be written only after all migration steps and
  post-migration contract validation succeed.
- Legacy v1 DBs with `schema_version=1` migrate to the current schema version
  before turn execution.
- Legacy v1-shaped DBs with an empty/missing `schema_version` are repaired as
  v1-shaped DBs, then validated as the current schema version.
- A DB marked with a future schema version must fail fast; downgrade is not
  supported.
- A DB marked as current but missing runtime-critical objects is
  `schema_inconsistent`/not-ready, not silently repaired.

## Persistence

- State blob persistence and per-turn projection persistence happen inside one
  transaction.
- `saveStateWithProjection` returns structured `PersistenceDiagnostic` values;
  callers must not collapse them to a generic `save_failed`.
- Persistence stages are typed with `PersistenceStage`, so diagnostics are not
  recovered by parsing arbitrary text.
- Per-connection SQLite policy such as `PRAGMA synchronous=NORMAL` belongs in
  connection initialization, not inside every save transaction.
- A corrupt persisted state blob enters recovery bootstrap with
  `PdCorruptDecode` plus any schema-default diagnostics available from the raw
  blob.

## Local Recovery

- Turn execution must not depend on an LLM or external completion provider.
- Low-legitimacy, low-parser-confidence, shadow-unavailable,
  shadow-divergent, render-blocked, unknown-topic, and degraded-runtime states
  are represented as typed `LocalRecoveryCause` values.
- Each recovery cause maps to a bounded local `LocalRecoveryStrategy`:
  clarification, scope narrowing, known-term definition, candidate
  distinction, uncertainty exposure, or safe recovery.
- Local recovery may reduce ambition or ask for clarification, but it must not
  invent missing content through an external model.
- User-facing recovery text must stay human-readable and must not expose raw
  internal taxonomy tokens (`low_legitimacy`, `narrow_scope`, etc.).
- Replay trace JSON must persist `trcLocalRecoveryPolicy`,
  `trcRecoveryCause`, `trcRecoveryStrategy`, and `trcRecoveryEvidence`.
- The turn effect protocol must not contain a network LLM call used as a rescue
  fallback.

## HTTP Perimeter

- `qxfx0-main --serve-http` defaults to loopback-only bind. `127.0.0.1`,
  `localhost`, and `::1` are loopback; `0.0.0.0` is not.
- Any non-loopback bind requires explicit `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1`.
- `QXFX0_HTTP_HOST` and `QXFX0_HTTP_PORT` are the canonical sidecar bind
  variables. The direct Python sidecar accepts legacy `QXFX0_HOST` and
  `QXFX0_PORT` only as compatibility fallbacks.
- Implicit sidecar script resolution must use packaged/resource/executable
  locations only; `cwd` discovery is allowed only through explicit
  `QXFX0_HTTP_RUNTIME`.
- If `QXFX0_API_KEY` is configured, `/sidecar-health`, `/health`,
  `/runtime-ready`, and `/turn` all require `X-API-Key`.
- If authenticated session-token enforcement is active, the first successful
  `/turn` for a new `session_id` returns `session_token`, and subsequent turns
  for that live session must present it via `X-QXFX0-Session-Token`.
- Invalid input must be rejected before session ownership is claimed.
- The HTTP sidecar input ceiling must match runtime `maxInputLength`
  (default `10000`) unless both are intentionally changed together.

## Resource And Cache Identity

- Morphology data is cached by canonicalized morphology directory path.
- Resource-root changes must not accidentally reuse a morphology cache entry
  from a different path.
- Embedded SQL fallback is disabled by default; using it requires explicit
  `QXFX0_ALLOW_EMBEDDED_SQL_FALLBACK=1`.
- `EMBEDDING_API_URL` alone must not switch the embedding runtime into remote
  mode; remote embeddings require explicit `QXFX0_EMBEDDING_BACKEND=remote-http`.
- The implicit local deterministic embedding backend is autonomous and
  strict-ready. It remains `quality=heuristic`, but it must not require a
  network endpoint or an explicit env var to satisfy strict startup.

## Verification

The invariant gate set is:

```bash
bash scripts/check_architecture.sh
python3 scripts/check_schema_consistency.py
python3 scripts/sync_embedded_sql.py --check
python3 scripts/check_schema_contract.py
cabal test qxfx0-test
bash scripts/check_generated_artifacts.sh
python3 test/test_import_ru_opencorpora.py
bash scripts/check_lexicon.sh
```

`scripts/verify.sh` and `scripts/release-smoke.sh` must validate replay traces
against `trcLocalRecoveryPolicy`, `trcRecoveryCause`,
`trcRecoveryStrategy`, and `trcRecoveryEvidence`.

Nix/Souffle verification probes in `release-smoke.sh` must follow runtime
resolution semantics:
- `nix-instantiate --restricted --eval` first, then fallback to plain `--eval`
  only if `--restricted` is unsupported;
- Souffle resolution order: `QXFX0_SOUFFLE_BIN` -> local `souffle` ->
  flake app `.#apps.x86_64-linux.souffle-runtime.program` -> if that store path
  is stale, materialize `.#souffle-runtime` and use `${out}/bin/souffle`.

Strict runtime smoke should also pass outside a sandbox that blocks Nix/Souffle:

```bash
QXFX0_RUNTIME_MODE=strict \
QXFX0_EMBEDDING_BACKEND=local-deterministic \
cabal run -v0 qxfx0-main -- --runtime-ready
```
