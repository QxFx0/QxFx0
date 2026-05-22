# Python Test Coverage — Verified Gap

**Status:** NOT PROVEN (no Python unit-test suite exists).

**Verified fact:** The CI workflow (`.github/workflows/ci.yml`) and the
`scripts/ci_gate_contract.sh` aggregate runner execute three Python
check scripts as gate steps:

| Script | Purpose | Exit code in CI |
|--------|---------|-----------------|
| `scripts/sync_embedded_sql.py --check` | `EmbeddedSQL.hs` ↔ `spec/sql` sync | 0 |
| `scripts/check_schema_consistency.py` | Migration files ↔ canonical schema | 0 |
| `scripts/check_schema_contract.py` | Runtime schema contract manifest ↔ `SchemaContract.hs` | 0 |

These are **lint/validation scripts**, not a formal unit-test contour.
There are no `test_*.py` / `*_test.py` files in the repository.

**What would be needed to close the gap:**
- A `tests/python/` directory with `pytest`-based tests for:
  - `scripts/compute_ab_metrics.py` (statistical correctness)
  - `scripts/score_blind_pairs.py` (judge schema compliance)
  - `scripts/wave*_soak.py` (telemetry schema validation)
  - `scripts/export_lexicon.py` (output format correctness)
- A CI step `python3 -m pytest tests/python/` with fail-on-error.

**Why this is not a regression:**
- The Haskell test suite (`qxfx0-test-fast`, 629 cases) provides full
coverage of the runtime behavior that the Python scripts interact with.
- Python scripts are thin orchestration/data-processing wrappers;
logic bugs are caught by Haskell-side contracts (e.g., JSONL schema
validation in `ModelComparison`).

**Decision:** Deferred.  The gap is documented and tracked; closing it
requires dedicated effort and is not blocking the core release contour.
