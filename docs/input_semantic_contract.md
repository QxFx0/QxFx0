# Input Semantic Contract

## Purpose

`QxFx0` input parsing must not route directly from raw keywords.  
The runtime contract is:

1. `raw_text`
2. `WordMeaningUnit[]`
3. `UtteranceSemanticFrame`
4. `InputPropositionFrame`
5. route/family decision

This document defines the minimum contract expected from the input layer.

## WordMeaningUnit

`WordMeaningUnit` is the minimal classified unit for a token:

- `surface_form`
- `lemma`
- `part_of_speech`
- `morph_features`
- `syntactic_role`
- `semantic_classes`
- `discourse_functions`
- `ambiguity_candidates`
- `confidence`

Invariants:

- every token must produce exactly one `WordMeaningUnit`;
- `lemma` must be non-empty;
- `confidence` must be in `[0.0, 1.0]`;
- `ambiguity_candidates` must contain at least one element.

## UtteranceSemanticFrame

`UtteranceSemanticFrame` is the normalized meaning frame for one user turn:

- `normalized_text`
- `word_units`
- `clause_type`
- `speech_act`
- `polarity`
- `topic`
- `focus`
- `agent` / `target`
- `semantic_candidates`
- `ambiguity_level`
- `route_hint`
- `confidence`

Invariants:

- frame confidence must be in `[0.0, 1.0]`;
- `route_hint` must always be present, even if `unknown`;
- `route_hint` from frame is advisory, legacy proposition detection is fallback.

## Route Priority

The routing contract is:

1. semantic frame hint (high-confidence patterns),
2. existing proposition detector fallback,
3. safety fallback (`CMClarify`/`CMGround`) as last resort.

The frame layer must preserve old behavior where no reliable new signal exists.

## v1 Scope

v1 guarantees:

- school-level POS coverage;
- essential service words (`не`, `ли`, `если`, `или`, `потому`);
- intent classes used by current runtime:
  - dialogue invitation,
  - concept knowledge question,
  - self-state question,
  - generative prompt,
  - contemplative short input,
  - misunderstanding report,
  - world cause,
  - location formation,
  - comparison plausibility.

v2 extends this with richer syntax graph, better ambiguity resolution, and broader colloquial coverage.
