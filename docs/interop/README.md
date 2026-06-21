# QxFx0 Interoperability Reference

Date: 2026-05-19

This document is a consolidated reference for external integrators,
operators, and audit consumers.  It covers three contracts:

1. **Trace JSON schema** — fields emitted per turn in `replay_trace_json`.
2. **SQLite persistence schema** — tables, columns, and semantics.
3. **Environment-variable contract** — all `QXFX0_*` variables recognised by
   the runtime, scripts, and release gates.

For normative architecture decisions, see the ADR series in
`docs/adr/`.  For implementation specs, see `docs/phase-*-spec.md`.

The canonical runtime/deployment contract source for the current hardening
milestone is `docs/runtime_deployment_contract.md`.
Worker-protocol details live in `docs/worker_protocol_v1.md`.
Resource policy details live in `docs/resource_contract_matrix.md`.

---

## 1. Machine-readable contracts

QxFx0 exposes multiple JSON families. They are related, but they are not
the same contract and must not be conflated.

1. `TurnReplayTrace`
   Stored in `turn_quality.replay_trace_json`. This is the canonical
   per-turn audit/replay envelope.
2. CLI/worker turn JSON
   Returned by CLI `--json` and HTTP `/turn`. This is an operator/integrator
   response envelope that includes rendered output plus selected runtime
   diagnostics (`TurnJsonResponse` / worker turn payload).
3. health/state JSON
   Returned by worker `health` / `state` paths and HTTP readiness surfaces.
   These are operational status contracts, not replay envelopes.

The rest of this section documents only the canonical replay trace.

## 1.1 Trace JSON schema

The canonical per-turn trace is a JSON object produced by
`TurnReplayTrace` (`src/QxFx0/Types/TurnProjection.hs`).  It is stored
in `turn_quality.replay_trace_json`. It is not the same payload as the
CLI `--json` or HTTP `/turn` response.

### 1.1.1 Top-level envelope (always present)

| Field | JSON type | Semantics |
|-------|-----------|-----------|
| `trcRequestId` | string | Monotonic request identifier (echo of `TurnInput.tiStartTime` + ordinal). |
| `trcSessionId` | string | Session UUID or named session id. |
| `trcRuntimeMode` | string | `"strict"` or `"degraded"`. |
| `trcShadowPolicy` | string | Snake-case tag of the active shadow policy. |
| `trcLocalRecoveryPolicy` | string | Snake-case tag: `"none"`, `"conatus_gate"`, etc. |
| `trcRecoveryCause` | string or `null` | Populated when recovery fires this turn. |
| `trcRecoveryStrategy` | string or `null` | Strategy selected by the recovery planner. |
| `trcRecoveryEvidence` | array of strings | Human-readable evidence lines (e.g. `"blanket_violations=2"`). |
| `trcSemanticIntrospectionEnabled` | boolean | Whether introspection was active this turn. |
| `trcWarnMorphologyFallbackEnabled` | boolean | Whether morphology fallback warnings are on. |
| `trcParserConfidence` | number in [0, 1] | Confidence of the semantic parser. |
| `trcEmbeddingQuality` | string | `"modeled"`, `"fallback"`, etc. |
| `trcClaimAst` | object or `null` | Serialized claim AST when available. |
| `trcLinearizationLang` | string or `null` | Target language code (`"rus"`, `"eng"`, etc.). |
| `trcLinearizationOk` | boolean | Whether GF linearization succeeded. |
| `trcFallbackReason` | string or `null` | Why a fallback renderer was used. |

### 1.1.2 Routing & salience (Phases 5.5e, 8)

| Field | JSON type | Semantics |
|-------|-----------|-----------|
| `trcSalienceDriver` | string | Snake-case `SalienceDriver` tag: `"driven_by_resonance"`, `"driven_by_conatus_gate"`, etc. |
| `trcSalienceHolisticBias` | number in [0, 1] | 0 = pure formal, 1 = pure holistic, 0.5 = neutral. |
| `trcSalienceConfidence` | number in [0, 1] | 1 = one driver dominates decisively. |
| `trcDeliberationRule` | string or `null` | Snake-case `ReconcileRule`: `"rule_agreement"`, `"rule_holistic_advantage"`, etc. |
| `trcDeliberationAgreement` | string or `null` | Snake-case `Agreement`: `"agree"`, `"diverge_on_family"`, etc. |
| `trcDeliberationDivergence` | number or `null` | Count of differing axes / 4, in [0, 1]. |
| `trcDeliberationNarrativeTone` | string or `null` | `NarrativeTone` tag rendered from the reconciled plan. |

