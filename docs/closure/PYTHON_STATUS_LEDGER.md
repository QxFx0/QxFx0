# Python Status Ledger (QxFx0_v3) — closure-phase update

- **Status**: Active (closure-phase work product, Package 5)
- **Date**: 2026-06-02
- **Refines**: `docs/PYTHON_STATUS_LEDGER.md` (2026-05-26)
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md`
  - `docs/closure/TECH_DEBT_CLOSURE_INDEX.md`

## 0. Why this update exists

The 2026-05-26 ledger classifies Python components by **category**
(legacy perimeter / governance / artifact / evaluation / test) and
flags `canonical=yes|no`. The closure plan's Package 5 demands a
stricter, per-file **authority** classification with concrete
**replacement plan** and **proof evidence** for each component that
moves from `canonical=yes` to `canonical=no`.

This file extends the 2026-05-26 ledger row by row, with a per-file
inventory of every `.py` file in `scripts/` and `services/`, plus
the two `test/test_*.py` files. The classification is the closure
plan's authoritative input for "zero Python in canonical authority
path".

## 1. Closure-plan authority classes for Python

| Class | Definition | Allowed in authority path? |
|---|---|---|
| `A. canonical-build` | Currently invoked by `scripts/check_architecture.sh`, `release-smoke.sh`, or `verify.sh` for build / release / governance. | yes — but must be replaced before closure. |
| `B. canonical-runtime` | Currently invoked by the runtime perimeter (e.g. `qxfx0-main --serve-http`). | yes — but must be replaced before closure. |
| `C. supplier-build` | Generates or validates derived artifacts (lexicon, morphology, GF). Not on the authority path, but the artifact depends on it. | no (supplier-only). |
| `D. eval-only` | Used only for AB eval, soak, scoring, blind-pair tests. Not on the authority path. | no (eval-only). |
| `E. test-only` | Python test that supports the build pipeline. Not on the authority path. | no (test-only). |
| `F. dead` | Not invoked by any known gate, deprecated, or stale. | no. **To be deleted.** |

## 2. First wave — must close in Phase 3 (build-time authority)

### 2.1 `scripts/check_schema_consistency.py`
- category (old ledger): release/governance authority helper
- **closure class**: `A. canonical-build`
- **invoked by**: `scripts/check_architecture.sh` (or `verify.sh`) — TBD confirm; previously YES per 2026-05-26 ledger
- **replacement_target**: Haskell verify/contract command
- **phase_target**: Phase 3 / closure-plan Phase 5 first wave
- **risk_if_removed**: high — schema drift could pass undetected
- **proof_of_replacement**:
  - command: TBD (Haskell command name TBD; see §7 below)
  - commit SHA: PENDING
  - gate evidence: PENDING
  - golden diff/no-diff evidence: PENDING
- **delete_deadline**: before closure-plan closure

### 2.2 `scripts/check_schema_contract.py`
- category (old ledger): release/governance authority helper
- **closure class**: `A. canonical-build`
- **invoked by**: same gate as §2.1
- **replacement_target**: Haskell verify/contract command (likely same command as §2.1)
- **phase_target**: Phase 3 / closure-plan Phase 5 first wave
- **risk_if_removed**: high
- **proof_of_replacement**: PENDING (combined with §2.1)
- **delete_deadline**: before closure-plan closure

### 2.3 `scripts/sync_embedded_sql.py`
- category (old ledger): release/governance + derived artifact authority helper
- **closure class**: `A. canonical-build` (the `--check` invocation)
- **invoked by**: `scripts/check_architecture.sh` (or `verify.sh`) with `--check` flag
- **replacement_target**: Haskell generator/check command
- **phase_target**: Phase 3 or 4A / closure-plan Phase 5 first wave
- **risk_if_removed**: high — embedded SQL drift could pass undetected
- **proof_of_replacement**: PENDING
- **delete_deadline**: before closure-plan closure

## 3. Second wave — runtime / supplier / eval / test classification

The full per-file inventory of `scripts/*.py` and `services/**/*.py`
is below. Closure class is per §1.

| File | LOC (approx) | Closure class | Notes |
|---|---|---|---|
| `scripts/http_runtime.py` | (small) | `B. canonical-runtime` (legacy) | Per 2026-05-26 ledger: replaced by `qxfx0-main --serve-http`. `proof_of_replacement` is PENDING a commit SHA + gate evidence. |
| `services/morphology/server.py` | (small) | `B. canonical-runtime` (ACTIVE) | The pymorphy2-based morphology HTTP server. **The only ACTIVE Python in the runtime path.** Replaced by Haskell morphology parser; see `docs/closure/MORPHOLOGY_REPLACEMENT.md` (Package 5 follow-up). |
| `scripts/build_input_lexicon.py` | | `C. supplier-build` | Generates `Input.GeneratedLexicon` (the 3946-line Haskell file). Replacement: Haskell IR emitter. |
| `scripts/export_lexicon.py` | | `C. supplier-build` | Exports lexicon to TSV. Replacement: Haskell export command. |
| `scripts/generate_haskell_from_tsv.py` | | `C. supplier-build` | TSV → Haskell IR. Replacement: Haskell emitter. |
| `scripts/generate_gf_from_tsv.py` | | `C. supplier-build` | TSV → GF grammar. Replacement: Haskell emitter. |
| `scripts/generate_paradigms_pymorphy2.py` | | `C. supplier-build` | pymorphy2 → paradigms. Replacement: Haskell morphology integration. |
| `scripts/validate_paradigms.py` | | `C. supplier-build` | Validates paradigms. Replacement: Haskell validator. |
| `scripts/expand_en_lexicon.py` | | `C. supplier-build` | Lexicon expansion (en). Replacement: Haskell expansion. |
| `scripts/expand_lexicon.py` | | `C. supplier-build` | Lexicon expansion (general). Replacement: Haskell expansion. |
| `scripts/expand_ru_lexicon.py` | | `C. supplier-build` | Lexicon expansion (ru). Replacement: Haskell expansion. |
| `scripts/add_nouns_to_paradigms.py` | | `C. supplier-build` | Paragigm augmentation. Replacement: Haskell. |
| `scripts/add_verbs_adjs_to_paradigms.py` | | `C. supplier-build` | Paragigm augmentation. Replacement: Haskell. |
| `scripts/top_up_ru_lexicon.py` | | `C. supplier-build` | Lexicon top-up. Replacement: Haskell. |
| `scripts/import_brain_kb.py` | | `C. supplier-build` | Knowledge-base import. Replacement: Haskell. |
| `scripts/import_ru_opencorpora.py` | | `C. supplier-build` | OpenCorpora import. Replacement: Haskell. |
| `scripts/check_gf_concrete_consistency.py` | | `C. supplier-build` | GF consistency check. Replacement: Haskell. |
| `scripts/check_input_lexicon.py` | | `C. supplier-build` | Input lexicon check. Replacement: Haskell. |
| `scripts/verify_agda_sync.py` | | `C. supplier-build` | Agda sync verification. Replacement: Haskell. |
| `scripts/check_*.sh` (shell, not Python) | n/a | n/a | Out of scope for this ledger. |
| `scripts/compute_ab_metrics.py` | | `D. eval-only` | AB-eval metrics. |
| `scripts/score_blind_pairs.py` | | `D. eval-only` | Blind pair scoring. |
| `scripts/run_blind_ab_eval.py` | | `D. eval-only` | Blind AB eval driver. |
| `scripts/wave2_soak.py` | | `D. eval-only` | Soak test (wave 2). |
| `scripts/wave3_soak.py` | | `D. eval-only` | Soak test (wave 3). |
| `scripts/wave4_soak.py` | | `D. eval-only` | Soak test (wave 4). |
| `scripts/wave5_soak.py` | | `D. eval-only` | Soak test (wave 5). |
| `scripts/mutate_governance_rebuild_failure.py` | | `D. eval-only` (likely) | Negative-path test. |
| `scripts/promote_state_to_authoritative.py` | | `D. eval-only` (likely) | State promotion test. |
| `scripts/normalize_freeze0_json.py` | | `D. eval-only` (likely) | JSON normalisation. |
| `test/test_import_ru_opencorpora.py` | | `E. test-only` | Python import test. |
| `test/test_import_brain_kb.py` | | `E. test-only` | Python import test. |

**`F. dead` candidates** — to be confirmed by `git log --diff-filter=D`
and `scripts/run_*.sh` callers. Likely dead:
- (none confirmed in this pass — closure plan's Package 6 test
  audit should produce a definitive list).

## 4. The closure class hierarchy and the closure gates

| Gate | Condition for moving forward |
|---|---|
| **Gate P5-1** | `check_schema_consistency.py`, `check_schema_contract.py`, `sync_embedded_sql.py` all moved to Haskell. CI gate replaced. Old `.py` files deleted. |
| **Gate P5-2** | `services/morphology/server.py` replaced by Haskell morphology parser. HTTP call sites in Haskell code updated. Server process terminated; port freed. |
| **Gate P5-3** | `scripts/http_runtime.py` confirmed not invoked by any gate (after Gate P5-1 and the original runtime perimeter work). File deleted. |
| **Gate P5-4** | All `C. supplier-build` Python either replaced by Haskell or moved to `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` with explicit supplier-only retention justification. |
| **Gate P5-5** | All `D. eval-only` Python either moved to `scripts/eval/` with a clear non-authority marker, or moved to a separate research repo. |
| **Gate P5-6** | `test/test_*.py` deleted; coverage is in Haskell `Test/Suite/`. |
| **Gate P5-7** | `docs/PYTHON_STATUS_LEDGER.md` (this file) reads "0 canonical Python" in the **canonical** column for every entry. |

After Gate P5-7, "zero Python in canonical authority path" is
literal, not aspirational.

## 5. Per-class replacement strategy

### 5.1 `A. canonical-build` → Haskell verify/contract commands

The three `A`-class files (schema consistency, schema contract, SQL
sync) are the **first** things to close. They are small, their
logic is in the Haskell code already (the schema sources are in
`spec/sql/**`), and the Haskell replacement is a thin wrapper over
existing types.

Replacement pattern:
1. Add a `cabal run qxfx0-main -- verify-schema` subcommand that
   invokes the same checks via the Haskell-typed schema.
2. Add a `cabal run qxfx0-main -- verify-contract` subcommand.
3. Add a `cabal run qxfx0-main -- check-embedded-sql` subcommand.
4. Update `scripts/check_architecture.sh` to invoke the Haskell
   commands.
5. Delete the `.py` files; update CI to require zero `python3`
   invocations on the canonical path (`grep -r "python3" scripts/`
   must return zero matches on authority-bearing scripts).

### 5.2 `B. canonical-runtime` → Haskell morphology parser

`services/morphology/server.py` is the only ACTIVE runtime Python
in the project. The Haskell replacement is a typed
`QxFx0.Lexicon.Morphology.Parser` module that exposes the same
operations without the HTTP round-trip.

Replacement pattern:
1. Profile current call sites of the morphology server.
2. Implement `QxFx0.Lexicon.Morphology.Parser` (pure Haskell,
   base-only dependencies) with the same `parse :: Text -> Maybe
   MorphologyInfo` API.
3. Replace each HTTP call with a direct call.
4. Delete `services/morphology/server.py`; release the port.
5. Document the change in `CHANGELOG.md`.

### 5.3 `C. supplier-build` → Haskell IR / validators

Supplier Python is **supplier-only** and not on the authority path.
The closure plan does not require its immediate removal; it does
require that suppliers be moved to `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md`
with explicit retention justification (or replaced by Haskell).

### 5.4 `D. eval-only` → keep, but mark

Eval Python is non-authority by definition. The closure plan
recommends moving it to a separate `scripts/eval/` subdirectory with
a `NON_AUTHORITY.txt` marker, OR moving it to a separate research
repo. The decision is per-script and recorded in
`PYTHON_SUPPLIER_ALLOWLIST.md`.

### 5.5 `E. test-only` → delete

Python tests duplicate Haskell test coverage. Delete.

## 6. The `PYTHON_SUPPLIER_ALLOWLIST.md` (Package 5 follow-up)

The closure plan requires that any Python file remaining after
Gate P5-7 carry an explicit allowlist entry. The format:

```markdown
### `scripts/<file>.py`
- retention justification: <why supplier is justified>
- replacement target: <Haskell command or "PENDING">
- replacement deadline: <date or "PENDING">
- removal criterion: <specific gate that, when met, deletes this>
```

This file is **not** written yet; it is a follow-up to Package 5
that lands at Gate P5-4.

## 7. Replacement commands (proposed Haskell surface)

| Python script | Haskell command | Module | Notes |
|---|---|---|---|
| `check_schema_consistency.py` | `cabal run qxfx0-main -- verify-schema` | `QxFx0.Internal.Schema.Verify` | new module |
| `check_schema_contract.py` | `cabal run qxfx0-main -- verify-contract` | `QxFx0.Internal.Schema.Verify` | same module |
| `sync_embedded_sql.py --check` | `cabal run qxfx0-main -- check-embedded-sql` | `QxFx0.Internal.SQL.Check` | new module |
| `services/morphology/server.py` (HTTP) | `QxFx0.Lexicon.Morphology.Parser` (in-process) | new module | per §5.2 |

The exact module paths are TBD and require a small Package 5
follow-up PR.

## 8. Acceptance criteria for Package 5 closure

- [ ] `scripts/check_schema_consistency.py`, `scripts/check_schema_contract.py`, `scripts/sync_embedded_sql.py` replaced by Haskell and deleted.
- [ ] `services/morphology/server.py` replaced by Haskell and the HTTP call sites updated.
- [ ] `scripts/http_runtime.py` confirmed not invoked and deleted.
- [ ] All `C. supplier-build` Python either replaced by Haskell or moved to `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` with explicit retention justification.
- [ ] All `D. eval-only` Python moved to `scripts/eval/` with `NON_AUTHORITY.txt` marker OR moved to a research repo.
- [ ] All `E. test-only` Python deleted.
- [ ] `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` exists and is empty (i.e. no Python remains on the authority or supplier path; all Python that remains is eval-only with explicit marker).
- [ ] CI gate: `grep -r "python3" scripts/ | grep -v NON_AUTHORITY.txt` returns zero matches in authority-bearing paths.
- [ ] `qxfx0-test-fast`, `qxfx0-test-slow`, `qxfx0-test`, `check_architecture.sh`, `release-smoke.sh`, `verify.sh` all pass with **zero** Python invocations.
