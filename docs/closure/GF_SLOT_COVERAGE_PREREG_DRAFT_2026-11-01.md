# Pre-registration — GF slot coverage for the release corpus (2026-11-01, S1 signed 2026-11-02)

- **Status**: **S1 signed (scope = option B, 207 rows). S2–S3 still open.**
  Nothing has been implemented or changed yet; the slot table, the generated
  Haskell and the frozen M7 admissible sets are untouched.
- **Predecessor**: `docs/closure/M7_FALLBACK_CONTENT_REVIEW_2026-11-01.md`
  (14-row content review; measured coverage 79/11 997 = 0.66%).
- **Why this is not a bug fix**: adding slots changes which predicate is
  emitted for a turn, therefore changes surfaces, therefore requires a new
  admissible-set pre-registration. The frozen `m7_admissible_predicates.tsv`
  stays as the record of what passed on 2026-10-31; it must not be edited.

## The defect

`buildGroundedPlan` prefers a GF-mapped predicate over the selector's own
choice:

```
selected = if null mappedSelected then originalSelected else mappedSelected
```

(`src/QxFx0/Semantic/ResponsePlan.hs`, `candidatesForTopic`). So whenever the
selected predicate lacks a slot, the system quietly replaces its own content
decision with the highest-ranked *mapped* predicate for the same topic —
14 of 30 anchor turns in the confirmatory packet.

Measured shape of the gap (against the *merged* runtime corpus: 172 seed topics
from `Content.hs` + 4 036 distinct curated topics = 4 070 topics, 12 000
predicate rows / 11 997 distinct surfaces):

| scope | predicate rows | with slots | coverage |
|---|---:|---:|---:|
| merged runtime corpus | 12 000 | 79 | 0.66% |
| 30 anchor topics | 286 | 79 | 28% |
| 15 held-out pilot topics | 96 | 0 | 0% |

The 84-row slot table's 30 distinct `subject_ru` values are exactly the 30
release-corpus topics. It was built for the release packet, not for the runtime
corpus, and only 79/84 rows match a corpus predicate verbatim.

## Scope options considered

| option | new rows | effect | decision |
|---|---:|---|---|
| A — the 14 observed fallbacks only | 14 | removes the fallback exactly on the 2026-10-31 packet; fragile — selection is Field-dependent, so a different session state re-selects an unmapped predicate | rejected |
| **B — anchor-complete** | **207** | every predicate of the 30 anchor topics is mapped; the fallback cannot fire there at all | **SIGNED (S1, 2026-11-02)** |
| C — B + pilot held-out | 303 | adds the 15 held-out topics (96 rows, 0 mapped today) | deferred until B's mechanics are proven |
| D — corpus-wide | ~11 900 | a project, not a batch | not started |

**S1 decision: option B, 207 rows.** A was rejected because it optimises for
one recorded run: repeating «что такое свобода?» three times in one warm
session already produced two different predicates (`предполагает возможность
выбора`, then `ограничена ответственностью`), so the 14 observed rows are a
sample of the selection function, not its range. B is 207 rows — large, but it
is the first scope where the fallback is structurally impossible rather than
merely rare. C follows only after B proves the authoring mechanics.

If 207 rows is too much for one batch, split B by topic groups of ~30 rows and
keep the same bars for each group; do not ship a partial set without saying
which topics are still unmapped. The signed scope is still "all 207", so a
partial landing must carry an explicit list of the topics left unmapped.


## Hard precondition before any row is added

A slot row is only admissible if its triple **linearizes**. The failure mode is
silent and worse than the current fallback: once a predicate has slots, the
mapped fallback stops applying (`mappedSelected` is no longer empty), and if GF
cannot realise the triple the turn falls through to the plain text path — i.e.
we would trade a grammatical substitute for an unlinearizable claim.

Therefore every candidate row must satisfy, mechanically:

1. `subject_id`, `relation_id`, `object_id` each exist as a lexeme in
   `spec/gf/QxFx0Lexicon*.gf` (checked by `rg` in a script, not by eye);
2. the generated `SemanticSlots.hs` compiles and the row's constructor appears
   in it;
3. a GF round-trip on the assembled sentence succeeds. Note the measured state
   of the checker first: `scripts/check_gf_concrete_consistency.py` is **red at
   HEAD**, but not on the grammar the runtime uses. `QxFx0SyntaxRus.gf` is
   aligned with the abstract (290/290 functions). `QxFx0SyntaxEng.gf` (52 lines)
   and `QxFx0SyntaxRusColloquial.gf` (57 lines) are legacy stubs that never
   received the semantic layer (40/290 functions each, no `SemanticSubject`
   lincat) and are not compiled: `scripts/compile_gf_grammar.sh` builds only
   `QxFx0SyntaxRus.gf`. The checker still compares all three, so it reports
   250 "missing" functions per stub, and `Gate 9` in `scripts/ci_gate_contract.sh`
   is **advisory**, so CI never saw it either.
   Consequence for this batch: use the **Rus concrete only** plus one explicit
   linearization per row, and do not widen the stub drift. The real risk is the
   converse: because the checker is permanently red for known reasons, it cannot
   flag a *new* Rus drift. Scoping it to the compiled concrete (or teaching it
   to skip stubs) is a two-line change and should land before the batch, with a
   test that a missing Rus function still fails;
   **resolved 2026-11-06**: the checker now defaults to the compiled Rus
   concrete, `--all-concretes` keeps the legacy drift measurable, and
   `--self-test` (12 cases) plus a real-tree Rus case are invoked from
   `scripts/check_generated_artifacts.sh`. Red check: deleting
   `SubjectSvoboda` from a temp copy exits 1; the real tree exits 0. Gate 9
   is still advisory in the core profile — the checker can now flag a new Rus
   drift, but making it a hard gate is a separate CI decision;
