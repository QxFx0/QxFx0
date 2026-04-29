# Commit Preparation

This repository currently has a large intentional working tree because the
runtime split moved many modules into new focused files. Do not reduce that
tree by reverting files unless the change owner explicitly asks for it.

## Safe Noise

The following are generated local artifacts and are ignored:

- `.test-tmp/`
- `.verify-home/`
- `*.db`, `*.db-wal`, `*.db-shm`
- `R5Verdict.csv`
- `ShadowAlert.csv`

If one of those appears in `git status`, update `.gitignore` or the producer
script rather than staging it.

## Commit Buckets

Prepare commits by subsystem instead of committing the whole dirty tree at once:

1. Runtime shell and CLI split:
   - `app/CLI*.hs`
   - `src/QxFx0/Runtime/**`
   - `src/QxFx0/CLI/**`
2. SQLite, persistence, and schema contract:
   - `spec/sql/schema.sql`
   - `migrations/**`
   - `src/QxFx0/Bridge/SQLite/**`
   - `src/QxFx0/Bridge/StatePersistence.hs`
   - `src/QxFx0/Types/Persistence.hs`
3. Turn pipeline modularization:
   - `src/QxFx0/Core/TurnPipeline/**`
   - `src/QxFx0/Core/PipelineIO/**`
   - `src/QxFx0/Core/TurnPlanning/**`
   - `src/QxFx0/Core/TurnRender/**`
   - `src/QxFx0/Core/TurnRouting/**`
4. Lexicon and morphology:
   - `spec/sql/lexicon/**`
   - `resources/morphology/**`
   - `resources/lexicon/**`
   - `src/QxFx0/Lexicon/**`
   - generated GF/Agda lexicon artifacts
5. Formal/spec/runtime guardrails:
   - `spec/*.agda`
   - `spec/datalog/**`
   - `src/QxFx0/Bridge/Datalog/**`
   - `src/QxFx0/Bridge/Nix*.hs`
6. Tests, scripts, and docs:
   - `test/**`
   - `scripts/**`
   - `docs/**`
   - `README.md`, `ARCHITECTURE.md`, `TECH_DEBT.md`

## Pre-Commit Checks

At minimum:

```bash
bash scripts/check_architecture.sh
python3 scripts/check_schema_contract.py
python3 scripts/check_schema_consistency.py
python3 scripts/sync_embedded_sql.py --check
cabal test qxfx0-test
```

Before a release tag:

```bash
bash scripts/check_generated_artifacts.sh
python3 test/test_import_ru_opencorpora.py
bash scripts/check_lexicon.sh
bash scripts/release-smoke.sh
```
