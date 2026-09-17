# Composer design — the system's own meaning assemblies

Status: **DESIGN v1 + skeleton** (operator decisions 2026-09-17).
Runtime wiring explicitly deferred (shadow discipline).

## Operator decisions (2026-09-17)

1. **Assembly unit**: `PredicateTerm` (`QxFx0.Semantic.Composition`:
   head + relation pairs + modifiers + negation). An assembly is a
   composed term, not concatenated prose.
2. **Rating labels**: two are enough for now — `assembly_coherent`
   (is the assembly coherent for a human?) and `assembly_grounded`
   (is the path honest: every bridge step really exists?),
   each in {0,1,2}. No novelty label yet.
3. **No hop cap**: delirium control is the rater's job, not a
   structural guillotine. `PathFinder`'s current 1–3-edge cap stays
   as-is for the legacy path; the composer records `asmPathLen`
   and lets rating decide.

## Bridge rule (v1, implemented in skeleton)

Two source terms assemble iff they share a concept `c`
(`termConcepts` intersection, non-empty) AND the sources differ
(same topic + equal term is rejected — the G2 non-tautology
analogue). No shared concept → `Nothing` (honesty over coverage:
no bridge is invented).

Composed term: head = A's head (B's if A is headless); rels/mods =
union; neg = OR (never silently affirm a negated source; the
over-negation bias is calibration-open, rating decides).

Provenance: `asmSources` carries both (topic, surface) pairs;
`asmBridge` the shared concept; `asmPathLen` = 1 in the skeleton
(shared atom). Network BFS + `PathProof` wiring is the next phase
(`PathFinder` builds 1–3-edge proofs; `validatePath` G1–G5 stays
the admission authority — the composer never bypasses the gate).

## Layering (deliberate)

- `QxFx0.Semantic.Assembly`: pure term composition (this landing).
- Prose realization: deferred to the shim/realizer phase, which owns
  morphology. The skeleton exposes `assemblyProposition` (head +
  relation pairs in lemma form), not prose — lemma-form prose would
  be a lie about inflection.
- Rendering contract (already landed): any assembly surface is
  non-corpus by construction → `isCorpusPredicate` is False →
  «Гипотеза:» framing automatic. The composer cannot produce false
  authority even when wired.
- Rating corpus extension: stratum `assembly_pairs` with
  `assembly_coherent` / `assembly_grounded` labels (schema in
  `CALIBRATION_CORPUS.md` stays {0,1,2}-shaped; add when rated).

## Cutover (staged, same discipline as Composition)

1. Shadow: module + tests (this landing). No runtime calls.
2. Wiring behind `selectorMathVersion` bump + corpus win on
   human-labelled `assembly_pairs` (coherent ≥ 2 majority).
3. Never: bypass of `GeneratedPredicateGate.validatePath`.
