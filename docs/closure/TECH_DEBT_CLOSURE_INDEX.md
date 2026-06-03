# QxFx0_v3 — Tech Debt Closure Index

- **Status**: Active (closure-phase work product, INDEX)
- **Date**: 2026-06-02
- **Refines**: AGENTS.md, `docs/AUTHORITY_BOUNDARY.md` (2026-05-26),
  `docs/ROADMAP.md`, all `docs/adr/*.md`, all `docs/adr/proposed/*.md`
- **Related**:
  - All `docs/closure/*.md` files (this index)
  - All `docs/adr/0001-0033*.md` (existing ADRs)
  - `docs/AUTHORITY_BOUNDARY.md` (freeze-0 boundary)
  - `docs/PYTHON_STATUS_LEDGER.md` (closure-phase update of this)

## 0. What this index is

This is the **single entry point** for the QxFx0_v3 tech-debt
closure plan. It ties together the 13 closure-phase artifacts
under `docs/closure/`, the proposed ADR-0034 under
`docs/adr/proposed/`, and the existing canonical docs. It
answers four questions:

1. What is the closure plan?
2. What did the audits find?
3. What does each package produce?
4. How do we know the closure is real?

The index is the **audit trail** for the closure, not a roadmap
in the aspirational sense. Every claim in this index is
defensible by a specific file and a specific acceptance
criterion.

## 1. The closure plan, in one diagram

```
                    ┌──────────────────────────────────┐
                    │  CRITICAL STAGE  (Packages 1-6)  │
                    ├──────────────────────────────────┤
                    │  P1: Authority split             │
                    │  P2: Semantic authority core     │
                    │  P3: Replay gate                 │
                    │  P4: GF authority subset         │
                    │  P5: Zero Python in auth paths   │
                    │  P6: Test authority audit        │
                    └────────────────┬─────────────────┘
                                     │
                    ┌────────────────▼─────────────────┐
                    │  HIGH STAGE  (Packages 7-10)     │
                    ├──────────────────────────────────┤
                    │  P7: Cognitive memory            │
                    │  P8: Bounded learning            │
                    │  P9: Metacognitive correction    │
                    │  P10: Self-layer status cleanup  │
                    └────────────────┬─────────────────┘
                                     │
                    ┌────────────────▼─────────────────┐
                    │  LATE STAGE  (Package 11)        │
                    ├──────────────────────────────────┤
                    │  P11: Calibration of surviving   │
                    │       substrate                  │
                    └──────────────────────────────────┘
```

The packages are not all strictly sequential: P10 (Self-layer
status cleanup) is parallelisable with P7/P8/P9 (all four are
gated on P1-P6, not on each other). P11 is strictly last
because it calibrates only what survives P1-P10.

## 2. The closure-phase artifacts

| # | File | Purpose | Status |
|---|---|---|---|
| INDEX | `docs/closure/TECH_DEBT_CLOSURE_INDEX.md` | this file | merged |
| P1 | `docs/closure/AUTHORITY_MAP.md` | per-module authority classification | merged |
| P1 | `docs/adr/proposed/0034-self-core-role-split.md` | role split ADR | proposed |
| P2 | `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` | typed semantic commitments minimal slice | merged |
| P3 | `docs/closure/REPLAY_GATE_SPEC.md` | replay-visibility as authority gate | merged |
| P4 | `docs/closure/GF_AUTHORITY_SUBSET.md` | authority-bearing surface language | merged |
| P5 | `docs/closure/PYTHON_STATUS_LEDGER.md` | Python closure-phase update | merged (extends 2026-05-26 ledger) |
| P6 | `docs/closure/TEST_AUTHORITY_AUDIT.md` | test classification | merged |
| P7 | `docs/closure/COGNITIVE_MEMORY_DESIGN.md` | episodic memory design | merged |
| P8 | `docs/closure/BOUNDED_LEARNING_DESIGN.md` | bounded learning design | merged |
| P9 | `docs/closure/METACOGNITION_LOOP_DESIGN.md` | metacognitive loop design | merged |
| P10 | `docs/closure/SELF_LAYER_STATUS.md` | per-module production status | merged |
| P11 | `docs/closure/CALIBRATION_BACKLOG.md` | calibration backlog | merged |

**Total: 13 closure-phase documents.** The index plus 12
package deliverables.

## 3. Per-package summary

### 3.1 Package 1 — Authority split (CRITICAL)

