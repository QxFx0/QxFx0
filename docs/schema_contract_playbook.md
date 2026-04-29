# Runtime Schema Contract Playbook

Use this playbook whenever a SQL object becomes runtime-critical.

## What Counts As Runtime-Critical

An object is runtime-critical when the runtime would produce false readiness,
lose state, lose traceability, or silently degrade behavior if the object were
missing.

Examples:

- tables read or written during bootstrap, turn execution, recovery, or health;
- columns required by `StatePersistence`, turn replay trace, shadow divergence,
  session continuity, or readiness;
- indexes needed for expected runtime behavior under normal load;
- FTS tables and triggers that keep query surfaces current;
- schema markers that determine migration/repair policy.

Objects that are only seed data, offline analysis, or one-off research output
should not be promoted to the runtime contract without a concrete runtime path.

## Change Procedure

1. Update `spec/sql/schema.sql`.
2. Add a migration for existing DBs under `migrations/`.
3. Update `src/QxFx0/Bridge/EmbeddedSQL.hs` through:

   ```bash
   python3 scripts/sync_embedded_sql.py
   ```

4. Add the runtime-critical object to
   `spec/sql/runtime_critical_contract.tsv`.
5. Update `QxFx0.Bridge.SQLite.SchemaContract`:
   - `schemaContractTables` for required tables;
   - `schemaContractColumns` for required columns;
   - `schemaContractIndexes` for required indexes;
   - `schemaContractTriggers` for required triggers;
   - `schemaContractFTS` for required FTS virtual tables.
6. Extend bootstrap/migration handling if the object must be repaired on legacy
   DBs.
7. Add or update tests for:
   - fresh DB bootstrap;
   - legacy migration;
   - inconsistent current-version DB;
   - `--runtime-ready` reporting not-ready for missing critical objects.
8. Run:

   ```bash
   python3 scripts/check_schema_contract.py
   python3 scripts/check_schema_consistency.py
   python3 scripts/sync_embedded_sql.py --check
   cabal test qxfx0-test
   ```

## Contract Rules

- Health probes may inspect DB shape but must not mutate session state.
- Bootstrap may repair known legacy shapes but must not silently repair a DB
  that is already marked as current and missing required objects.
- `schema_version` must advance only after validation succeeds.
- Contract errors should remain machine-readable in readiness JSON through
  `schema_reason`.
