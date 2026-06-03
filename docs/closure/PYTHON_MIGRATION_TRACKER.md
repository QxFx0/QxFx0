# Python → Haskell Migration Tracker (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 5
  enforcement)
- **Date**: 2026-06-02
- **Refines**:
  - `docs/closure/PYTHON_STATUS_LEDGER.md` (the source of
    truth for per-script classification)
  - `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` (the
    empty allowlist; the discipline)
  - ADR-0034 §3 Rule 5 (only `Bridge.ExternalLLM` may be
    opt-in by feature flag)
- **Related**:
  - `docs/closure/PROMOTION_PLAYBOOK.md` (sister doc; the
    promotion counterpart)
  - `docs/closure/ENFORCEMENT_MATRIX.md` (R5 + R7 cross-ref)

## 0. What this tracker is

`PYTHON_STATUS_LEDGER.md §3` lists 31 Python scripts in
6 closure classes (A–F). The ledger is the **source of
truth**; this tracker is the **status board** that the
next contributor uses to pick up a migration task.

The tracker is **regenerated** as scripts are migrated.
A script's status moves through the stages:

- `PENDING` — the script is identified for migration; no
  Haskell replacement exists.
- `IN-FLIGHT` — a Haskell replacement is in development;
  the script is still in the authority path.
- `REPLACED` — the Haskell replacement is in production;
  the Python script is no longer invoked by the
  authority path.
- `DELETED` — the Python script is removed from the
  repository.
- `KEEP` — the script is moved to `scripts/eval/` (eval-only)
  or to `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md`
  (supplier-only) with an explicit retention justification.

## 1. The first wave (Gate P5-1, P5-2, P5-3)

The first wave is the **authority-bearing** Python. Per
`PYTHON_STATUS_LEDGER.md §2`, the three scripts in this
wave are:

| Script | Closure class | Status | Replacement target |
|---|---|---|---|
| `scripts/check_schema_consistency.py` | A. canonical-build | IN-FLIGHT | `cabal run qxfx0-main -- --check-schema-consistency` wired in working tree; deletion pending build/test/CI |
| `scripts/check_schema_contract.py` | A. canonical-build | IN-FLIGHT | `cabal run qxfx0-main -- --check-schema-contract` wired in working tree; deletion pending build/test/CI |
| `scripts/sync_embedded_sql.py` | A. canonical-build | IN-FLIGHT | `cabal run qxfx0-main -- --check-embedded-sql` and `--sync-embedded-sql` wired in working tree; deletion pending build/test/CI |
| `scripts/http_runtime.py` | B. canonical-runtime (legacy) | PENDING | Confirmed not invoked after Gate P5-1; file deleted |
| `services/morphology/server.py` | B. canonical-runtime (ACTIVE) | PENDING | Haskell morphology parser (`QxFx0.Lexicon.Morphology.Parser`) |

**Gate P5-1** is closed when the three `A.` scripts are
`DELETED` and the Haskell replacements are in CI.
**Gate P5-2** is closed when the morphology server is
`DELETED` and the Haskell parser is in the runtime path.
**Gate P5-3** is closed when `http_runtime.py` is
confirmed not invoked (the script is `KEEP`-as-deleted).

## 2. The second wave (Gate P5-4, P5-5)

The second wave is the **build-time supplier** and the
**eval-only** Python. Per `PYTHON_STATUS_LEDGER.md §3`,
the scripts in this wave are:

### 2.1 C. supplier-build (Gate P5-4)