4. the emitted `source_ru` is byte-identical to the corpus predicate (this is
   what makes the lookup fire), and `subject_ru + " " + relation_ru + " " +
   object_ru` concatenates back to it exactly — measured to hold for 84/84
   existing rows (see the S3 cost model below).

If a row cannot pass 1–4 within the authoring budget, it is **dropped, not
approximated**. Dropping a row is not a failure of the batch; inventing a
near-miss surface is (it re-creates the 51-row mismatch problem above).

## Bars (S2 — still open, not yet signed)

Run the same 30-prompt strict/isolated packet as `m7-gf-confirm-20261031` and
the same checker, with a **new** admissible-set file (new sha256), because the
emitted predicates will change.

| # | bar | threshold |
|---|---|---|
| 1 | gate pass | 30/30 (unchanged rule) |
| 2 | `gf_mapped_fallback` count | ≤ 2 (from 14) |
| 3 | turns whose emitted predicate = the system's own selection | ≥ 28/30 |
| 4 | new rows that fail the 4-point realizability check | 0 |
| 5 | determinism | surfaces and predicates byte-identical across two runs |
| 6 | full test matrix on the landing tree | every suite green, same counts ±new pins |
| 7 | content review of the changed turns | no new `drift`/`weak` row vs today's 14-row verdicts |

Bar 3 is the point of the exercise; bar 2 is the mechanism. Bar 7 exists
because "emitted the system's own choice" is not automatically better — the
14-row review found 5 harmless, 7 acceptable, 1 drift, 1 weak, and that
judgement has to be redone on the *new* emitted set, not assumed.

## S3 cost model, measured (2026-11-02, evidence only — no decision)

The open question is "authoring GF lexemes for the new objects: in scope or
not". Measured against the GF sources, the term "lexeme" is misleading: every
semantic slot is a literal string, and the proposition is plain concatenation.

```
lincat  SemanticSubject / SemanticRelation / SemanticObject = { s : Str }
lin     MkSemanticPredicate subject relation object =
          { s = subject.s ++ " " ++ relation.s ++ " " ++ object.s }
```

So a row needs three strings, not a morphology entry. Current inventory:

| item | count | note |
|---|---:|---|
| `Subject*` constructors | 30 | exactly the 30 anchor topics — no new subject needed |
| `Relation*` constructors | 48 | 48 distinct relation strings used by the 84 rows |
| `Object*` constructors | 83 | 83 distinct object strings for the 84 rows |

All 84 existing rows satisfy `subject_ru + " " + relation_ru + " " + object_ru
== source_ru` **exactly** (84/84). Exact reconstruction is the convention, not
an accident, so a new row's three strings must concatenate to the corpus
surface byte for byte.

Breakdown of the signed 207-row set:

| bucket | rows | what it needs |
|---|---:|---|
| relation string already exists (17 distinct relations used) | 116 | 114 new object strings (115 distinct; 1 already exists) |
| relation string does **not** exist (57 distinct verb forms) | 91 | 57 new relation strings + 86 new object strings |
| **total** | **207** | **200 new object lines, 57 relation lines, 207 TSV rows** |

Two measured risks for S3:

1. **Agreement.** 23 of the 91 new-relation rows use a relation head ending in
   -а/-я (`основана`, `направлена`, `формируется`, `измеряется`, …). Those
   encode gender or number and cannot be reused across subjects mechanically —
   the same relation string under a different subject can become ungrammatical.
   The other 68 use present-tense 3rd-person forms that are subject-invariant
   for singular subjects.
2. **Corpus typos leak into the strings.** While measuring this, two more
   misspellings surfaced in the same corpus: `воспоминание преобразкет` (line
   147, should be «преобразует») and `доверие стройтся` (should be «строится»).
   A row whose `source_ru` contains a typo would put that typo into the emitted
   surface. They must be fixed (or the rows excluded) before authoring, which is
   a data decision like `bec1d19` was.

What this changes about S3: the question is **not** "can we author ~45 new
lexemes" (there is no lexeme inventory to extend) but "do we accept 257 new
GF string lines (200 objects + 57 relations) plus 207 table rows, with the
agreement and typo risks above, in one batch or in topic groups". The 4-point
realizability check in the previous section still applies, and point 3 (GF
round-trip per row) is what catches both risks.


## What this does not do

- Does not make new topics answerable with GF. Outside the 30 anchors the
  unmapped text path still governs (option B/C territory).
- Does not fix the corpus typo (`curated_predicates.jsonl:148`,
  «прошл**и**м» → «прошл**ы**м»); that is a separate one-character data commit,
  landed on its own.
- Does not change the gate rule, the corpus prompts, or the frozen admissible
  sets from 2026-10-31.

## Open questions for the owner

S1 is signed (option B, 207 rows). Two items remain open and both block the
batch:

1. **S2** — bars 1–7 above: accept, or set different values before
   implementation? Bar 3 (emitted predicate = the system's own choice, ≥ 28/30)
   is the point of the exercise; bar 2 is only its mechanism.
2. **S3** — the batch needs 200 new `Object*` strings, 57 new `Relation*`
   strings and 207 TSV rows (measured above; all slots are literal strings, and
   the 30 subjects already exist). Is that in scope as one batch, or should it
   land in topic groups? The choice decides whether the 4-point realizability
   check can *fail* a row (single batch) or merely *defer* it to the next group.
   Two data fixes must precede authoring: `воспоминание преобразкет` and
   `доверие стройтся`.
