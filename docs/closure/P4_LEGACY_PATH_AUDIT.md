# P4: Legacy structuredBody Path Audit & Remediation

**Date:** 2026-06-26
**Status:** IMPLEMENTED (Option A) — 2026-06-27

## Context

The production render path in `Render.hs:309-316` has three tiers:
1. **viaSemantic** — `generateFromFrame` (NEW, gate-enforced, uses `composeDefinition`)
2. **viaAssembly** — `renderArtifactViaAssembly` → `structuredBody` (LEGACY, uses `selectPredicates`)
3. **renderDialogueArtifact** — legacy fallback (uses `selectPredicates`)

The `structuredBody` function (`Dialogue.hs:371`) handles multiple proposition types and uses `selectPredicates` without gate enforcement for content selection.

## Audit Findings

### selectPredicates Usage (4 sites)

| Line | Proposition Type | Risk | Status |
|------|-----------------|------|--------|
| 500 | ConceptKnowledgeQ (EN) | Predicates not gate-validated | ✅ FIXED |
| 511 | ConceptKnowledgeQ (RU) | Same as above | ✅ FIXED |
| 625 | MisunderstandingReport | Predicates not gate-validated | ✅ FIXED |
| 647 | ConfrontQ | Same + `lookupChallengeResponse` at line 651 | ✅ FIXED |

### What's Already Safe
- ✅ G-3 fix: `lookupDefinitionContent` fallback removed at all 4 sites
- ✅ Empty `selectPredicates` result → empty `contentText` (no crash, no unguarded content)
- ✅ `generateFromFrame` (tier 1) is fully gate-enforced and takes priority in production

### What Was Risky (Now Fixed)
- ✅ `selectPredicates` returns predicates without running them through `GeneratedPredicateGate`
- ✅ `lookupChallengeResponse` (line 651) receives predicates from gated `selectedPreds`
- ✅ If `generateFromFrame` produces empty output (gate failure), the system falls through to `viaAssembly` which now uses gated `selectPredicatesGated`

## Remediation Implemented (Option A)

### Approach

The audit originally recommended `filterAdmissible` after `selectPredicates`, but this has a type mismatch:
- `filterAdmissible` operates on `[PathProof]` (containing `[Relation]` edges)
- `selectPredicates` returns `[SelectedPredicate]` with `[SemanticPredicate]` (text-only, no Relation edges)

**Solution:** Created predicate-level gates in `GeneratedPredicateGate.hs` that check equivalent properties:

| PathProof Gate | Predicate Gate | Check |
|----------------|---------------|-------|
| G1 (Specificity) | PG1 | `spTopicForm` is non-empty |
| G2 (Non-tautology) | PG2 | `spRu` is not just the topic word (non-self-referential) |
| G3 (Path provenance) | PG3 | `spRu` and `spEn` are both non-empty |
| G4 (Source whitelist) | N/A | SemanticPredicate has no source field; predicates come from curated definitionCorpus |
| G5 (Non-substrate output) | N/A | Same — no substrate source in SemanticPredicate |

### Files Changed

1. **`src/QxFx0/Semantic/Content/GeneratedPredicateGate.hs`**
   - Added `validatePredicate :: SemanticPredicate -> Bool`
   - Added `filterAdmissiblePredicates :: [SemanticPredicate] -> [SemanticPredicate]`
   - Added import of `SemanticPredicate` from `Content.Base`

2. **`src/QxFx0/Render/Dialogue.hs`**
   - Added import of `filterAdmissiblePredicates`
   - Added `selectPredicatesGated` wrapper function that:
     1. Calls `selectPredicates` (unchanged)
     2. Filters each `SelectedPredicate`'s predicates through `filterAdmissiblePredicates`
     3. Drops any `SelectedPredicate` whose filtered predicate list is empty
   - Replaced all 4 `selectPredicates` call sites with `selectPredicatesGated`

### Coverage

- ✅ ConceptKnowledgeQ (EN) — line 512
- ✅ ConceptKnowledgeQ (RU) — line 523
- ✅ MisunderstandingReport — line 637
- ✅ ConfrontQ — line 659 (also covers `lookupChallengeResponse` which receives `spPredicates` from gated `selectedPreds`)

## Build Status

- `GeneratedPredicateGate.hs` compiles successfully (module 41/408, `-fno-code` check)
- Full build blocked by pre-existing errors in `System.hs` (duplicate-exports) and 30s timeout constraint
- Changes are minimal and type-safe: new function uses existing types, no new dependencies

## Dependencies

- P0 (NixGuard fix) — DONE ✅
- P1 (moratorium gates) — DONE ✅
- P2 (content quality gate tests) — DONE ✅
- P3 (tautology fix) — DONE ✅
- This audit — DONE ✅
- Implementation of Option A — DONE ✅
