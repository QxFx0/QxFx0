# Python Supplier Allowlist (QxFx0_v3)

- **Status**: Active (closure-phase follow-up F-02, Package 5
  Gate P5-7)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/PYTHON_STATUS_LEDGER.md` §6
- **Related**:
  - `docs/AUTHORITY_BOUNDARY.md` (2026-05-26)
  - `docs/PYTHON_STATUS_LEDGER.md`

## 0. Why this file exists

The closure plan's Package 5 Gate P5-7 says: "PYTHON_STATUS_LEDGER.md
reads `0 canonical Python` in the **canonical** column for
every entry." The ledger is now closure-phase; this file is
its companion: an explicit allowlist for any Python that
**remains** after Gate P5-7.

The file's content at Gate P5-7 is **empty**. If it is not
empty, every entry carries:

- `path` — relative to the project root.
- `class` — one of `supplier-build`, `eval-only`, `test-only`.
  (`canonical-build` and `canonical-runtime` are not allowed.)
- `retention justification` — why this Python is justified.
- `replacement target` — the Haskell command or "PENDING".
- `replacement deadline` — date or "PENDING".
- `removal criterion` — the specific gate that, when met,
  deletes this.

## 1. The allowlist

| Path | Class | Retention justification | Replacement target | Replacement deadline | Removal criterion |
|---|---|---|---|---|---|
| _empty_ | — | — | — | — | — |

**Empty allowlist is the closure goal.** Any entry below this
line is an open retention; it must be reviewed at every
closure-plan pass.

## 2. The pre-closure inventory (transition reference)

This section is the **starting point** for the allowlist.
Each entry is one of:

- **DELETE** — slated for deletion in the current closure
  pass. The replacement target is given; the deadline is
  "before next release".
- **PORT** — slated for porting to Haskell. The replacement
  target is given; the deadline is "before next release".
- **KEEP** — slated for retention. The retention
  justification is given; the removal criterion is a
  specific gate.

| Path | Class | Disposition | Replacement / removal criterion |
|---|---|---|---|
| `scripts/check_schema_consistency.py` | `A. canonical-build` | PORT | `cabal run qxfx0-main -- verify-schema` (per `PYTHON_STATUS_LEDGER.md §7`); deadline before P5 Gate P5-1. |
| `scripts/check_schema_contract.py` | `A. canonical-build` | PORT | `cabal run qxfx0-main -- verify-contract`; deadline before P5 Gate P5-1. |
| `scripts/sync_embedded_sql.py` | `A. canonical-build` | PORT | `cabal run qxfx0-main -- check-embedded-sql`; deadline before P5 Gate P5-1. |
| `scripts/http_runtime.py` | `B. canonical-runtime` (legacy) | DELETE | per `PYTHON_STATUS_LEDGER.md §3`; deadline before P5 Gate P5-3. |
| `services/morphology/server.py` | `B. canonical-runtime` (active) | PORT | `QxFx0.Lexicon.Morphology.Parser`; deadline before P5 Gate P5-2. |
| `scripts/build_input_lexicon.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell IR emitter; deadline before P5 Gate P5-4. |
| `scripts/export_lexicon.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell export command; deadline before P5 Gate P5-4. |
| `scripts/generate_haskell_from_tsv.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell emitter; deadline before P5 Gate P5-4. |
| `scripts/generate_gf_from_tsv.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell emitter; deadline before P5 Gate P5-4. |
| `scripts/generate_paradigms_pymorphy2.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell morphology integration; deadline before P5 Gate P5-4. |
| `scripts/validate_paradigms.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell validator; deadline before P5 Gate P5-4. |
| `scripts/expand_*.py` (3 files) | `C. supplier-build` | KEEP (temporary) or PORT | Haskell expansion; deadline before P5 Gate P5-4. |
| `scripts/add_*.py` (2 files) | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/top_up_ru_lexicon.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/import_*.py` (2 files) | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/check_gf_concrete_consistency.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/check_input_lexicon.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/verify_agda_sync.py` | `C. supplier-build` | KEEP (temporary) or PORT | Haskell; deadline before P5 Gate P5-4. |
| `scripts/compute_ab_metrics.py` | `D. eval-only` | KEEP | moved to `scripts/eval/` with `NON_AUTHORITY.txt`; deadline before P5 Gate P5-5. |
| `scripts/score_blind_pairs.py` | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `scripts/run_blind_ab_eval.py` | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `scripts/wave*_soak.py` (4 files) | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `scripts/mutate_governance_rebuild_failure.py` | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `scripts/promote_state_to_authoritative.py` | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `scripts/normalize_freeze0_json.py` | `D. eval-only` | KEEP | same; deadline before P5 Gate P5-5. |
| `test/test_import_ru_opencorpora.py` | `E. test-only` | DELETE | deadline before P5 Gate P5-6. |
| `test/test_import_brain_kb.py` | `E. test-only` | DELETE | deadline before P5 Gate P5-6. |

**`F. dead` candidates** — TBD. The closure plan's Package 6
test audit should produce a definitive list. Until then,
no `F. dead` candidate is listed in the allowlist.

## 3. The Gate P5-7 verdict (closure)

The allowlist at Gate P5-7 reads:

```
| Path | Class | Retention justification | ... |
| _empty_ | — | — | ... |
```

This is the **closure goal**. The transition reference
above (§2) is the **pre-closure** state. The transition is:

1. Every `A. canonical-build` and `B. canonical-runtime`
   Python is **PORT**'d or **DELETE**'d before Gate P5-7.
2. Every `C. supplier-build` Python is either **PORT**'d to
   Haskell (and removed from the allowlist) or **KEEP**'d
   with a non-empty `retention justification` (and moved to
   §1 of the allowlist).
3. Every `D. eval-only` Python is moved to `scripts/eval/`
   with a `NON_AUTHORITY.txt` marker (and moved to §1 of
   the allowlist).
4. Every `E. test-only` Python is **DELETE**'d.
5. Every `F. dead` Python is **DELETE**'d.

After all five steps, §1 is the **only** Python that remains
in the project. If §1 is empty, the closure goal is met.

## 4. The CI gate

`scripts/check_architecture.sh` (or a new
`scripts/check_python_authority.sh`) is extended with:

```bash
# Find every Python file invoked by an authority-bearing script.
grep -rln "python3" scripts/ \
  | grep -v NON_AUTHORITY.txt \
  | grep -v closure/PYTHON_SUPPLIER_ALLOWLIST.md \
  | xargs -I {} \
    [ ! -f {}.allowlisted ] && echo "UNAUTHORISED PYTHON: {}" && exit 1