### 1.1.3 Essence layer (Phases 9–10)

| Field | JSON type | Semantics |
|-------|-----------|-----------|
| `trcEssenceMode` | string or `null` | `"witnessing"` pre-commit; `"contemplative"`, `"dialogical"`, `"integrative"` post-commit. `null` only when the essence layer is statically compiled out. |
| `trcEssenceCommitted` | boolean or `null` | `false` pre-commit, `true` post-commit. |
| `trcEssenceAngstLevel` | number or `null` | `etAngstLevel` in [0, 1] of the post-turn trajectory. |
| `trcEssenceTrigger` | string or `null` | `"angst_threshold"` or `"conatus_erosion"` on the commitment turn; otherwise `null`. |

### 1.1.4 Shadow & divergence

| Field | JSON type | Semantics |
|-------|-----------|-----------|
| `trcShadowSnapshotId` | string | UUID of the shadow snapshot used this turn. |
| `trcShadowStatus` | string | `"available"`, `"unavailable"`, `"blocked"`, etc. |
| `trcShadowDivergenceKind` | string | `"none"`, `"family"`, `"style"`, `"tone"`, `"recovery"`, `"multiple"`. |
| `trcShadowDivergenceSeverity` | string | `"info"`, `"warn"`, `"critical"`. |
| `trcShadowResolvedFamily` | string | Family after shadow override resolution. |
| `trcFinalFamily` | string | Canonical move family emitted to the user. |
| `trcFinalForce` | string | Illocutionary force tag. |
| `trcDecisionDisposition` | string | `"advisory"`, `"deny"`, `"permit"`, `"repair"`. |
| `trcLegitimacyReason` | string | `"reason_ok"`, `"reason_low_parser_confidence"`, etc. |

### 1.1.5 Stability guarantees

- Field names are **additive-only** — new fields may appear in future
  phases, but existing field names are never renamed or removed without
  a major version bump.
- All enum tags are **snake_case** and documented in the Haskell type
  they render from.  Tags are never abbreviated.
- `null` is used for absence; missing keys are never produced (the
  `ToJSON` instance is total over the record).

---

## 2. SQLite persistence schema

Database path is controlled by `QXFX0_DB` (default: project-relative
`.state/qxfx0.db`).  The schema is canonical in `spec/sql/schema.sql`.
Migrations live in `migrations/*.sql` and are applied in lexical order.

### 2.1 Core tables

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `schema_version` | Migration bookkeeping | `version` (PK), `applied_at`, `description` |
| `runtime_sessions` | Session lifecycle | `id` (PK TEXT), `started_at`, `last_active`, `agency`, `tension`, `status` |
| `dialogue_state` | Per-session key-value store | `session_id`, `key`, `value`, `updated_at` (composite PK) |
| `turn_quality` | Per-turn audit record | `session_id`, `turn` (composite PK), plus 30+ columns below |
| `shadow_divergence_log` | Shadow override history | `id` (PK), `session_id`, `turn`, `shadow_*` columns |

### 2.2 `turn_quality` column semantics

| Column | Type | Semantics |
|--------|------|-----------|
| `session_id` | TEXT NOT NULL | FK → `runtime_sessions(id)` |
| `turn` | INTEGER NOT NULL | 1-based ordinal within the session |
| `parser_mode` | TEXT NOT NULL | Parser mode tag (e.g. `"full_pipeline"`) |
| `parser_confidence` | REAL NOT NULL | In [0, 1] |
| `parser_errors` | TEXT NOT NULL | JSON array of error strings (default `'[]'`) |
| `planner_mode` | TEXT NOT NULL | Planner dispatch mode |
| `planner_decision` | TEXT NOT NULL | Canonical move family selected |
| `atom_register` | TEXT NOT NULL DEFAULT 'Neutral' | Semantic register |
| `atom_load` | REAL NOT NULL DEFAULT 0.0 | Atom-trace load signal |
| `scene_pressure` | TEXT NOT NULL DEFAULT 'medium' | Scene pressure tag |
| `scene_request` | TEXT NOT NULL DEFAULT '' | User input (truncated) |
| `scene_stance` | TEXT NOT NULL DEFAULT 'ContentLayer' | Semantic layer |
| `render_lane` | TEXT NOT NULL DEFAULT 'ValidateMove' | ConvMove tag |
| `render_style` | TEXT NOT NULL DEFAULT 'standard' | Render style tag |
| `legitimacy_status` | TEXT NOT NULL DEFAULT 'pass' | `pass`, `warn`, `fail` |
| `legitimacy_reason` | TEXT NOT NULL DEFAULT '' | Human-readable legitimacy verdict |
| `owner_family` | TEXT NOT NULL | Family before shadow / legitimacy |
| `owner_force` | TEXT NOT NULL | Force before shadow / legitimacy |
| `shadow_status` | TEXT NOT NULL | Shadow availability status |
| `shadow_family` | TEXT | Shadow-proposed family (nullable) |
| `shadow_force` | TEXT | Shadow-proposed force (nullable) |
| `shadow_message` | TEXT NOT NULL | Shadow diagnostic text |
| `divergence` | INTEGER NOT NULL CHECK (0,1) | 1 if shadow and owner diverged |
| `warranted_mode` | TEXT NOT NULL DEFAULT 'ConditionallyWarranted' | Legitimacy warranted-move verdict |
| `decision_disposition` | TEXT NOT NULL DEFAULT 'advisory' | Final disposition tag |
| `shadow_snapshot_id` | TEXT NOT NULL DEFAULT '' | Shadow snapshot UUID |
| `shadow_divergence_kind` | TEXT NOT NULL DEFAULT 'none' | Divergence classification |
| `replay_trace_json` | TEXT NOT NULL DEFAULT '{}' | **Full** `TurnReplayTrace` JSON (§1) |
| `created_at` | TEXT NOT NULL DEFAULT (datetime('now')) | Wall-clock timestamp (ISO-8601) |

