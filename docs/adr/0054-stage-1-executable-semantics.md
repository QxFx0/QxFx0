# ADR-0054: Stage-1 Executable Semantics — Freedom Cluster

**Status:** Accepted
**Date:** 2026-09-29
**Accepted-By:** operator review (2026-09-29)
**Related:**
- ROADMAP.md North Star + §122 bidirectional semantic-machine doctrine
- CALIBRATION_REPORT.md: concept verification (2026-09-28), OQ1 verdict (Field ranking compliant with bounds)
- Stage-0 IR skeleton (`QxFx0.Semantic.IR`, `data/semantic_ir/gold.jsonl`, 100 rows) — ratified retroactively by this ADR (see §8)
- `docs/closure/THRESHOLDS.md`, `MATH_CHANGE_PROTOCOL.md`
- ADR-0048 (moratorium process — this record precedes the code)

---

## 1. Context

The meaning-machine thesis was verified against the codebase
(2026-09-28): the diagnosis stands (curated-utterance graph, not a
sense algebra; text-identity commitments; surface context), and the
proposed direction (executable semantics, typed proposition IR,
sense contracts, staged program) is accepted in substance with
corrections (ClaimAst is move-AST not proposition logic; revision
machinery partially exists; the self-layer does mechanistic work;
the North Star says subject).

Stage-0 landed the IR skeleton and 100 gold parses as shadow-only
types + data (zero runtime callers). Stage-1 builds the first
completed semantic domain on top of it — still shadow. No runtime
wiring in this ADR. Any cutover is a future ADR with its own
pre-registration, rater bars, and staged shadow → trace → gated
sequence per precedent (move graph, speculative/generative regimes).

## 2. Decision

### 2.1 Frozen scope: the freedom cluster

Exactly the nine topics from the concept: свобода, выбор,
возможность, ограничение, принуждение, ответственность, намерение,
осознанность, последствие. No expansion inside Stage-1. Budgets
are ceilings, not targets: 20–40 primitives, 50–100 senses,
100–200 rules, 300–500 gold utterances, 30 multi-turn scenarios.

### 2.2 Shadow artifacts (all additive, all versioned data)

- `data/semantic_ir/senses.jsonl` — one Sense contract per sense:
  id, lexicalizations, frame roles, presuppositions,
  entailments, incompatibilities, examples, counter-examples,
  provenance (all human-authored; no LLM in Stage-1).
- `data/semantic_ir/primitives.jsonl` — primitive inventory, each
  reconciled against existing atom ids (`csTopicAtoms` /
  `AtomGraph`) where possible; truly new primitives justified
  per-item in review.
- `data/semantic_ir/rules.jsonl` — strict rules (modus ponens over
  IR, proof objects) and defeasible rules (explicit scope,
  exceptions, priority).
- `data/semantic_ir/minimal_pairs.jsonl` — paraphrase/contrast/
  negation/quantifier pairs with same-or-crucially-different IR.
- `data/semantic_ir/scenarios/` — 30 multi-turn dialogues,
  IR-annotated per turn (interpretation sets, not just surfaces).
- `data/semantic_ir/cluster_freedom.jsonl` — 300–500 gold
  utterances in the Stage-0 row schema (extends, never rewrites,
  `gold.jsonl`).

### 2.3 Shadow evaluator (pure, total, deterministic)

`QxFx0.Semantic.IREval` (new module, no pipeline callers):
strict entailment (`P`, `P → Q` ⊢ `Q` with proof objects),
defeasible evaluation (scope/priority/exception handling),
presupposition and incompatibility checks, counterexample
matching. Output is JSON evaluation traces, consumed by scripts
and tests only. Sense selection among competing senses uses
semantic evidence (presupposition/entailment checks) — never
Field affinity (OQ1 boundary honored by construction).

### 2.4 Held-out evaluation FIRST