| Script | Status | Replacement target |
|---|---|---|
| `scripts/build_input_lexicon.py` | PENDING | Haskell IR emitter |
| `scripts/export_lexicon.py` | PENDING | Haskell export command |
| `scripts/generate_haskell_from_tsv.py` | PENDING | Haskell emitter |
| `scripts/generate_gf_from_tsv.py` | PENDING | Haskell emitter |
| `scripts/generate_paradigms_pymorphy2.py` | PENDING | Haskell morphology integration |
| `scripts/validate_paradigms.py` | PENDING | Haskell validator |
| `scripts/expand_en_lexicon.py` | PENDING | Haskell expansion |
| `scripts/expand_lexicon.py` | PENDING | Haskell expansion |
| `scripts/expand_ru_lexicon.py` | PENDING | Haskell expansion |
| `scripts/add_nouns_to_paradigms.py` | PENDING | Haskell paradigm augmentation |
| `scripts/add_verbs_adjs_to_paradigms.py` | PENDING | Haskell paradigm augmentation |
| `scripts/top_up_ru_lexicon.py` | PENDING | Haskell lexicon top-up |
| `scripts/import_brain_kb.py` | PENDING | Haskell KB import |
| `scripts/import_ru_opencorpora.py` | PENDING | Haskell OpenCorpora import |
| `scripts/check_gf_concrete_consistency.py` | PENDING | Haskell GF consistency check |
| `scripts/check_input_lexicon.py` | PENDING | Haskell input lexicon check |
| `scripts/verify_agda_sync.py` | PENDING | Haskell Agda sync verification |

**Gate P5-4** is closed when every script above is
either `DELETED` (Haskell replacement is in CI) or
`KEEP` (moved to `PYTHON_SUPPLIER_ALLOWLIST.md` with
explicit supplier-only retention justification).

### 2.2 D. eval-only (Gate P5-5)

| Script | Status | Notes |
|---|---|---|
| `scripts/compute_ab_metrics.py` | PENDING | AB-eval metrics. Move to `scripts/eval/` with non-authority marker. |
| `scripts/score_blind_pairs.py` | PENDING | Blind pair scoring. Same. |
| `scripts/run_blind_ab_eval.py` | PENDING | Blind AB eval driver. Same. |
| `scripts/wave2_soak.py` | PENDING | Soak test (wave 2). Same. |
| `scripts/wave3_soak.py` | PENDING | Soak test (wave 3). Same. |
| `scripts/wave4_soak.py` | PENDING | Soak test (wave 4). Same. |
| `scripts/wave5_soak.py` | PENDING | Soak test (wave 5). Same. |
| `scripts/mutate_governance_rebuild_failure.py` | PENDING (likely) | Negative-path test. |
| `scripts/promote_state_to_authoritative.py` | PENDING (likely) | State promotion test. |
| `scripts/normalize_freeze0_json.py` | PENDING (likely) | JSON normalisation. |

**Gate P5-5** is closed when every script above is
either `KEEP` (moved to `scripts/eval/`) or moved to a
separate research repo. The `D.` class is the **only**
class where `KEEP` is a first-class outcome.

### 2.3 E. test-only

| Script | Status | Notes |
|---|---|---|
| `test/test_import_ru_opencorpora.py` | PENDING | Python import test. Move to a separate research repo or delete. |
| `test/test_import_brain_kb.py` | PENDING | Python import test. Same. |

The `E.` class is **deletion-only**; no `KEEP`
outcome is allowed. The tests are Python-import
shims that exist only because the import side-effects
were not yet Haskell-native. Once the imports are
Haskell-native, the shims are dead.

## 3. The status table

The summary status as of 2026-06-02:

| Class | Total | PENDING | IN-FLIGHT | REPLACED | DELETED | KEEP |
|---|---|---|---|---|---|---|
| A. canonical-build | 3 | 0 | 3 | 0 | 0 | 0 |
| B. canonical-runtime | 2 | 2 | 0 | 0 | 0 | 0 |
| C. supplier-build | 17 | 17 | 0 | 0 | 0 | 0 |
| D. eval-only | 10 | 10 | 0 | 0 | 0 | 0 |
| E. test-only | 2 | 2 | 0 | 0 | 0 | 0 |
| F. dead | 0 | 0 | 0 | 0 | 0 | 0 |
| **Total** | **34** | **31** | **3** | **0** | **0** | **0** |