### 2.3 Knowledge / lexicon extension tables

| Table | Purpose |
|-------|---------|
| `identity_claims` | Core self-identity assertions (concept, text, confidence, topic, embedding) |
| `semantic_clusters` | Named keyword clusters for topic routing |
| `realization_templates` | Move-kind → template mappings for rendering |
| `lexicon_sources`, `lexicon_entries`, `lexicon_forms` | Morphological lexicon (Phase-5.5e+) |
| `brain_kb_units_raw`, `brain_kb_lexeme_candidates` | Knowledge-base import staging |

### 2.4 FTS5 index

`identity_claims_fts` is a virtual FTS5 table shadowing
`identity_claims(concept, text)` for full-text search.

---

## 3. Environment-variable contract

All variables are **opt-in** — the runtime has hardcoded defaults for
every variable.  Variables are read once at startup (or per-turn for
the HTTP sidecar) and never reloaded without a restart.

### 3.1 Runtime core

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_RUNTIME_MODE` | enum | `degraded` | `strict` requires the strict local runtime contour (DB/schema/GF/local embedding and configured local infra); `degraded` relaxes optional subsystems explicitly. |
| `QXFX0_DB` | path | `.state/qxfx0.db` | Canonical SQLite database path. Created automatically if missing. |
| `QXFX0_DB_PATH` | path | deprecated alias | Temporary compatibility alias for `QXFX0_DB`. Prefer `QXFX0_DB` in new deployments. |
| `QXFX0_ROOT` | path | project checkout root | Used to resolve `spec/`, `migrations/`, and generated-artifact paths. |
| `QXFX0_STATE_DIR` | path | `$QXFX0_ROOT/.state` | Directory for Agda witness JSON, HTTP PID files, etc. |
| `QXFX0_SESSION_ID` | string | (none) | If set, the CLI `--session` default. |
| `QXFX0_MAX_SESSION_LOCKS` | integer | 4096 | Maximum tracked session locks before overflow sharding/backpressure. |
| `QXFX0_SESSION_LOCK` | boolean | `1` | Session locking is enabled by default. Set to `0`/`off` only for debug or test scenarios. |

### 3.2 HTTP sidecar (`http_runtime.py`)

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_HTTP_HOST` | string | `127.0.0.1` | Bind address. Non-loopback requires `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1`. |
| `QXFX0_HTTP_PORT` | integer | `9170` | Listen port. |
| `QXFX0_ALLOW_NON_LOOPBACK_HTTP` | boolean | `0` | Set to `1` to allow binding to `0.0.0.0` or external interfaces. |
| `QXFX0_HTTP_RUNTIME` | path | auto-resolved | Explicit path to `scripts/http_runtime.py`. |
| `QXFX0_API_KEY` | string | `""` | Bearer token for `/turn` and `/health`. Empty = no auth. |
| `QXFX0_WORKERS` | integer | legacy/ignored | Deprecated legacy knob. The sidecar logs `legacy_workers_ignored` and does not vary worker pool width from this variable. |
| `QXFX0_WORKER_TIMEOUT_SECONDS` | float | `12.0` | Per-turn worker timeout. |
| `QXFX0_MAX_SESSIONS` | integer | `128` | Maximum active HTTP sessions. |
| `QXFX0_SESSION_TTL_SECONDS` | float | `900.0` | Session idle timeout. |
| `QXFX0_READINESS_CACHE_TTL` | float | `30.0` | `/runtime-ready` response cache TTL. |
| `QXFX0_REQUIRE_SESSION_TOKEN` | boolean | `1` if `API_KEY` set else `0` | Enforce session token on `/turn`. |
| `QXFX0_ALLOW_INSECURE_NO_API_KEY` | boolean | `0` | Allow `API_KEY=""` without loopback bind. |
| `QXFX0_HTTP_INPUT_MAX` | integer | `10000` | Maximum bytes in a single HTTP request body. |
| `QXFX0_DEFAULT_SESSION_ID` | string | `""` | Fallback session id when none is provided. |

