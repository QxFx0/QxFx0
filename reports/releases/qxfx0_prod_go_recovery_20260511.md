## PROD_GO Recovery (Core Contract)

Core production contract has been restored.

- **Canonical RUN_ID:** `ci-20260511-000108`
- **Core verdict:** `PROD_GO`
- **Gate result:** all core gates PASS (build, tests, architecture, GF quality, haddock, schema/artifacts/lexicon checks, release-smoke degraded-local)

### What changed
- Added targeted Render/Dialogue coverage tests (`+12`, total tests `426 -> 438`)
- Stabilized degraded-local smoke semantics for low-RAM core validation
- Updated canonical evidence/reporting for WP1–WP3 closure

### Scope note
`FULL_SCIENTIFIC_GO` remains deferred by infrastructure constraints on this 10–11 GB runner:
- coverage instrumentation conflict (`vector-0.13.2.0` internal-library)
- strict smoke timeout in isolated rebuild path
- missing Agda / external LLM backend in this environment

This is tracked as INFRA, not code regression.