**Goal**: make the Self/* vs Core/* split explicit, auditable,
and CI-enforceable.

**What it produces**:
- `AUTHORITY_MAP.md` (per-module role classification; five
  classes: canonical, canonical-flag-off, supplier, derived,
  observer, legacy).
- ADR-0034 (proposed): the role split decision with seven
  boundary rules.
- Per-module map of every `Self/*` and `Core/*` module.

**Acceptance criteria**:
- [ ] AUTHORITY_MAP.md and ADR-0034 merged.
- [ ] `scripts/check_architecture.sh` enforces the seven
      boundary rules of ADR-0034 §3.
- [ ] Every `Self/*` and `Core/*` module's Haddock header
      declares its role.

**Cross-package handoffs**:
- Defines the **`canonical` class** that all other packages
  must respect. A contour that is not `canonical` per
  AUTHORITY_MAP is not authority-bearing, and is not in
  scope for the replay gate (Package 3) or any of the design
  packages (7, 8, 9).
- Reclassifies flag-off features (`Essence`, `familyDivergence`,
  `Perspective.Operator`) as a **fifth class**
  (`canonical-flag-off`), not as `legacy` or `experimental`.

### 3.2 Package 2 — Semantic authority core (CRITICAL)

**Goal**: build a minimal but real typed-commitment contour.

**What it produces**:
- `SEMANTIC_CORE_MIN_SLICE.md` (the design: one class, four
  operations, one consumer, replay-visible lineage).
- New module `QxFx0.Semantic.Commitment` (target).
- New module `QxFx0.Semantic.Retrieve` (target).
- New `ssSemanticCommitments` field on `SystemState`.
- New trace fields `trcCommitmentRetrieval`.

**Acceptance criteria**:
- [ ] The four operations are total, pure, replay-visible.
- [ ] Replay produces identical `SemanticCommitmentStore`
      for identical `TurnInput` sequences.
- [ ] `Core/Consciousness/Kernel/Pulse.hs` no longer produces
      text-shaped narrative for factual claims.

**Cross-package handoffs**:
- Provides the **commitment store** that Package 7 (episodic
  memory) links to via `eeLinked :: [CommitmentId]`.
- Provides the **commitment-retraction** signal that Package 8
  (learning) consumes via `SrcCommitmentRetraction`.
- Provides the **commitment-stability** signal that Package 11
  (calibration) uses to evaluate `emAngstCommitmentThreshold`.

### 3.3 Package 3 — Replay gate (CRITICAL)

**Goal**: make replay-visibility a project-wide law.

**What it produces**:
- `REPLAY_GATE_SPEC.md` (the four properties P1–P4; the
  envelope; the event trail; CI gates).
- New `envelopeVersion` field on the replay envelope.
- New `trc*` fields for each contour (semantic, episodic,
  learning, calibration, metacognition).

**Acceptance criteria**:
- [ ] Every existing canonical contour passes P1–P4 (or is
      reclassified to supplier/observer per Package 1).
- [ ] `scripts/check_replay_gate.sh` enforces P1–P4.
- [ ] Every new ADR has a "Replay Gate" section.

**Cross-package handoffs**:
- All other packages (2, 4, 7, 8, 9, 11) **inherit** the
  replay discipline. The replay gate is not optional for any
  authority-bearing contour.

### 3.4 Package 4 — GF authority subset (CRITICAL)

**Goal**: identify the surface language the system can parse
back to itself with high round-trip coverage.

**What it produces**:
- `GF_AUTHORITY_SUBSET.md` (the `AuthoritySurface` newtype;
  the parser-complete subset; the boundary rule).
- New module `QxFx0.Render.Authority`.
- New module `QxFx0.Semantic.AuthorityParse`.
- New `trcAuthoritySurface` field on `TurnReplayTrace`.

**Acceptance criteria**:
- [ ] `roundTripProperty` is identity on the test generators.
- [ ] `coverageCorpus ≥ 0.99` on a 1k × 2-language corpus.
- [ ] At least one existing render function in `Render/Surface/*`
      is migrated to return `AuthoritySurface Text`.

**Cross-package handoffs**:
- Defines the **subset** that Package 2's `commitObservation`
  accepts. Without Package 4, the parser is allowed to commit
  free-form text, which defeats the Σ-type discipline.

### 3.5 Package 5 — Zero Python in authority paths (CRITICAL)

**Goal**: replace every Python script in the canonical authority
path with Haskell; allowlist the rest.

**What it produces**:
- `PYTHON_STATUS_LEDGER.md` (closure-phase update of the
  2026-05-26 ledger; per-file authority classification A–F;
  per-gate replacement plan).
- New Haskell commands: `--check-schema-consistency`,
  `--check-schema-contract`, `--check-embedded-sql`,
  `QxFx0.Lexicon.Morphology.Parser`.

**Acceptance criteria**:
- [ ] The three `A. canonical-build` scripts replaced by
      Haskell and deleted.
- [ ] `services/morphology/server.py` replaced by
      `QxFx0.Lexicon.Morphology.Parser` and the HTTP call sites
      updated.
- [ ] `scripts/http_runtime.py` confirmed not invoked and
      deleted.
- [ ] `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` exists and
      is empty.
- [ ] CI gate: zero `python3` invocations on the canonical path.

**Cross-package handoffs**:
- Defines **the build-time authority boundary** that Package 6
  (test audit) verifies. Without Package 5, the test suite
  may have Python in its CI path.

### 3.6 Package 6 — Test authority audit (CRITICAL)

**Goal**: classify every test suite by role; rewrite or
delete the ones that do not fit.

**What it produces**:
- `TEST_AUTHORITY_AUDIT.md` (per-file classification of all
  30 test suites; five classes: canonical-behavior,
  canonical-flag-off, compatibility, obsolete, rewrite-required,
  eval-only).
- `cabal test qxfx0-test-canonical` (new; the canonical
  regression lock).
- Rewritten `ArchitectureInvariants`, `LearningLoop`,
  `SemanticSlices` test suites.

**Acceptance criteria**:
- [ ] Each test file declares its class in its module Haddock.
- [ ] The `rewrite-required` test suites are rewritten in the
      new form.
- [ ] The `E. test-only` Python tests are deleted.
- [ ] `cabal test qxfx0-test-canonical` exists and passes.

**Cross-package handoffs**:
- Verifies the **replay gate** (Package 3) is testable.
- Verifies the **architecture rules** (Package 1) are
  testable.

### 3.7 Package 7 — Cognitive memory (HIGH)

**Goal**: turn persisted state into usable cognitive memory.

**What it produces**:
- `COGNITIVE_MEMORY_DESIGN.md` (episodic contour; tagged-sum
  content; retrieval index; forgetting policy; authority rules).
- New module `QxFx0.Memory.Episodic`.
- New `ssEpisodic` field on `SystemState`.
- New trace fields `trcEpisodicEncoding`, `trcEpisodicRetrieval`,
  `trcEpisodicForgetting`.

**Acceptance criteria**:
- [ ] The four authority rules (write / extract / forget /
      reuse) are enforced.
- [ ] `Test.Suite.EpisodicMemory` passes the replay gate
      (Package 3).
- [ ] Documentation: `EPISTEMIC_MEMORY_EXAMPLE.md`.

**Cross-package handoffs**:
- Provides the **retrieval-quality** signal that Package 8
  (learning) consumes via `SrcEpisodicRetrievalOutcome`.
- Provides the **forgetting policy** that Package 11
  (calibration) tunes via `episodicCapacity` and
  `episodicWindow`.

### 3.8 Package 8 — Bounded learning (HIGH)

**Goal**: enable learning only around authority carriers,
bounded by four invariants.

**What it produces**:
- `BOUNDED_LEARNING_DESIGN.md` (the four invariants I1–I4;
  the four `UpdateKind`s; the rate limits; the rollback rule).
- New module `QxFx0.Learning.Contour`.
- New `ssLearning` field on `SystemState`.
- New `trcLearningUpdate` field on `TurnReplayTrace`.
- `LEARNING_ALLOWED_TARGETS.md` and `LEARNING_ALLOWED_SOURCES.md`
  (closed lists).

**Acceptance criteria**:
- [ ] The four invariants are enforced.
- [ ] The rate limits and rollback are enforced.
- [ ] `Test.Suite.LearningContour` replaces
      `Test.Suite.LearningLoop`.
- [ ] Reclassified `ssAdaptiveMutationLog`,
      `ssCalibrationLog`, `ssDialogueOutcomeLearning` as
      `LearningContour`-derived.

**Cross-package handoffs**:
- Provides the **client** for Package 9 (metacognition):
  `boundedCorrection` produces a `LearningUpdate` that goes
  through `applyLearningUpdate`.
- Provides the **target** for Package 11 (calibration): the
  rate limits and rollback window are calibration knobs.

### 3.9 Package 9 — Metacognitive correction loop (HIGH)

**Goal**: close the loop `decision → outcome → evaluation →
bounded correction`, calibrated against external evaluation.

**What it produces**:
- `METACOGNITION_LOOP_DESIGN.md` (the four-stage loop; the
  six `Outcome`s; the four `Evaluation`s; the calibration
  discipline).
- New module `QxFx0.Policy.Metacognition`.
- New `ssMetacognition` field on `SystemState`.
- New `trcMetacognition` field on `TurnReplayTrace`.
- `METACOGNITION_CORPUS.md` (the labelled held-out corpus).

**Acceptance criteria**:
- [ ] `observeResponse` is parser-typed (no keyword
      heuristics).
- [ ] `selfEvaluate` is calibrated: precision ≥ 0.85,
      recall ≥ 0.70 on the held-out corpus.
- [ ] `boundedCorrection` routes through Package 8.
- [ ] `cabal test qxfx0-test-metacognition-calibration` is
      part of the canonical regression lock.

**Cross-package handoffs**:
- Provides the **self-evaluation** signal that Package 8
  (learning) consumes via `SrcMetacognitiveEvaluation`.
- Provides the **calibration corpus** that Package 11
  (calibration) needs for the precision / recall gates.

### 3.10 Package 10 — Self-layer status cleanup (HIGH)

**Goal**: make flag-off features explicit, document their
promotion or demotion criteria.

**What it produces**:
- `SELF_LAYER_STATUS.md` (per-module production status; the
  "core runtime" table; the calibration-status section).
- AGENTS.md update for `Self.Perspective` feature flag.

**Acceptance criteria**:
- [ ] Every `Self/*` module has a status entry.
- [ ] Every flag-off feature has a promotion ADR or a
      demotion ADR.
- [ ] The "core runtime" table matches the runtime
      behaviour under default flags.

**Cross-package handoffs**:
- Verifies the **status** of every `Self/*` module that the
  other packages touch (2, 7, 8, 9).

### 3.11 Package 11 — Calibration of surviving substrate (LATE)

**Goal**: empirically calibrate the parameters that survive
the closure, against a production-trace corpus.

**What it produces**:
- `CALIBRATION_BACKLOG.md` (per-parameter table with codomain
  check, observable outcome, empirical evidence needed,
  promotion gate).
- `data/calibration_corpus/` (the production-trace corpus).
- `Test.Suite.Calibration*` (regression locks for
  empirically-calibrated parameters).
- `docs/closure/CALIBRATION_REPORT.md` (the calibration pass
  summary).

**Acceptance criteria**:
- [ ] The corpus exists with at least 1k records and a
      labelled subset of at least 100 records.
- [ ] At least 50% of the entries in the backlog have an
      empirical calibration pass.
- [ ] `SELF_LAYER_STATUS.md` reflects the new calibration
      status for each parameter.

**Cross-package handoffs**:
- Receives the **calibration corpus** from Package 9.
- Receives the **calibration knobs** from Packages 7, 8, 9
  (forgetting policy, rate limits, calibration targets).

## 4. How we know the closure is real — the 7 conditions

The closure plan's "what counts as closed" is **7 simultaneous
conditions**:

1. **One canonical cognitive decision path.** The role split
   per Package 1 is in place; `scripts/check_architecture.sh`
   enforces the seven boundary rules of ADR-0034 §3; CI
   reports zero violations.

2. **Conatus and other Self-parts have explicit authority
   status.** Per `SELF_LAYER_STATUS.md §6`, every `Self/*`
   module is `production`, `production-flag-off`, or
   `observability-only`; no module is in an ambiguous state.

3. **Typed semantic commitments are the centre of internal
   continuity.** Per Package 2, `SemanticCommitmentStore` is
   the canonical store for the system's commitments; the
   Σ-type discipline is enforced at compile time; the
   minimal slice passes its acceptance criteria.

4. **Authority surfaces do not depend on Python.** Per Package
   5, the canonical authority path has zero `python3`
   invocations; `PYTHON_SUPPLIER_ALLOWLIST.md` is empty (or
   contains only eval-only Python with explicit markers).

5. **Authority subset surface language has round-trip
   semantic integrity.** Per Package 4, `roundTripProperty` is
   identity and `coverageCorpus ≥ 0.99` on the 1k × 2-language
   corpus.

6. **Memory, learning and self-evaluation are tied to
   commitments and replay.** Per Packages 7, 8, 9, the
   episodic contour links to commitments, the learning
   contour consumes commitment signals, the metacognitive
   contour routes through the learning contour, and all
   three pass the replay gate (Package 3).

7. **Tests verify the new architecture, not the old ghosts.**
   Per Package 6, every test suite is classified, the
   `rewrite-required` suites are rewritten, and the canonical
   regression lock (`cabal test qxfx0-test-canonical`)
   passes.

**All 7 conditions must be met simultaneously** for the
closure to be considered real. The closure is not a sequence
of "package N is done"; it is a **state** the system is in.

## 5. What this index does NOT claim

- It does not claim the closure is **complete**. The 13
  closure-phase artifacts are the design and the plan; the
  actual code-and-CI work is downstream.
- It does not claim the closure is **sufficient**. The
  closure plan is the **tech-debt** work; the broader
  project (embodiment, richer affect, neural realisation,
  broad proactive agency) is out of scope.
- It does not claim the closure is **easy**. Each package
  is a multi-day-to-multi-week effort. The closure plan
  does not pretend otherwise.
- It does not claim the closure is **without risk**. Each
  package has honest limits (per the per-package docs).
  Specifically:
  - Package 2 depends on Package 4 (no free-form commits).
  - Package 8 depends on Packages 2, 7, 9 (no learning
    without signals).
  - Package 11 depends on a production-trace corpus that
    does not yet exist.
  - All packages depend on Package 5 (Python removal) for
    the canonical path to be Haskell-only.

## 6. Audit trail: which doc answers which question

| Question | Doc | Section |
|---|---|---|
| What is the per-module authority? | `AUTHORITY_MAP.md` | §3–5 |
| What is the role split decision? | ADR-0034 (proposed) | §2–3 |
| What is the Self-layer status? | `SELF_LAYER_STATUS.md` | §6 |
| What is the Python status? | `PYTHON_STATUS_LEDGER.md` | §3 |
| What is the test status? | `TEST_AUTHORITY_AUDIT.md` | §1–2 |
| What is the semantic commitment minimal slice? | `SEMANTIC_CORE_MIN_SLICE.md` | §1 |
| What is the replay gate? | `REPLAY_GATE_SPEC.md` | §1 |
| What is the GF authority subset? | `GF_AUTHORITY_SUBSET.md` | §3 |
| What is the episodic memory design? | `COGNITIVE_MEMORY_DESIGN.md` | §1 |
| What is the bounded learning design? | `BOUNDED_LEARNING_DESIGN.md` | §2 |
| What is the metacognitive loop design? | `METACOGNITION_LOOP_DESIGN.md` | §1 |
| What is the calibration backlog? | `CALIBRATION_BACKLOG.md` | §2 |
| How do we know the closure is real? | this index | §4 |
| What is the closure plan? | this index | §1, §3 |

## 7. Open follow-ups (deferred from this closure pass)

1. **`docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md`** (Package 5
   follow-up) — the empty allowlist at Gate P5-7.
2. **`docs/closure/SYSTEM_STATE_AUTHORITY.md`** (Package 1
   follow-up) — per-field classification of every `ss*` field.
3. **`docs/closure/SEMANTIC_CORE_EXAMPLE.md`** (Package 2
   follow-up) — end-to-end walkthrough.
4. **`docs/closure/EPISTEMIC_MEMORY_EXAMPLE.md`** (Package 7
   follow-up).
5. **`docs/closure/LEARNING_EXAMPLE.md`** (Package 8
   follow-up).
6. **`docs/closure/METACOGNITION_EXAMPLE.md`** (Package 9
   follow-up).
7. **`docs/closure/METACOGNITION_CORPUS.md`** (Package 9
   follow-up) — the labelled held-out corpus.
8. **`docs/closure/CALIBRATION_REPORT.md`** (Package 11
   follow-up).
9. **`LEARNING_ALLOWED_TARGETS.md`** and
   **`LEARNING_ALLOWED_SOURCES.md`** (Package 8 follow-up).
10. **Promotion / demotion ADRs** for every flag-off feature
    in `SELF_LAYER_STATUS.md §3` (Package 10 follow-up).

These are the next-step work products. The closure plan does
not pretend they are already done; the index makes them
explicit so the next pass has a clear starting point.

## 8. Acceptance criteria for the closure (the meta-criterion)

The closure-phase artifacts are **all in place** when:

- [x] 13 closure-phase documents exist under
      `docs/closure/` and `docs/adr/proposed/`.
- [ ] Every package's per-package acceptance criteria (in
      the per-package docs) are tracked as issues or PRs
      with named owners.
- [ ] The 7 conditions of §4 are tracked as a top-level
      project checklist.
- [ ] The follow-ups of §7 are tracked in a single
      `docs/closure/FOLLOWUPS.md` (or equivalent).
- [ ] A `cabal build` of the post-closure QxFx0_v3 passes
      with zero warnings introduced by the closure work
      (this requires the actual code-and-CI work, which
      is downstream of this index).

The closure-phase artifacts are **the plan**, not the
**execution**. The execution is the work of merging the
artifacts into the codebase, building, running tests, and
verifying the 7 conditions. This index is the entry point
to that work.
