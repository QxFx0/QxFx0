# QxFx0 Lexicon Stabilization Implementation Plan

## Scope

This plan compresses `research_packs/research.txt` into a staged implementation path that strengthens vocabulary without expanding architecture.

Current pipeline stays fixed:

```text
raw input -> parseProposition -> collectAtoms -> runSemanticLogic -> runFamilyCascade -> render/finalize
```

## Non-Goals

- No AST parser.
- No dependency parser.
- No theorem prover.
- No deontic/modal/temporal logic engine.
- No LLM-as-parser or LLM-as-router.
- No new runtime boundaries.
- No new persistence tables for lexicon roles in this phase.
- No new `AtomTag` constructors unless an existing tag cannot safely approximate behavior.

## Implementation Rule

Every vocabulary item must have one primary integration role:

- `morphology`: SQL lexicon forms only.
- `semantic_cluster`: phrase trigger producing an existing `AtomTag`.
- `parser_keyword`: route cue in `ParserKeywords`.
- `focus_stopword`: operator/connective that must not become focus.
- `focus_marker`: phrase that points to the semantic complement.
- `corpus_case`: invariant regression only.

If an item needs more than one role, add it in the safest role first and promote later only after tests.

## P0: Stabilize Logical Operators And High-Load Prose

### SQL Lexicon

Add high-signal Russian lemmas only. The current lexicon exporter validates Cyrillic forms, so English terms stay in parser/corpus rather than SQL.

Initial domains:

- logical structure: `посылка`, `вывод`, `заключение`, `импликация`, `квантор`
- proof/evidence: `доказательство`, `обоснование`, `свидетельство`, `критерий`
- distinction: `объяснение`, `дистинкция`, `разница`, `разграничение`
- contradiction/refutation: `опровержение`, `контрпример`, `противоречие`, `несовместимость`
- modality/agency: `необходимость`, `достаточность`, `возможность`, `обязанность`, `разрешение`, `способность`, `право`

### Semantic Clusters

Add a small set of clusters, mapped to existing tags:

- `LogicalInference` -> `Verification`
- `ProofRequest` -> `Searching`
- `DistinctionRequest` -> `Doubt`
- `CounterexampleRequest` -> `Contradiction`
- `ObligationDuty` -> `AgencyLost`
- `PermissionRight` -> `AgencyFound`
- `TemporalOrdering` -> `Verification`
- `ContrastCorrection` -> `Doubt`

### Parser Keywords

Add phrase-level cues to existing keyword groups:

- definition: `аксиома`, `теорема`, `квантор`, `definition`, `syllogism`
- distinction: `необходимое условие`, `достаточное условие`, `necessary condition`, `sufficient condition`
- ground: `следует из`, `влечёт`, `обоснование`, `follows from`, `entails`
- hypothesis: `предположим`, `допущение`, `assumption`, `suppose`
- confront: `контрпример`, `опровержение`, `не следует из`, `does not follow`
- clarify: `посылка`, `вывод`, `заключение`, `premise`, `conclusion`

### Focus Rules

Extend focus stopwords with operators and connectives:

- modal: `должен`, `может`, `следует`, `нужно`, `необходимо`, `достаточно`
- temporal: `когда`, `пока`, `до`, `после`, `прежде`, `затем`
- contrast: `но`, `однако`, `зато`, `хотя`
- EN: `must`, `should`, `may`, `can`, `when`, `while`, `before`, `after`, `however`, `therefore`

Extend focus markers with phrases that point to complements:

- `имеет право`, `имеет основание`, `является причиной`, `является условием`
- `необходимо для`, `достаточно для`, `следует из`
- `has the right`, `has reason`, `is necessary for`, `is sufficient for`, `follows from`

### Local Suppression

Only local rules:

- `не устал` suppresses exhaustion.
- `не могу` is agency loss; `могу не` is not.
- `не в состоянии` is agency loss.
- `не имеет права` is permission denial, not possession.
- `не следует из` is non-entailment, not generic advice.
- `следует из` is entailment; `следует сделать` is obligation/recommendation.
- `не X, а Y` shifts focus toward `Y`.

### Corpus

P0 corpus additions must verify:

- ordinary logic/modality prose does not produce `CMRepair`;
- operators/connectives do not become focus;
- contrast and negation do not invert route pressure;
- Nix/tool degradation does not masquerade as semantic repair.

## P1: Expand Domains Carefully

- Epistemology: knowledge/evidence/truth/error.
- Ontology: being/essence/form/cause/modality.
- Ethics/agency: responsibility/permission/obligation/coercion.
- Dialogue acts: define/explain/distinguish/justify/refute/continue.
- Affective states: add only with negation tests to avoid over-triggering repair.

## P2: Soak And High-Load Regression

- 100+ invariant cases.
- Long Russian philosophical paragraphs.
- RU/EN parity pairs.
- punctuation/no-punctuation variants.
- long-session semantic-load run.

## Rejection Criteria

Do not merge a lexicon expansion if it:

- increases `CMRepair` on non-distress logical prose;
- makes modal/temporal/connective tokens become focus;
- introduces cluster names that map only to `CustomAtom`;
- relies on rendered-text goldens;
- adds architecture to compensate for missing tests.