(The total is 34, not 31, because the ledger
counts `services/morphology/server.py` and 2
`test/test_import_*.py` files; this tracker
includes them for completeness.)

**0/34 scripts are fully migrated as of 2026-06-02, 3 are now in-flight in the working tree.**
The closure plan's "Python free" goal is the work
list above.

## 4. The migration order

The next contributor follows the order:

1. **A. canonical-build** (Gate P5-1). The 3
   scripts are the **highest-priority** because
   they are in the **build-time authority path**.
   `check_architecture.sh` [10] currently
   depends on the Haskell-side
   `--check-embedded-sql` invocation; the
   Python `sync_embedded_sql.py` is the
   source-of-truth generator.
2. **B. canonical-runtime** (Gate P5-2, P5-3). The
   morphology server is the **only ACTIVE Python
   in the runtime path**; replacing it is the
   closure plan's most visible "Python free"
   signal.
3. **C. supplier-build** (Gate P5-4). The 17
   scripts are the **build-time supplier**; the
   Haskell replacements are IR emitters and
   validators.
4. **D. eval-only** (Gate P5-5). The 10 scripts
   are **non-authority**; they are moved to
   `scripts/eval/` with a non-authority marker.
5. **E. test-only**. The 2 scripts are
   **deletion-only**.

## 5. The discipline

The discipline of this tracker is:

- **The ledger is the source of truth.** This
  tracker is regenerated from the ledger; the
  ledger is regenerated from the source.
- **A script's status moves forward only.** A
  `PENDING` script can become `IN-FLIGHT`,
  `REPLACED`, or `DELETED`. A `REPLACED` script
  can become `DELETED`. A `DELETED` script does
  not come back.
- **The migration is irreversible.** Once a
  script is `DELETED`, it is gone. Re-introducing
  it requires a new design ADR.
- **The `KEEP` outcome is for `D. eval-only` and
  `C. supplier-build` (with explicit
  justification).** The `A.` and `B.` classes do
  not have a `KEEP` outcome; they must be
  migrated.
- **The CI enforces the migration.** A Python
  script in the authority path is a violation
  (per `check_architecture.sh` rules [3] and [4]
  + the new rules [13]–[20] for the role split).
  The `KEEP` outcome requires a supplier-only
  retention justification in
  `PYTHON_SUPPLIER_ALLOWLIST.md`.

## 6. The next step

The next concrete migration is **Gate P5-1 (A.
canonical-build)**. The 3 scripts in this gate are
the highest-priority because they are in the
**build-time authority path**. The Haskell
replacement target is documented in
`PYTHON_STATUS_LEDGER.md §7`. The next contributor
with codebase access:

1. Reads `PYTHON_STATUS_LEDGER.md §7` (the
   proposed Haskell surface).
2. Verifies the Haskell commands already wired in `app/CLI/` and
   the gate-script rewiring compile and pass CI.
3. Deletes the 3 Python scripts.
4. Regenerates this tracker and the ledger.

The total estimate is **M** (1 week) for a
contributor with codebase access.

## 7. Acceptance criteria for this tracker

This tracker is **closed** when:

- [ ] All 34 scripts are in one of the 5 forward
      statuses (PENDING, IN-FLIGHT, REPLACED,
      DELETED, KEEP).
- [ ] Gate P5-1 is closed (3 `A.` scripts
      `DELETED`).
- [ ] Gate P5-2 is closed (1 `B.` script
      `DELETED`).
- [ ] Gate P5-3 is closed (1 `B.` script
      `DELETED`).
- [ ] Gate P5-4 is closed (17 `C.` scripts
      `DELETED` or `KEEP`).
- [ ] Gate P5-5 is closed (10 `D.` scripts
      `KEEP`).
- [ ] `E.` scripts are `DELETED`.
- [ ] The CI is green (no Python in the
      authority path; the `KEEP` scripts are
      out of the authority path).

The tracker is **deferred** until all 8 criteria
are met.