### 3.3 Embedding & morphology

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_EMBEDDING_BACKEND` | enum | `local-deterministic` | `local-deterministic` (hash-based, no network) or `remote-http` (calls external embedding API). `remote-http` is authoritative only when explicitly set and paired with a valid reachable remote URL; invalid or unhealthy remote config is reported as not-ready and does not silently switch modes. |
| `EMBEDDING_API_URL` | URL | unset | Optional remote embedding endpoint. This variable alone never enables remote mode; it is consulted only when `QXFX0_EMBEDDING_BACKEND=remote-http`. Accepted values are `https://...` or loopback `http://127.0.0.1/...`, `http://localhost/...`, `http://[::1]/...`. |
| `QXFX0_MORPH_BACKEND` | enum | (platform default) | Morphology provider: `local`, `remote`, etc. |

### 3.4 Grammatical Framework (GF)

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_GF_RUNTIME` | boolean | `0` | Enable in-process PGF linearization pipeline. Default off; set to `1` to activate. When off, the Haskell rule-based fallback (`linearizeClaimAstRus`) is used. |
| `QXFX0_GF_LANG` | string | `QxFx0SyntaxRus` | PGF grammar module name for the target language. |
| `QXFX0_GF_PGF_PATH` | path | auto-resolved | Explicit path to compiled `.pgf` binary. |
| `QXFX0_WARN_MORPHOLOGY_FALLBACK` | boolean | (infra) | Emit warnings when morphology falls back to heuristic stems. |

### 3.5 Agda & formal verification

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_AGDA_WITNESS` | path | auto-resolved | Explicit path to the Agda witness JSON file. |
| `QXFX0_AGDA_TIMEOUT_MS` | integer | (platform) | Timeout for `agda` subprocess calls. |

### 3.6 Datalog / soufflé

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_SOUFFLE_BIN` | path or name | `souffle` | Soufflé binary path or name in `$PATH`. |
| `QXFX0_SOUFFLE_TIMEOUT_MS` | integer | (platform) | Timeout for soufflé compilation. |

### 3.7 Nix & concepts

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_CONCEPTS_PATH` | path | `$QXFX0_ROOT/semantics/concepts.nix` | Constitutional concept catalog. |

