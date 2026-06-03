# Python Test Coverage — Verified Gap

**Status:** PARTIALLY CLOSED.

**Verified fact:** The CI workflow (`.github/workflows/ci.yml`) runs the
canonical Python unit-test command:

`python3 -m unittest discover -s test -p 'test_*.py'`

CI and the aggregate gate also execute five Python check scripts:

| Script | Purpose | Exit code in CI |
|--------|---------|-----------------|
| `scripts/sync_embedded_sql.py --check` | `EmbeddedSQL.hs` ↔ `spec/sql` sync | 0 |
| `scripts/check_schema_consistency.py` | Migration files ↔ canonical schema | 0 |
| `scripts/check_schema_contract.py` | Runtime schema contract manifest ↔ `SchemaContract.hs` | 0 |
| `scripts/check_runtime_contract.py` | Runtime/deployment docs ↔ workflow/tests/resources drift gate | 0 |
| `scripts/check_concepts_schema.py` | `concepts.nix` schema / family / layer / prohibitedIf contract | 0 |

These scripts are **lint/validation scripts**, distinct from the Python
unit-test contour. The repository currently contains Python tests under
`test/test_*.py`, but coverage is still narrow compared with the Haskell
runtime surface.

**What would be needed to close the gap:**
- Additional Python tests for:
  - `scripts/compute_ab_metrics.py` (statistical correctness)
  - `scripts/score_blind_pairs.py` (judge schema compliance)
  - `scripts/wave*_soak.py` (telemetry schema validation)
  - `scripts/export_lexicon.py` (output format correctness)
- Expansion of the current `unittest discover` contour to the remaining
  operational Python surfaces.

**Why this is not a regression:**
- The Haskell test suite (`qxfx0-test-fast`, 629 cases) provides full
coverage of the runtime behavior that the Python scripts interact with.
- Python scripts are thin orchestration/data-processing wrappers;
logic bugs are caught by Haskell-side contracts (e.g., JSONL schema
validation in `ModelComparison`).

**Decision:** Deferred.  The gap is documented and tracked; closing it
requires dedicated effort and is not blocking the core release contour.
