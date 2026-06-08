# P1-1: Generic Proposition Admission Refactoring Plan

## Status: 18/18 safe clones converted (COMPLETE, under equivalence lock)

### Scope correction (2026-06-05)

The original plan listed "22 identical modules". Mechanical classification
(grep for the `PreserveAmbiguous` branch + `safeTriggerLabels :: [Text]`) shows
the candidates are **three distinct shapes**, not one:

- **18 true 3-guard / label clones** — authoritative→AdmitRaw, all-safe→
  PreserveAmbiguous, else→SuppressStrong, with a `[Text]` safe-label list.
  These are the ONLY modules safely convertible to the current generic with
  zero behavior change.
- **4 two-guard variants** (`ComparisonPlausibility`, `DialogueInvitation`,
  `ExploratoryPrompt`, `GenerativePrompt`) — NO `PreserveAmbiguous` branch.
  Forcing them through the 3-guard generic would ADD a preserve path they
  never had = behavior change. Out of scope unless the generic gains an
  optional-preserve mode.
- **2 non-label-predicate** (`PhraseDecision` matches a `PropositionFallbackType`
  enum; the special frame-based `PropositionAdmission` softens a frame, not
  triggers) — the generic's `pacSafeLabels :: [Text]` cannot express their
  safe-predicate. Out of scope.

So the realistic target is **18 modules**, not 22, and the conversion is
roughly **line-neutral** per module (config boilerplate ≈ inline boilerplate at
~40 lines). The single-source-of-truth for the admission LOGIC is the real win;
the "~2000 lines removed" headline only materializes if Phase 2 (Types
templates) is done.

### Discipline: lock-then-convert (mandatory)

The 3 `pacDecision*` config fields all share one decision type per module, so a
miswired config (e.g. `pacDecisionAdmitRaw = ...PreserveAmbiguous`) **typechecks
but is wrong**. Every conversion MUST therefore:

1. Add an equivalence test to `Test.Suite.AdmissionEquivalence` pinning all
   three decision branches AND constructor identity for the module.
2. Run it **green against the unconverted module** (proves it captures real
   behavior).
3. Convert the module to `admitPropositionTriggers <config>`.
4. Run it **green again** (proves equivalence).

### Converted (18/18, all under equivalence lock)

`Contact` (PoC), `Confront`, `WorldCause`, `AffectiveSupportPhrase`,
`AffectiveSupportProbe`, `ConceptKnowledge`, `ContemplativeTopic`,
`Distinction`, `LocationFormation`, `Misunderstanding`, `NextStep`,
`OperationalCause`, `OperationalStatus`, `Purpose`, `RepairDirective`,
`SelfKnowledge`, `SelfState`, `SystemLogic`.

All 18 now delegate to `admitPropositionTriggers <config>`. Behavioral
equivalence is locked by `Test.Suite.AdmissionEquivalence` (3 branches ×
constructor identity per module), proven green BEFORE conversion (captures real
behavior) and green AFTER (proves equivalence). The irregular constructor names
(`Misunderstanding`'s `Pm*`, `AffectiveSupportProbe`'s `PasprSuppressStrongProbe`)
are wired explicitly and covered by the lock.

### Out of scope (correctly untouched)

- 4 two-guard variants: `ComparisonPlausibility`, `DialogueInvitation`,
  `ExploratoryPrompt`, `GenerativePrompt` — no `PreserveAmbiguous` branch.
- 2 non-label-predicate: `PhraseDecision`, frame-based `PropositionAdmission`.

These would need a richer generic (optional-preserve mode / predicate-based
safe check) and a behavior-change review — a separate decision, not this pass.

---

## Original plan (superseded scope above)

### Completed Work

1. **Created Generic Module** (`src/QxFx0/Core/GenericPropositionAdmission.hs`)
   - 92 lines of reusable admission logic
   - `PropositionAdmissionConfig` record with 10 fields
   - `admitPropositionTriggers` function implementing three-guard logic
   - Fully documented with Haddock comments

2. **Refactored Example Module** (`src/QxFx0/Core/PropositionContactAdmission.hs`)
   - Reduced from 43 lines to 44 lines (but eliminated all boilerplate logic)
   - Now just config + safe labels list
   - Demonstrates the pattern for remaining 17 modules

3. **Updated Build Configuration** (`qxfx0.cabal`)
   - Added `QxFx0.Core.GenericPropositionAdmission` to exposed-modules
   - Project compiles successfully

### Remaining Work

#### Phase 1: Core Modules (17 files, ~6 hours)

Refactor these Proposition*Admission modules using the same pattern as PropositionContactAdmission:

