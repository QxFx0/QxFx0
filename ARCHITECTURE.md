# QxFx0 Architecture

## Dependency Rules

- `QxFx0.Types.*` are the shared contract layer and must not import `Core`, `Bridge`, or `Semantic`.
- `QxFx0.Core.*` owns domain logic and turn pipeline decisions. It must not import `Bridge` or `Runtime`.
- `QxFx0.Runtime.*` owns orchestration, locks, readiness, health, and interactive turn execution. It may depend on focused `Core` modules, but not on the top-level `QxFx0.Core` aggregator.
- `QxFx0.Bridge.*` owns SQLite, Nix, Agda, Datalog, and other side effects. It must not import `Core`.
- `QxFx0.Render.*` owns the canonical surface renderer. There is one production dialogue contour: `QxFx0.Render.Dialogue`.

## Canonical Contracts

- R5 constructor contract: `spec/R5Core.agda` and `spec/Sovereignty.agda`.
- SQL contract: `spec/sql/schema.sql`.
- Runtime SQL snapshot: `src/QxFx0/Bridge/EmbeddedSQL.hs`.
- Runtime-critical SQL health contract: `spec/sql/runtime_critical_contract.tsv` and `src/QxFx0/Bridge/SQLite/SchemaContract.hs`.
- Lexicon contract: `spec/sql/lexicon/schema.sql` and `spec/sql/lexicon/seed_ru_core.sql`.

## Runtime Boundaries

- `QxFx0.Runtime.Engine` is the only runtime execution layer for `runTurn`, `runTurnInSession`, and `loop`.
- `QxFx0.Core.TurnPipeline.*` runs only through `QxFx0.Core.PipelineIO`.
- `QxFx0.Runtime.Wiring` adapts runtime resources into `PipelineIO`.
- The turn pipeline has no LLM rescue effect. Low-confidence or degraded turns
  use typed local recovery (`LocalRecoveryCause`, `LocalRecoveryStrategy`,
  evidence) and must still produce a local surface without network inference.

## SQL Policy

- Canonical `spec/sql/*` is required by default.
- Embedded SQL fallback is disabled unless `QXFX0_ALLOW_EMBEDDED_SQL_FALLBACK=1`.
- Runtime bootstrap validates `schema_version` and fails fast on mismatches.
- Runtime health validates the runtime-critical schema contract without mutating session state.
- Schema version markers are committed only after migration steps and contract validation succeed.
- New runtime-critical SQL objects must be added to `spec/sql/schema.sql`, migrations, `SchemaContract.hs`, and `spec/sql/runtime_critical_contract.tsv`.

## Runtime Invariants

- `--runtime-ready` and strict bootstrap must agree on strict-mode readiness.
- `--runtime-ready` is side-effect free for session bookkeeping.
- Fresh DBs may be `schema_bootstrapable_fresh_db`; existing legacy DBs must be not-ready until migrated.
- Persistence diagnostics are typed through `PersistenceStage`; callers must not collapse them to a generic string.
- Morphology cache keys are canonical filesystem paths.
- Replay traces record `trcLocalRecoveryPolicy`, `trcRecoveryCause`,
  `trcRecoveryStrategy`, and `trcRecoveryEvidence`; they must not record an LLM
  fallback policy.

See `docs/runtime_invariants.md` and `docs/schema_contract_playbook.md`.

## Verification

1. `cabal build all`
2. `cabal test qxfx0-test`
3. `bash scripts/check_architecture.sh`
4. `python3 scripts/check_schema_contract.py`
5. `bash scripts/check_generated_artifacts.sh`
6. `bash scripts/check_lexicon.sh`
7. `python3 scripts/verify_agda_sync.py`
8. `bash scripts/verify.sh`
9. `bash scripts/release-smoke.sh`
