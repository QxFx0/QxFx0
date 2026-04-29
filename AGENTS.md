# AGENTS.md — QxFx0 Architecture Guide

## Canonical Contracts

1. `spec/R5Core.agda` + `src/QxFx0/Types.hs` define canonical R5 vocabulary.
2. `spec/Sovereignty.agda` is a closed sovereignty proof layer over constitutional validity predicates.
3. `spec/sql/schema.sql` defines canonical SQL shape.
4. `src/QxFx0/Bridge/EmbeddedSQL.hs` must mirror canonical SQL shape.
5. Lexicon canonical source is SQL-first: `spec/sql/lexicon/schema.sql` + `seed_ru_curated.sql` (primary curated seed, 156 lemmas). `seed_ru_core.sql` is retained for backward compatibility.
   **Scale-step auto-coverage (Phase 3, 2026-04-24):** `seed_ru_auto.tsv` (3997 P1 auto-verified lemmas + 17498 P2 auto-coverage lemmas) + `auto_source_manifest.json` (OpenCorpora-derived, CC-BY-SA-3.0). Source: pymorphy3 v2.0.6 / OpenCorpora rev 417150.
   **Auto-lexicon quality gates:** P1/P2 selection uses multi-criteria scoring (must_include → domain_seed → POS → non-proper → non-technical → non-patronymic → shorter → completeness → alpha). Quality metrics enforced in `check_lexicon.sh`: p1_range=3000–5000, p2_range=15000–20000, p1_mostly_proper=0, p1_patronymic_like=0, p1_long_lemma≤15, p1_technical_compound≤15, p2_patronymic≤50, p1_domain_seed_hit≥100, dangerous_collision=0. Python unit tests: `test/test_import_ru_opencorpora.py` (55 tests).
6. Canonical lexical direction is `SQL -> generated artifacts` (`resources/morphology/*.json` including `forms_by_surface.json`, `spec/gf/*.gf`, `spec/Lexicon*.agda`, `src/QxFx0/Lexicon/Generated.hs`).
7. Generated lexical artifacts are not edited manually.
8. `scripts/release-smoke.sh` is the release gate and must fail on any broken gate.

## Runtime Architecture

### Bridge Layer (`QxFx0.Bridge.*`)
Adapters and side effects: SQLite, constitutional Nix guard, Agda witness/checks,
morphology I/O, Datalog execution, persistence diagnostics.

### Core Layer (`QxFx0.Core.*`)
Domain logic and turn pipeline decisions. Core must not import `Runtime` or `Bridge`; runtime orchestration enters through `PipelineIO`. Any semantic dependency from Core must go through `QxFx0.Core.Semantic.*` port modules. Any render dependency from Core must go through `QxFx0.Core.Render.*` port modules. Any policy dependency from Core must go through `QxFx0.Core.Policy.*` port modules.

### Runtime Layer (`QxFx0.Runtime.*`)
Runtime orchestration, readiness, locks, health, and interactive turn execution. Runtime may depend on focused Core modules, but not on the top-level `QxFx0.Core` aggregator.

### Semantic/Render Layer (`QxFx0.Semantic.*`, `QxFx0.Render.*`)
Atom extraction, logic routing, semantic planning, and Russian surface rendering.

## Safety Pipeline

1. Semantic routing and constitutional Nix check.
2. R5 plan and rendering.
3. Post-render guard (`QxFx0.Core.Guard`) to prevent metadata/toxicity leakage.

## Formal Pipeline

1. `scripts/verify_agda_sync.py` checks constructor sync Agda↔Haskell.
2. Runtime can run Agda verification (`spec/r5-snapshot.tsv`) during health/readiness checks.
3. Strict readiness is honest only when strict bootstrap dependencies are both present and operational: `nix_policy_present` is file presence, `nix_ok` is evaluator availability.
4. Replay envelope gates must validate `trcLocalRecoveryPolicy`, `trcRecoveryCause`, `trcRecoveryStrategy`, and `trcRecoveryEvidence`, not the removed `trcLlmFallbackPolicy`.
5. `scripts/verify.sh` and `scripts/release-smoke.sh` require Agda by default; local bypass is explicit via `QXFX0_SKIP_AGDA=1` for `verify.sh`.