Before authoring new gold: freeze a train/dev/test split of all
Stage-1 data by id hash (60/20/20), commit split checksums.
Evaluation scripts read the test split only. This prevents
training-to-test and is verified in CI (split-integrity check).

### 2.5 Exit criteria (preset here, not after measuring)

Mechanical: gold-validate 100% (parser + validator + closedness,
as Stage-0); strict entailment accuracy ≥ 0.80 on the frozen test
split; defeasible accuracy ≥ 0.60; zero false-authority (no
derived claim presented as curated fact — checked by provenance
tags in evaluation traces).
Human: B2-style blind pairs on novel (out-of-corpus) freedom-
cluster examples, operator-rated under the landed rater doctrine
(coherent majority, zero false-authority, honest abstain allowed).
Formal M6-style second-rater quorum stays out of scope (rater
unavailable, as recorded).

### 2.6 Governance

Sense/primitive/rule changes bump a new `semanticDataVersion`
counter (data files carry it; evaluator asserts it) with a
`MATH_CHANGE_PROTOCOL.md` entry. Within Stage-1, changes are
additive-only (no id reuse, no silent redefinition; deprecate,
don't rewrite). Corpus growth outside the cluster is frozen
until exit (the 2026-09-25 lexicon doctrine stays in force for
runtime data).

### 2.7 Explicit non-goals

No selection/render/persistence wiring; no LLM anywhere in the
loop (offline candidates are Stage-6 matter); no new Self
metaphors, Field heuristics, admission types, or relation types;
no runtime corpus expansion beyond the cluster; no changes to
`definitionCorpus` authority (it stays the runtime source of
truth until a cutover ADR says otherwise).

### 2.8 Ratification

Stage-0 (IR skeleton module, gold-100, SemanticIR suite) landed
without an ADR, against the ADR-0048 moratorium. This ADR
retroactively adopts it as its foundation: the module header's
SHADOW ONLY status, the validator discipline, and the gold
schema are hereby accepted as reviewed. The process gap is
acknowledged; the fix is this record, not re-litigation.

## 3. Alternatives

- **A. Big-bang rewrite** (replace Atom/Relation/commitments now).
  Rejected: kills the green matrix (1640+/1820+/1190+), violates
  the staged-cutover precedent that delivered every regime
  without regressions.
- **B. Runtime-first wiring** (wire senses into selection now).
  Rejected: unwired semantics cannot be evaluated honestly;
  evaluation must precede authority, per the bidirectional
  doctrine (§122: both directions coupled under governance).
- **C. LLM-in-the-loop acquisition now.** Rejected: nondeterministic
  candidates need the full gate apparatus (Stage-6); Stage-1 stays
  human-authored for determinism.
- **D. Corpus-only growth, no semantics.** Fallback, not plan: if
  the exit criteria fail twice, §4 sunset fires and the program
  retreats to D honestly.

## 4. Sunset clause

If the §2.5 exit criteria are unmet after two full evaluation
rounds, Stage-1 is declared failed: shadow artifacts stay shadow
permanently, no cutover ADR may cite them, and effort returns to
corpus-level work. This bounds the program's cost and prevents
sunk-cost cutover pressure.

## 5. Consequences

Additive only: three data dirs' growth, one evaluator module,
one CI split-integrity check, extended gold validation in the
unit suite. Zero runtime risk (no callers). Review load: the
operator authors/confirms senses, rules, scenarios, and rates
the human leg. On exit, a cutover ADR becomes writable; on
sunset, nothing needs unwinding.

## 6. Quality Gate

- CI: gold-validate (all rows incl. cluster files) green;
  frozen-split checksums verified; evaluator totality pins.
- Mechanical exit numbers (§2.5) reproduced in CI, not locally.
- Human leg recorded with the landed rater doctrine; thresholds
  preset above, not fitted after.
- This ADR itself: operator review (the reviewer in this
  workflow) flips `Proposed` → `Accepted` before any Stage-1
  artifact lands.
