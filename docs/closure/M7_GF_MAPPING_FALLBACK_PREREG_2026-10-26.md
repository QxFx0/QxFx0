# Pre-registration — GF mapped-predicate fallback (2026-10-26)

- **Status**: IMPLEMENTED in the working tree and verified on the 30-prompt
  packet (2026-10-26): `AuthorityCanonical` 30/30, `AuthorityShim` 0/30,
  `unmapped_curated_predicate` 0/30. Exact golden remains 5/30 and M7 remains
  OPEN. Result: `docs/closure/M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`.
- **Trigger evidence**: `docs/closure/M7_BOUNDED_PACKET_2026-10-26.md`.
- **Scope**: response-plan predicate selection only. No routing-family, crisis,
  safety, morphology, or GF-grammar change.
- **Owner decision**: mapped-predicate fallback chosen 2026-10-26.

## Problem

The 30-prompt governed GF release-corpus packet produced 30/30 `CMDefine`
routing but only 16/30 `AuthorityCanonical`. Fourteen turns recorded:

```text
gf_response_plan:unmapped_curated_predicate:<predicate>
```

and rendered as `AuthorityShim` exploratory surfaces (`Гипотеза: ... Следующий
ход: вернуться к открытому вопросу ...`). The selected curated predicates are
absent from `spec/gf/curated_predicate_slots.tsv` and therefore from
`lookupCuratedPredicateSlots`; `QxFx0.Semantic.ResponsePlan.GF` correctly
rejects them rather than smuggling text into GF.

The affected predicates are:

1. `воспоминание восстанавливает прошлое в настоящем`
2. `сознание есть основание субъектности`
3. `доверие открывает возможность сотрудничества`
4. `справедливость требует равенства возможностей`
5. `время устанавливает границы между прошлим и будущим`
6. `история складывается из событий и их интерпретации`
7. `язык выражает и структурирует мысль`
8. `смерть выражает конечность бытия`
9. `одиночество обнаруживает границу между я и другими`
10. `любовь преодолевает границу между я и другим`
11. `труд выражает целенаправленное усилие`
12. `покой выражает отсутствие напряжения`
13. `власть это способность и возможность влиять на поведение людей`
14. `молчание выражает позицию через отсутствие слов`

## Proposed behavior

When the response-plan builder selects predicates for GF rendering:

1. Build a GF-safe selector view: for each topic, keep only predicates whose
   `spRu` has `lookupCuratedPredicateSlots` `Just`.
2. Score/select from that view with the existing `selectPredicates` function
   (same Field affinity, activation bonus, floor, tie-break, and determinism).
3. If the GF-safe view yields at least one candidate for a topic, use it; the
   original top-1 predicate is rejected and the highest-ranked mapped
   predicate for the same topic (under the existing `selectPredicates`
   ordering) is used.
4. If the GF-safe view yields no candidate for a topic, retain the current
   behavior for that topic (the existing shim path); do not invent a predicate
   and do not cross topics.
5. Do not add or edit GF slots/constructors in this slice. The fallback uses
   predicates already present in `curated_predicate_slots.tsv`.

## Trace contract

A fallback is visible in `trcResponsePlan.rspDerivation`:

- add a derivation entry with `pdRule = "DeriveGfMappedFallback"`;
- `pdReason` states that the original selected predicate lacks GF slots;
- `pdRejectedAlternatives` contains the original predicate surface;
- `pdPredicateRefs` contains the mapped replacement.

Acceptance requires `trcFallbackReason = null`, `trcLinearizationOk = true`,
`trcAuthorityClass = AuthorityCanonical`, and the fallback rule present only
where a replacement occurred. No new `TurnReplayTrace` field is required.

## Non-goals

- No change to `gf_response_plan:unmapped_curated_predicate` rejection itself;
  the GF layer must keep failing closed for genuinely unmapped predicates.
- No golden re-baseline in this slice. Exact-surface acceptance is decided
  separately after the canonical-rate fix.
- No 500-prompt corpus work; that gate remains BLOCKED.
- No routing, crisis, safety, or persistence-schema change.

## Implementation (working tree, 2026-10-26)

- `QxFx0.Semantic.ResponsePlan` gained `gfMappedSelector`, which filters
  `csTopicPredicates` with `lookupCuratedPredicateSlots`.
- `candidatesForTopic` scores the filtered view with the existing
  `selectPredicates` semantics (including its floor fallback); if the view
  yields no candidate, the original selection is retained (existing shim
  path).
- `PlanCandidate.candidateGfFallback` carries the rejected original surface;
  `buildGroundedPlan` emits a `DeriveGfMappedFallback` derivation entry with
  the mapped replacement in `pdPredicateRefs` and the rejected surface in
  `pdRejectedAlternatives`.
- `DerivationRule` gained `DeriveGfMappedFallback`. `rspVersion` remains `2`:
  the enum extension is additive and old persisted plans still decode; if the
  release contract later requires a version bump for new derivation values,
  decide that separately.
- Focused test: `Test.Suite.ResponsePlan` `38/38` green, including mapped
  fallback, no-mapping retention, JSON round-trip, and GF addressability.
  Full unit run: `1820/1820` green.
- `gf-rel-007` isolated smoke: `AuthorityCanonical`, `trcFallbackReason=null`,
  `rspDerivation` contains `DeriveGfMappedFallback` with the original
  `воспоминание восстанавливает прошлое в настоящем` rejected.

## Tests and acceptance

- Unit: a topic whose top-1 predicate is unmapped but whose second predicate
  is mapped selects the mapped predicate deterministically; a topic with no
  mapped predicate retains the current shim behavior.
- Unit: fallback derivation entry is present and names the rejected predicate.
- Integration: re-run the 30-prompt governed GF packet with strict runtime and
  isolated sessions; require `AuthorityCanonical` 30/30 and
  `unmapped_curated_predicate` 0/30.
- Record exact golden match rate after the fix; do not silently rewrite
  `spec/gf/release_corpus_golden.tsv`.

### Acceptance outcome (2026-10-26 run)

- `AuthorityCanonical` **30/30**, `AuthorityShim` **0/30**,
  `unmapped_curated_predicate` **0/30** — the pre-registered mapping gate
  passes.
- `DeriveGfMappedFallback` appears on exactly the 14 pre-fix unmapped topics.
- Exact golden **5/30** (pre-fix 4/30; `gf-rel-016` added). The golden
  acceptance rule is **not** decided by this pre-registration, so M7 stays
  OPEN.
- One fallback-selected predicate exposes a pre-existing GF concrete-syntax
  case defect (`ObjectAktObrashcheniya`, instrumental instead of nominative);
  it is out of scope here and recorded in the result document.

## Risks and rollback

- Content for the 14 topics will change to an existing mapped predicate; review
  the surfaces for definitional adequacy before accepting.
- The change is local to the response-plan selection path and is reversible by
  reverting the commit; no persisted state or schema migration is involved.
- If the packet still has shims, stop and diagnose rather than widening the
  fallback across topics.
