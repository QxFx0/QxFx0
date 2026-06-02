# Test Authority Audit (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 6)
- **Date**: 2026-06-02
- **Refines**: `docs/AUTHORITY_BOUNDARY.md`, AGENTS.md
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md`
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/closure/TECH_DEBT_CLOSURE_INDEX.md`

## 0. Why this audit exists

The closure plan's Package 6 says: "after role split and semantic
core, part of the test suite will be obsolete, part will lock in
undesirable architecture, part will require rewriting, and part
will require conscious deletion." This document is the closure-
phase audit of every test suite under `test/Test/Suite/`.

Classification per file follows the closure plan's four classes:

| Class | Definition | Action |
|---|---|---|
| **canonical-behavior** | Tests current canonical behaviour; the runtime regression lock. | Keep, mark with module-under-test role. |
| **compatibility** | Tests the boundary between canonical and legacy, or a contract that is intentionally frozen. | Keep, mark as `compatibility-lock`. |
| **obsolete** | Tests behaviour that has been superseded by a later phase or ADR. | Delete. |
| **rewrite-required** | Tests behaviour that should be canonical, but the current test is not replay-traced or is tied to a non-authority path. | Rewrite in the new form. |

A **fifth** class, `canonical-flag-off`, is added to mirror
`AUTHORITY_MAP.md §1`: tests for `Self.Essence`,
`Self.Perspective`, `familyDivergenceEnabled`, `LearningLoop`,
`TrainingCycle` — landed, fully-tested, but the modules they
exercise are not in the default runtime path. These tests run on
CI but are not part of the canonical regression lock until the
relevant feature flag is flipped.

## 1. Test inventory (per file)

The list below is the per-file audit. The test file is the
**subject**; the test's relationship to the authority path is the
**predicate**.

### 1.1 `Test.Suite.SelfConatus`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Conatus` (canonical)
- **verdict**: keep as is. Property tests cover the energy functional's monotonicity, the gradient structure, the ConatusGate semantics. These are the M6 single-source-of-truth regression locks (AGENTS.md).

### 1.2 `Test.Suite.SelfBlanket`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Blanket` (canonical)
- **verdict**: keep as is. Property tests over `computeSelfBlanket` / `checkInitialBlanket` invariants.

### 1.3 `Test.Suite.SelfAdjunction`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Adjunction` (canonical)
- **verdict**: keep as is. Property tests for the `Holistic ⊣ Formal` algebra.

### 1.4 `Test.Suite.SelfField`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Field` (canonical) + `FieldHeuristics` (Phase 7 calibration infrastructure)
- **verdict**: keep as is. Property tests cover the 5-component Field, `fieldConfidence` aggregation, and the Phase-7-extracted `FieldHeuristics`.

### 1.5 `Test.Suite.SelfSalience`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Salience` (canonical)
- **verdict**: keep as is. Property tests cover the controller (total, monotone, Conatus-gated, `Tied` dead band, `DrivenByConatusGate` priority) per ADR-0010 §7.

### 1.6 `Test.Suite.SelfDeliberation`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Deliberation` (canonical)
- **verdict**: keep as is. Property tests cover reconcile (Conatus override, agreement idempotence, recovery preservation, tied fallback, divergence boundedness, determinism, render totality) per ADR-0011 §8.

### 1.7 `Test.Suite.SelfEssence`
- **class**: `canonical-flag-off`
- **module-under-test**: `Self.Essence` (canonical-flag-off)
- **verdict**: keep as is. Property tests E1–E5 (ADR-0012 §9). These run on CI but are not part of the **canonical runtime** regression lock until `essenceCommitmentEnabled` flips to `True`.

### 1.8 `Test.Suite.SelfEssenceCommit`
- **class**: `canonical-flag-off`
- **module-under-test**: `Self.Essence` (canonical-flag-off, Phase 10 commit logic)
- **verdict**: keep as is. Property tests E6–E8. Same flag-gating note as §1.7.

### 1.9 `Test.Suite.SelfPerspective`
- **class**: `canonical-flag-off`
- **module-under-test**: `Self.Perspective` (canonical-flag-off)
- **verdict**: keep as is. P4 work; flag is implicit (per `SELF_LAYER_STATUS.md §3`).

### 1.10 `Test.Suite.PerspectiveRegistry`
- **class**: `canonical-behavior`
- **module-under-test**: `Self.Perspective.Registry` (canonical lineage) + `PerspectiveOperator` (flag-off)
- **verdict**: keep as is. The registry itself is canonical; the operator is flag-off.

