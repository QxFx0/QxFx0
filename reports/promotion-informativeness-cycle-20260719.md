# Promotion Informativeness Cycle - 2026-07-19

## Human Decision

- Previous candidate `b597843143137551d6ebff0653f04c79c795db5cdd05aa3be1bdb3f28e2869e4` (`история related_to прошлое`) is recorded as `human_rejected_low_information`.
- No production overlay was activated.

## Informativeness Gate

- Added to local promotion gates as a separate versioned check.
- Rejects tautologies and topic paraphrases.
- Requires novel object/relation/constraint information.
- Computes semantic gain as one minus maximum canonical-atom overlap with the topic's base predicates.
- Threshold: `0.75`.
- Current history candidate measured `semantic_gain=0.6666666666666667` and failed with `no_novel_object_relation_or_constraint`.

## Targeted Learning

- Gaps: `надежда`, `власть`, `одиночество`.
- Jobs: 16 targeted requests, all succeeded.
- Governed evidence: 6 admissions and 6 corroborations.
- Corroborated shapes included:
  - `надежда presupposes будущее`, support `2`;
  - `надежда depends_on пространство`, support `2`;
  - `власть depends_on общественный договор`, support `2`;
  - `одиночество signals потребность`, support `3`.

## New Promotion Chain

- Snapshot: `promotion-snapshot-47d1956edf4a02833e1fd71c8bef589707e8661d03953e756835acc9501ebfeb`.
- Runtime edges: `17713`.
- Candidates: `18`.
- Informativeness/local gates eligible: `1`.
- Draft overlay: `overlay-e320cf2d8184360c1908b5d78f4ee63d9b867ba77938a8083bcc9b0c51c933f1`.
- Eligible predicate: `надежда presupposes будущее`.

## Renderer A/B

- Report: `/tmp/qxfx0-v4-runtime-ab-informative-20260719.json`.
- Automated gate: `false`.
- Overlay usage: `0`.
- Runtime failures/timeouts/conflicts/unsupported: `0/0/0/0`.
- Base top-1 selected `надежда ориентирует на возможность будущего`; overlay `надежда предполагает будущее` scored `0` and lost before attribution.

## Decision

The informative candidate is not useful as a renderer overlay yet. It remains a draft and is not activated. The failure is an explainable selector relevance loss against a stronger base predicate, not an attribution failure. No further broad learning or production activation was performed.