### 3.8 Release / verification gates

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_REQUIRE_STRICT_RUNTIME` | boolean | `0` | `verify.sh` step 5: fail if strict runtime cannot initialise. |
| `QXFX0_STRICT_EMBEDDING_BACKEND` | enum | `local-deterministic` | Embedding backend injected by verification/release scripts for strict probes. The runtime itself reads `QXFX0_EMBEDDING_BACKEND`; this variable is script-facing policy, not a second runtime selector. |
| `QXFX0_ENFORCE_STRICT_GF_GATE` | boolean | `0` | Require GF compiler present in generated-artifact gate. |
| `QXFX0_ENFORCE_HADDOCK_GATE` | boolean | `1` | Require every module to have a Haddock header. |
| `QXFX0_ENABLE_COVERAGE_GATE` | boolean | `1` | Run HPC coverage gate (currently SKIP in low-RAM environments). |
| `QXFX0_RUN_SLOW_TESTS` | enum | `auto` | `0`/`1`/`auto` — whether verification/release scripts run `qxfx0-test-slow`. `1` is explicit opt-in; `auto` remains conservative and may skip outside the extended profile. |
| `QXFX0_SKIP_AGDA` | boolean | `0` | Skip Agda type-check in `verify.sh` (use when Agda is not installed). |
| `QXFX0_REQUIRE_AGDA` | boolean | `1` | `release-smoke.sh`: treat missing Agda as FAIL rather than SKIP. |
| `QXFX0_RELEASE_SMOKE_MODE` | enum | `strict` | `strict` = no skips allowed; `degraded-local` = infra skips become WARN. |
| `QXFX0_SHARED_CABAL_STORE` | path | `~/.cabal/store` | Shared Cabal store for CI caches. |
| `QXFX0_SHARED_CABAL_LOGS` | path | `~/.cabal/logs` | Shared Cabal logs directory. |
| `QXFX0_CABAL_LOCK_FILE` | path | `/tmp/qxfx0-cabal.lock` | `flock` file for serialized Cabal builds. |

### 3.9 Essence layer (Phase 10)

| Variable | Type | Default | Meaning |
|----------|------|---------|---------|
| `QXFX0_ESSENCE_COMMITMENT_ENABLED` | boolean | ignored | Legacy/deprecated variable. Essence commitment is now law-driven at runtime; this variable no longer governs production behavior and remains only as historical/test documentation residue until removed. |

### 3.10 Test-only variables (never used in production)

These variables are consumed only by the test harness (`Test.Support`)
and the runtime wiring's test-mode branches.  They are safe to set in
CI but have no effect on production traffic.

| Variable | Meaning |
|----------|---------|
| `QXFX0_TEST_MODE` | Enable test-mode branches (marker-file checks, deterministic time). |
| `QXFX0_TEST_FIXED_TIME` | Freeze `UTCTime` to epoch for deterministic trace ordering. |
| `QXFX0_TEST_POST_COMMIT_TAIL_EXCEPTION_ONCE_FILE` | Path to a once-file that triggers a synthetic `EssenceRupture` in integration tests. |
| `QXFX0_TEST_WORKER_CRASH_AFTER_ACCEPT_ONCE_FILE` | Synthetic worker crash marker for HTTP fault-injection tests. |
| `QXFX0_TEST_WORKER_TURN_ERROR_AFTER_ACCEPT_ONCE_FILE` | Synthetic turn-error marker for HTTP fault-injection tests. |

### 3.11 Eval / quality-gate variables (script-local)

The following variables are consumed only by evaluation and quality-gate
scripts (`scripts/check_en_render_path.sh`, `scripts/check_gf_render_path.sh`,
`scripts/run_en_eval.sh`, `scripts/run_dialogue_eval_200.sh`,
`scripts/gf_quality_gate.sh`, `scripts/check_lexicon.sh`).  They tune
thresholds and timeouts for corpus-quality measurement, not runtime
behaviour.

| Prefix | Typical variables |
|--------|-------------------|
| `QXFX0_EN_*` | Intent-fit, GF-output, fallback, RU-leakage, critical-mismatch thresholds; max prompts; turn timeout. |
| `QXFX0_GF_*` | Atoms threshold, fallback threshold, max prompts, prompts file, turn timeout, fast-test flag. |
| `QXFX0_LEXICON_*` | Minimum score, collision maxima (`DANGEROUS_COLLISION`, `FEM_ACC_EQ_NOM`, `NOUN_INS_EQ_NOM`, `SOFT_INS_EQ_NOM`). |
| `QXFX0_COVERAGE_*` | Critical-module minimum, overall minimum, critical-module list. |
| `QXFX0_HADDOCK_TARGETS` | Explicit module list for the Haddock gate. |
| `QXFX0_EVAL_SESSION_ID` / `QXFX0_EVAL_SESSION_MODE` | Evaluation harness session naming. |
| `QXFX0_SOAK_*` | Soak-test delay, port, turn count. |
| `QXFX0_CONTRACT_PROFILE` | `core`, `extended`, or `extended-lowram` — selects CI gate subset. |
| `QXFX0_FAST_TEST_SUITE` | Override the fast-suite name in `ci_gate_contract.sh`. |

---

## 4. Versioning policy

- **Trace JSON**: additive-only; no field renames without a semver-major
  runtime bump.
- **SQLite schema**: cumulative migrations in `migrations/*.sql`; never
  destructive (no `DROP TABLE` in forward migrations).
- **Env vars**: additive-only; obsolete variables are ignored but never
  reused for a different meaning.

---

## 5. How to consume this document

- **Audit consumers** parsing `replay_trace_json` should lock against the
  field list in §1 and the stability guarantee in §4.
- **Operators** deploying the runtime should consult §3 for the minimal
  env-var set needed for their target mode (`strict` vs `degraded`).
- **CI maintainers** should set `SOURCE_DATE_EPOCH` and
  `QXFX0_RELEASE_SMOKE_MODE=degraded-local` on low-RAM runners; see
  `docs/operations/release-reproducibility.md` for the reproducibility
  audit.