### 1.11 `Test.Suite.ArchitectureInvariants`
- **class**: `canonical-behavior`
- **module-under-test**: the architecture rules in `AUTHORITY_BOUNDARY.md` and the closure plan's `AUTHORITY_MAP.md`
- **verdict**: **rewrite-required** after the closure plan's `check_architecture.sh` extension lands (ADR-0034 §3). The current test must be extended to enforce the seven boundary rules.

### 1.12 `Test.Suite.CoreBehavior`
- **class**: `canonical-behavior`
- **module-under-test**: the turn pipeline's mainline behaviour
- **verdict**: keep as is. The three `routeFamily*Deliberation*` integration locks (ADR-0011 §8) are here. **Note:** the "F1 regression locks retargeted from `adjustedFamily` to `rdFamily` / `delibReconciled.planFamily`" (ADR-0011 §12 Package D) is a model of what a `rewrite-required` → `canonical-behavior` transition looks like. Apply the same discipline to the test authority audit's `rewrite-required` cases.

### 1.13 `Test.Suite.TurnPipelineProtocol`
- **class**: `canonical-behavior`
- **module-under-test**: the turn pipeline's wire shape
- **verdict**: keep as is. Includes `testDeliberationRecoveryNotSilenced` (ADR-0011 §8.4). Add new tests for the closure plan's typed semantic commitments (Package 2) when those land.

### 1.14 `Test.Suite.P5Governance`
- **class**: `canonical-behavior`
- **module-under-test**: Phase 5 governance
- **verdict**: keep as is. Phase-5 governance is part of the canonical runtime.

### 1.15 `Test.Suite.RenderDialogueCoverage`
- **class**: `canonical-behavior`
- **module-under-test**: the Render subsystem
- **verdict**: keep as is.

### 1.16 `Test.Suite.DreamPressure`
- **class**: `canonical-flag-off` (likely)
- **module-under-test**: `Core.DreamDynamics` (observer)
- **verdict**: keep as is, but mark the test file as `observer-only`. Dreams are not in the runtime path; this test exercises the observer contour.

### 1.17 `Test.Suite.LearningLoop`
- **class**: `canonical-flag-off`
- **module-under-test**: `Learning/*` (per `SELF_LAYER_STATUS.md §5`)
- **verdict**: **rewrite-required** when the closure plan's bounded learning (Package 8) lands. The current test is likely testing zero-signal stubs. Replace with bounded-learning tests that exercise the actual learning contours after Package 8.

### 1.18 `Test.Suite.TrainingCycle`
- **class**: `canonical-flag-off`
- **module-under-test**: training cycle (per `docs/adr/0031-phase10-offline-training-cycle.md`)
- **verdict**: keep as is, marked as `offline-training-only`. Not in the runtime path.

### 1.19 `Test.Suite.LongSessionCorpus`
- **class**: `canonical-behavior` (corpus regression)
- **module-under-test**: the long-session integration corpus
- **verdict**: keep as is. This is the regression lock for the 25-session integration corpus (ADR-0012 §14). Per ADR-0012 §15.2, the corpus is "no rupture under realistic dynamics" smoke-test, not angst-threshold validation; that gap is in `CALIBRATION_BACKLOG.md`.

### 1.20 `Test.Suite.SemanticCorpus`
- **class**: `canonical-behavior` (corpus regression)
- **module-under-test**: semantic corpus
- **verdict**: keep as is.

### 1.21 `Test.Suite.SemanticSlices`
- **class**: `rewrite-required` (per closure plan Package 2)
- **module-under-test**: semantic authority surface (per `docs/semantic_slice_result_ledger.md`)
- **verdict**: keep the **ledger** but expect the test surface to change after Package 2 (typed semantic commitments) lands. Specifically: the closure plan's Package 2 produces a `SEMANTIC_CORE_MIN_SLICE.md` that re-anchors the slice definition; the test must be rewritten in that new form.

### 1.22 `Test.Suite.ModelComparison`
- **class**: `eval-only`
- **module-under-test**: model comparison
- **verdict**: keep as is, but consider moving to `scripts/eval/` or a separate research repo per `PYTHON_STATUS_LEDGER.md §5.4` discipline. The Haskell test surface here is for the **Haskell** model-comparison code; Python eval scripts are a separate concern.

### 1.23 `Test.Suite.KnowledgeTree`
- **class**: `canonical-behavior`
- **module-under-test**: `KnowledgeTree` (per `docs/adr/0025-rooted-knowledge-tree.md`)
- **verdict**: keep as is.

### 1.24 `Test.Suite.LexiconTests`
- **class**: `canonical-behavior`
- **module-under-test**: `Lexicon/*` (mostly derived)
- **verdict**: keep as is. The lexicon is a canonical supplier; its tests are part of the canonical lock.