## Verification Workflow

1. `cabal build all`
2. `cabal test qxfx0-test`
3. `python3 scripts/verify_agda_sync.py`
4. `bash scripts/check_generated_artifacts.sh`
5. `bash scripts/check_lexicon.sh`
6. `bash scripts/release-smoke.sh`
7. Strict release contour: `bash scripts/release-smoke.sh`

## Deployment Notes

- Prefer explicit `QXFX0_ROOT` for binary deployments.
- `QXFX0_DB` or `QXFX0_STATE_DIR` controls persistence location.
- HTTP sidecar can be launched via:
  - `qxfx0-main --serve-http <port>`
  - `python3 scripts/http_runtime.py --bin <path> --port <port>`

## Known Accepted Risks

| Risk | Mitigation | Why Accepted |
|---|---|---|
| `FromJSON` silent defaults | `testBootstrapSessionMarksRecoveredCorruption` covers recovery | Graceful degradation for corrupt state blobs |
| `SessionLock` orphan leak at cap | Configurable via `QXFX0_MAX_SESSION_LOCKS`; overflow logs to stderr | Realistic use case is far below the default cap |
| MeaningGraph temporal drift | `UTCTime` rewiring stamps; bounded at 300 edges | Acceptable for bounded-session use |
| HTTP sidecar plaintext | Loopback default; non-loopback requires `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1` + reverse proxy | TLS termination is handled by the reverse proxy in production |
| Shared API key perimeter | API key protects all HTTP endpoints; authenticated `/turn` also binds `session_id` to `X-QXFX0-Session-Token` ownership | Multi-principal isolation still depends on deployment architecture, not just one shared key |
| `preferFamily` unconditional override | Recorded in `RoutingPhase` observability | Architectural decision (MeaningGraph strategy priority) |
| `mergeFamilySignals` first-deviation-wins | 3-signal fallback chain documented | Architectural decision |
| `extractObject` first-non-stopword heuristic | Keyword-based system boundary | Design boundary, not a bug |
| Auto-coverage tier excluded from routing | Resolver returns raw surface for ambiguous auto forms; only curated feeds `Render.Dialogue` | Architectural boundary: auto-coverage is candidate-only, not rendering-authoritative |
| Auto-lexicon scale-step | P1=3997/P2=17498 lemmas; quality gates enforced; compact array JSON format for runtime loading; MVar cache for per-process morphology parse | Scale target reached (2026-04-25); next step: full OpenCorpora import (~100k forms) or curated review |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `QXFX0_NIXGUARD_LENIENT_UNSUPPORTED` | `0` | Set to `1` to allow unsupported concepts in NixGuard (lenient mode) |
| `QXFX0_TEST_FIXED_TIME` | — | Set to epoch seconds for deterministic time source in tests |
| `QXFX0_MAX_SESSION_LOCKS` | `4096` | Cap for per-session lock tracking (overflow degrades to single global lock) |
| `QXFX0_HTTP_HOST` | `127.0.0.1` | Canonical HTTP sidecar bind host; legacy `QXFX0_HOST` is accepted only by direct Python sidecar startup |
| `QXFX0_HTTP_PORT` | `9170` direct sidecar / CLI override default `8080` | Canonical HTTP sidecar port; legacy `QXFX0_PORT` is accepted only by direct Python sidecar startup |
| `QXFX0_ALLOW_NON_LOOPBACK_HTTP` | `0` | Set to `1` to allow HTTP sidecar on non-loopback interfaces (requires reverse proxy for TLS) |
| `QXFX0_API_KEY` | — | Shared API key required by `/sidecar-health`, `/health`, `/runtime-ready`, and `/turn` when configured |
| `QXFX0_REQUIRE_SESSION_TOKEN` | `1` if `QXFX0_API_KEY` is set, else `0` | Enforce `X-QXFX0-Session-Token` ownership on authenticated session traffic |
| `QXFX0_HTTP_INPUT_MAX` | `10000` | HTTP sidecar input ceiling; keep aligned with runtime `maxInputLength` |
| `QXFX0_EMBEDDING_BACKEND` | implicit local deterministic | Local deterministic embeddings are autonomous and strict-ready; `remote-http` must be set explicitly to enable remote embeddings |