```

A Python file is allowlisted if:

1. It is in §1 of this file (with a non-empty `retention
   justification`).
2. It has a sibling `.allowlisted` marker file (one-line
   `echo allowlisted > path/to/script.allowlisted`).
3. The marker file is committed to git.

A Python file that fails all three is rejected at CI.

## 5. The discipline

The discipline of this allowlist is:

- **Supplier Python is allowed but justified.** A `C. supplier-build`
  Python that is hard to port to Haskell (e.g. pymorphy2 with
  many language-specific quirks) may stay supplier-only with
  a `retention justification`. But it must be in §1 of the
  allowlist.
- **Eval Python is allowed but quarantined.** `D. eval-only`
  Python is moved to `scripts/eval/` with a `NON_AUTHORITY.txt`
  marker. This is the "research" boundary.
- **Test Python is forbidden.** `E. test-only` Python is
  deleted; coverage lives in Haskell.
- **Dead Python is forbidden.** `F. dead` Python is deleted.

The allowlist is the **discipline, not the list**. The list
itself should be **empty at Gate P5-7**.

## 6. Acceptance criteria for F-02

F-02 is closed when:

- [ ] §1 of this file is empty (or every entry has a
      non-empty `retention justification` and a `replacement
      target`).
- [ ] §2 of this file has zero `A. canonical-build` and
      zero `B. canonical-runtime` entries.
- [ ] §2 of this file has zero `E. test-only` and zero
      `F. dead` entries.
- [ ] The CI gate of §4 is in place; CI is green.
- [ ] `docs/closure/PYTHON_STATUS_LEDGER.md` reads
      "0 canonical Python" in the `canonical` column for
      every entry.