### 1.25 `Test.Suite.DialogueDevelopment`
- **class**: `canonical-behavior`
- **module-under-test**: dialogue phase state machine
- **verdict**: keep as is. Per `docs/adr/0032-dialogue-development-contours.md`, this is part of the canonical runtime.

### 1.26 `Test.Suite.EgoRead`
- **class**: `canonical-behavior`
- **module-under-test**: `Core.Ego`
- **verdict**: keep as is.

### 1.27 `Test.Suite.LegalAdapter`
- **class**: `canonical-behavior`
- **module-under-test**: `Legal/*`
- **verdict**: keep as is.

### 1.28 `Test.Suite.ReliabilityHardening`
- **class**: `canonical-behavior`
- **module-under-test**: reliability invariants
- **verdict**: keep as is.

### 1.29 `Test.Suite.RuntimeInfrastructure`
- **class**: `canonical-behavior`
- **module-under-test**: runtime infrastructure
- **verdict**: keep as is.

### 1.30 `Test.Suite.VecProperties`
- **class**: `canonical-behavior`
- **module-under-test**: vector properties (likely `Semantic.Sense.Vector`)
- **verdict**: keep as is.

## 2. Test-class summary

| Class | Count | Action |
|---|---|---|
| `canonical-behavior` | 22 | keep |
| `canonical-flag-off` | 5 (`SelfEssence`, `SelfEssenceCommit`, `SelfPerspective`, `DreamPressure`, `LearningLoop`, `TrainingCycle` — note `LearningLoop` is also `rewrite-required`) | keep, mark |
| `compatibility` | 0 explicit (none found in this pass) | n/a |
| `obsolete` | 0 explicit (none found in this pass) | n/a |
| `rewrite-required` | 3 (`ArchitectureInvariants`, `LearningLoop`, `SemanticSlices`) | rewrite after Packages 1, 8, 2 respectively |
| `eval-only` | 1 (`ModelComparison`) | mark or move |
| **total** | **30 test suites** | |

**Important:** the absence of explicit `obsolete` and
`compatibility` classes in this audit is a **finding**, not a
clean bill. The closure plan's Package 6 should not accept "no
obsolete tests" without an explicit search for them. Suggested
search: tests that reference removed intermediates (e.g.
`adjustedFamily`, pre-Phase-8 priority-switching, pre-Phase-6
duplicated Conatus computation). The `git log --diff-filter=D` of
the test files is the canonical source for candidates.

## 3. Test-authority boundary rules (extension of `check_architecture.sh`)

The closure plan's Package 6 extends the architecture check with:

1. **Test files declare the class of their subject.** A new test
   file under `test/Test/Suite/` must declare, in its module
   Haddock, the class of the module-under-test
   (`canonical-behavior` / `canonical-flag-off` /
   `compatibility` / `obsolete` / `rewrite-required` / `eval-only`).
2. **`canonical-flag-off` tests run on CI but are excluded from
   the canonical regression lock** by `cabal test qxfx0-test-canonical`.
   The aggregate `qxfx0-test` runs everything; the closure plan's
   final release gate uses `qxfx0-test-canonical`.
3. **`obsolete` tests are deleted at the next closure-plan package
   merge.** A test marked `obsolete` carries a delete-on-merge
   marker that CI honours.
4. **`rewrite-required` tests carry a follow-up ADR number** in
   their Haddock. CI fails if the follow-up ADR is not yet
   accepted.

## 4. Python test files (cross-reference with Package 5)

- `test/test_import_ru_opencorpora.py` — `E. test-only` per
  `PYTHON_STATUS_LEDGER.md §3`. Delete.
- `test/test_import_brain_kb.py` — same. Delete.

These are the two `obsolete` Python tests in the project. They
are replaced by Haskell-side import tests in the supplier Haskell
modules (or they simply become irrelevant once the supplier
pipeline is in Haskell per Package 5 Gate P5-4).

## 5. Acceptance criteria for Package 6 closure

- [ ] Each `test/Test/Suite/*.hs` file declares its class in its
      module Haddock.
- [ ] `cabal test qxfx0-test-canonical` (new) exists and runs only
      the `canonical-behavior` and `compatibility` tests.
- [ ] `cabal test qxfx0-test` (existing) still runs all tests.
- [ ] `test/test_*.py` files deleted; CI passes.
- [ ] An explicit search (`git log --diff-filter=D` of test files)
      produces zero `obsolete` candidates not already deleted.
- [ ] `ArchitectureInvariants` test file is rewritten to enforce
      the seven boundary rules of ADR-0034 §3.
- [ ] `LearningLoop` test file is rewritten to exercise the
      bounded-learning contours after Package 8 lands.
- [ ] `SemanticSlices` test file is rewritten to align with the
      `SEMANTIC_CORE_MIN_SLICE.md` from Package 2.