1. `PropositionAffectiveSupportPhraseAdmission.hs`
2. `PropositionAffectiveSupportProbeAdmission.hs`
3. `PropositionComparisonPlausibilityAdmission.hs`
4. `PropositionConceptKnowledgeAdmission.hs`
5. `PropositionConfrontAdmission.hs`
6. `PropositionContemplativeTopicAdmission.hs`
7. `PropositionDialogueInvitationAdmission.hs`
8. `PropositionDistinctionAdmission.hs`
9. `PropositionExploratoryPromptAdmission.hs`
10. `PropositionGenerativePromptAdmission.hs`
11. `PropositionLocationFormationAdmission.hs`
12. `PropositionMisunderstandingAdmission.hs`
13. `PropositionNextStepAdmission.hs`
14. `PropositionOperationalCauseAdmission.hs`
15. `PropositionOperationalStatusAdmission.hs`
16. `PropositionPhraseDecisionAdmission.hs`
17. `PropositionPurposeAdmission.hs`
18. `PropositionRepairDirectiveAdmission.hs`
19. `PropositionSelfKnowledgeAdmission.hs`
20. `PropositionSelfStateAdmission.hs`
21. `PropositionSystemLogicAdmission.hs`
22. `PropositionWorldCauseAdmission.hs`

**Pattern for each file:**
```haskell
import QxFx0.Core.GenericPropositionAdmission

admitPropositionXxxTriggers :: PropositionXxxAdmissionInput -> [RawPropositionXxxTrigger] -> AdmittedPropositionXxxTriggers
admitPropositionXxxTriggers = admitPropositionTriggers xxxConfig

xxxConfig :: PropositionAdmissionConfig PropositionXxxAdmissionInput RawPropositionXxxTrigger AdmittedPropositionXxxTriggers PropositionXxxAdmissionDecision
xxxConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pXxxaiTruthContractStatus
  , pacTriggerLabel = rpXxxLabel
  , pacTriggerMatched = rpXxxMatched
  , pacSetTriggerMatched = \b t -> t { rpXxxMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionXxxTriggers
  , pacDecisionAdmitRaw = PXxxadAdmitRaw
  , pacDecisionPreserveAmbiguous = PXxxadPreserveAmbiguous
  , pacDecisionSuppressStrong = PXxxadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels = [...]  -- Copy from original file
```

**Estimated savings:** ~800 lines (22 files × ~36 lines of boilerplate each)

#### Phase 2: Types Modules (22 files, ~2 hours)

The 22 Types/Proposition*Admission.hs files are identical 33-line templates. Options:

**Option A: Template Haskell (recommended)**
Create `src/QxFx0/Types/GenericPropositionAdmission.hs` with TH splice:
```haskell
{-# LANGUAGE TemplateHaskell #-}
module QxFx0.Types.GenericPropositionAdmission (mkPropositionAdmissionTypes) where

import Language.Haskell.TH

mkPropositionAdmissionTypes :: String -> Q [Dec]
mkPropositionAdmissionTypes prefix = do
  -- Generate 4 data types with appropriate prefixes
  -- Input, Decision, RawTrigger, AdmittedTriggers
  ...
```

Then each Types file becomes:
```haskell
{-# LANGUAGE TemplateHaskell #-}
module QxFx0.Types.PropositionXxxAdmission where
import QxFx0.Types.GenericPropositionAdmission
$(mkPropositionAdmissionTypes "Xxx")
```

**Option B: Keep as-is**
Types files are small (33 lines) and explicit. Duplication is acceptable for data type definitions.

**Estimated savings:** ~660 lines (22 files × 30 lines each) if using TH

#### Phase 3: Integration & Testing (~1 hour)

1. Run full test suite to ensure behavioral equivalence
2. Update any tests that import the refactored modules
3. Document the refactoring in CHANGELOG.md
4. Update architecture documentation if needed

### Total Impact

- **Lines removed:** ~1460-2120 (depending on Phase 2 approach)
- **Files reduced:** 63 → 10-32 (depending on Phase 2 approach)
- **Maintainability:** Single source of truth for admission logic
- **Type safety:** Preserved through parameterization
- **Performance:** No runtime overhead (all inlined)

### Testing Strategy

1. **Compilation test:** Already passing ✅
2. **Unit tests:** Existing tests should pass without modification
3. **Property tests:** Add tests for generic admission logic
4. **Integration tests:** Verify end-to-end behavior unchanged

### Next Steps

1. Apply the refactoring pattern to remaining 17 Core modules (batch of 5-6 at a time)
2. Decide on Types module approach (TH vs keep as-is)
3. Run comprehensive test suite
4. Document completion in technical debt tracking

### Notes

- The generic approach maintains full type safety through parameterization
- No behavioral changes — pure refactoring
- Each module can be refactored independently (low risk)
- Rollback is trivial (git revert individual commits)