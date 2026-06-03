# Replay Gate Triage List (QxFx0_v3) — Package 3 Closure

- **Status**: Active (closure-phase follow-up F-13, Package 3
  acceptance criteria §9)
- **Date**: 2026-06-02 (rev. 3 — trace-gap closure wired in working tree)
- **Refines**: `docs/closure/REPLAY_GATE_SPEC.md` §3
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md` §3 (per-module role map)
  - `docs/adr/proposed/0034-self-core-role-split.md` §4
  - `docs/closure/SYSTEM_STATE_AUTHORITY.md` (P1 per-field table)
  - `docs/closure/TRACE_SCHEMA.md` (the schema reference, post-rev. 2)
  - `docs/closure/CONTOUR_INDEX.md` (the contour index, post-rev. 2)

## rev. 3 (2026-06-02) — trace-gap closure in working tree

`TurnReplayTrace` now carries the representative
fields for the 3 previously missing canonical
contours:

- `trcConatusEnergy`, `trcConatusGateFired`
- `trcField`
- `trcIdentityClaims`

The static `check_replay_gate.sh` gate no longer
treats these as expected gaps; absence is now a
direct violation. This moves Conatus, Field, and
Identity from `needs-work` to `passing` in the
working tree. Full landing still depends on
build/test/CI.

## rev. 2 (2026-06-02) — alignment pass

The original triage (rev. 1, 2026-05-19) was
written before the Phase 9-10 Essence landing
(2026-05-19) and the Phase 5.5e Salience
observability landing. It claimed "passing" for
**Conatus** and **Field** based on
**expected** field names that have not been
added to `TurnReplayTrace`.

`check_replay_gate.sh` (rev. 2, 2026-06-02) and
`Test.Suite.TraceSchema` (rev. 1, 2026-06-02) both
read the **actual** `TurnReplayTrace` type and
report 3 GAPs: Conatus, Field, Identity. The
triage is updated to match.

Changes in rev. 2:

- **Conatus**: was "passing" in rev. 1; is
  **needs-work** in rev. 2 (the 3 expected
  `trcConatus*` fields are not in the type).
- **Field**: was "passing" in rev. 1; is
  **needs-work** in rev. 2 (the 2 expected
  `trcField*` fields are not in the type).
- **Salience**: the field names in the type
  are `trcSalienceDriver`,
  `trcSalienceHolisticBias`, `trcSalienceConfidence`
  (Phase 5.5e), not the
  `trcSalienceVerdict`/`trcSalienceBias` claimed
  in rev. 1.
- **Deliberation**: the field names in the type
  are `trcDeliberationRule`,
  `trcDeliberationAgreement`,
  `trcDeliberationDivergence`,
  `trcDeliberationNarrativeTone` (Phase 8
  Package B), not `trcDeliberationOutcome`.
- **Essence**: was "deferred (flag-off)" in
  rev. 1; the 4 trc\* fields ARE in the type
  (Phase 9-10, 2026-05-19). The flag-off
  status remains, but the 4 fields exist and
  are serializable.
- **Identity**: was "passing" in rev. 1; is
  **needs-work** in rev. 2 (the expected
  `trcIdentityClaim` / `trcIdentityClaims` is
  not in the type).

See `docs/closure/TRACE_SCHEMA.md` for the
canonical schema reference and the per-GAP
recipes.

## 0. What this list is

The closure plan's Package 3 requires every **authority-bearing
contour** to satisfy four replay properties (P1–P4 of
`REPLAY_GATE_SPEC.md §1`). The list of contours is the input;
the question of which contour **passes**, which **fails**, and
which **needs work** is the triage. This document is the
triage.

A contour is **authority-bearing** if it appears in the
`TurnReplayTrace` field set or if it is the source of an
authority-bearing `ss*` field (per `SYSTEM_STATE_AUTHORITY.md`).

## 1. The contour inventory

| Contour | Source | Authority-bearing `ss*` | Replay trace fields (actual) |
|---|---|---|---|
| Semantic commitments | `ssSemanticAnchor` (P2 promoted), `Core.MeaningGraph` | `ssSemanticAnchor` (P2 promotion target) | (none in type yet; rev. 1 had `trcSemanticCommitment`, `trcSemanticJustification`) |
| Conatus | `Self.Conatus` | none (computes from `ss*`) | OK: `trcConatusEnergy`, `trcConatusGateFired` |
| Field | `Self.Field` | none (computes from `ss*`) | OK: `trcField` |
| Salience | `Self.Salience` | `ssAdaptiveMutationLog` (gated) | OK: `trcSalienceDriver`, `trcSalienceHolisticBias`, `trcSalienceConfidence` (Phase 5.5e) |
| Deliberation | `Self.Deliberation` | `ssTone`, `ssFamily` (gated by `familyDivergenceEnabled`) | OK: `trcDeliberationRule`, `trcDeliberationAgreement`, `trcDeliberationDivergence`, `trcDeliberationNarrativeTone` (Phase 8 Package B) |
| Essence | `Self.Essence` (flag-off) | `ssEssence` (flag-off) | OK: `trcEssenceMode`, `trcEssenceCommitted`, `trcEssenceAngstLevel`, `trcEssenceTrigger` (Phase 9-10) |
| Perspective | `Self.Perspective` (flag-off) | `ssPerspectiveLog` | OK: `trcPerspectiveProjection`, `trcPerspectiveProjections` (P4) |
| Episodic memory | `Memory.Episodic` | `ssEpisodicMemory` | (none — only via snapshot) |
| Learning | `Learning.*` (flag-off) | `ssLearningWeights`, `ssAdaptiveMutationLog` | OK: `trcLearningQueryType`, `trcExternalTool`, `trcLearningValidationStatus`, `trcLearningSandboxResult`, `trcLearningGraftTurn`, `trcLearningRejectReason` |
| Calibration | `Learning.Calibration` (flag-off) | `ssCalibrationLog`, `ssCalibrationSnapshots` | (none — only via snapshot) |
| Metacognition | `Policy.Metacognition` (flag-off) | `ssMetacognitionLog` | (none) |
| Identity | `ssIdentityClaims` | `ssIdentityClaims` | OK: `trcIdentityClaims` |
| AuthoritySurface (GF) | `Render.Authority` (stub) | none (post-P4) | (none — stub returns Nothing) |

The **canonical contours** are: Conatus, Field, Salience,
Deliberation, Identity, **Essence** (added 2026-05-19, see
rev. 2). The **canonical-flag-off contours** are:
Essence (flag-off but 4 trc\* fields present),
Perspective, Learning, Calibration, Metacognition. The
**post-P2 promoted contour** is: Semantic commitments. The
**post-P4 stub contour** is: AuthoritySurface.

**Note on Essence**: Essence has 4 trc\* fields in
the type (Phase 9-10, 2026-05-19), so its
P1-P4 status is **OK** at the schema level.
But the contour is **flag-off** (`essenceCommitmentEnabled = False`),
so the runtime gate is not run. The discipline
is "the fields exist; the gate runs at
promotion time". This is **deferred** status
in the triage vocabulary.

## 2. The triage

Each contour is classified as one of:

- **passing** — the four properties P1–P4 hold; no work needed.
- **passing-with-notes** — P1–P4 hold, but there is a known
  small fix or a known gap to document.
- **needs-work** — at least one of P1–P4 is violated; the work
  to fix is enumerated below.
- **deferred** — the contour is flag-off and the closure plan
  explicitly defers the gate until the flag is flipped.

### 2.1 Conatus — passing (rev. 3)

- **P1 (serializable)**: OK. `ConatusEnergy` and the
  gate flag are in `TurnReplayTrace`.
- **P2 (replayable)**: OK. `computeConatusEnergy` is
  pure; replays from the same `SelfBlanket` produce
  the same energy.
- **P3 (reconstructable)**: OK. The snapshot is the
  `SelfBlanket` itself; reconstruction is total.
- **P4 (trace-explainable)**: OK. `trcConatusEnergy`
  and `trcConatusGateFired` expose the gate inputs.

### 2.2 Field — passing (rev. 3)

- **P1**: OK. `Field` is serializable and `trcField`
  is present in `TurnReplayTrace`.
- **P2**: OK. `Self.Field.compute` is pure.
- **P3**: OK. Snapshot is the `Field` Σ-type itself;
  reconstruction is total.
- **P4**: OK. `trcField` exposes the 5-field input to
  salience and downstream replay.

### 2.3 Salience — passing (rev. 2)

- **P1**: OK. The 3 landed fields are
  `trcSalienceDriver :: Text`,
  `trcSalienceHolisticBias :: Double`,
  `trcSalienceConfidence :: Double`
  (Phase 5.5e). All are serializable.
- **P2**: OK. `Self.Salience.compute` is pure;
  replays produce the same verdict.
- **P3**: OK. Snapshot is the `SalienceWeights`;
  reconstruction uses `defaultSalienceWeights`
  (the lifeness property test in
  `Test.Suite.SelfSalience` proves this).
- **P4**: OK. `Salience` is documented in
  ADR-0010. The `ssAdaptiveMutationLog` interaction
  remains a **post-promotion concern** (per
  ADR-0022) — when Adaptive Mutation is promoted,
  the trace field is extended to carry the mutation
  record. The current 3 fields are sufficient
  for the off-state.

### 2.4 Deliberation — passing-with-notes (rev. 2)

- **P1**: OK. The 4 landed fields are
  `trcDeliberationRule :: Maybe Text`,
  `trcDeliberationAgreement :: Maybe Text`,
  `trcDeliberationDivergence :: Maybe Double`,
  `trcDeliberationNarrativeTone :: Maybe Text`
  (Phase 8 Package B). All serializable.
- **P2**: OK. `Self.Deliberation.reconcile` is pure;
  replays produce the same outcome.
- **P3**: OK. Snapshot is the `DeliberationWeights`;
  reconstruction uses defaults.
- **P4**: OK. Documented in ADR-0011. **Note**: the
  `familyDivergenceEnabled` flag is a known opt-in
  (Package D); per `check_replay_gate.sh §5` and
  `Test.Suite.PromotionFlagDiscipline`, the flag
  is at its documented off-state
  (`Cascade.hs:74` literal `= False`).

### 2.5 Identity — passing (rev. 3)

- **P1**: OK. `trcIdentityClaims` is present in the
  replay trace.
- **P2**: OK. `IdentityGuard` is pure.
- **P3**: OK. Snapshot is the `ssIdentityClaims` list;
  reconstruction is total (the field is append-only).
- **P4**: OK. The trace exposes the active identity
  claim set for the turn.

### 2.6 Essence — deferred (rev. 2: fields landed, flag-off)

`essenceCommitmentEnabled = False` is the default
(integration level, per AGENTS.md). The closure
plan defers the gate to the post-promotion pass
(per F-14 ADR-0036). The four `trcEssence*` fields
are **landed and serializable** (Phase 9-10,
2026-05-19); the gate is not run because the
contour is flag-off.

When the flag is flipped (per F-14), the gate runs
against the existing fields. No code change is
required for the gate itself; the only change is
the gate's `cabal test` registration (it is
currently in `qxfx0-test-canonical` candidate).

**Schema status (rev. 2)**: P1-P4 OK. **Gate
status**: deferred.

### 2.7 Perspective — needs-work

- **P1**: `trcPerspective` and `trcPerspectiveProjections`
  are serializable.
- **P2**: `PerspectiveOperator` is pure; the registry is
  append-only.
- **P3**: the snapshot is the `PerspectiveRegistry`; replay
  reconstructs the registry from the trace. **Gap**: the
  registry is large (per AGENTS.md P4); the snapshot must be
  stored compactly. **Work**: add a `PerspectiveRegistrySnapshot`
  Σ-type that stores only the `PerspectiveProjection` set,
  not the full lineage.
- **P4**: documented in AGENTS.md P4 + ADR-0009 addendum. The
  explicit `QXFX0_PERSPECTIVE_OPERATOR_ENABLED` flag is
  **not yet added** (per `SELF_LAYER_STATUS.md §4`); the work
  is to add the flag (per F-14 ADR-0016) and then to run
  the gate.

### 2.8 Episodic memory — needs-work

- **P1**: episodic events are serializable (per
  `COGNITIVE_MEMORY_DESIGN.md §4`).
- **P2**: the `Memory.Episodic` module is pure; replays
  produce the same event stream.
- **P3**: snapshot is the entire `ssEpisodicMemory` field;
  reconstruction is total. **Gap**: the snapshot size is
  large (default 1000 events, ~64 KB). **Work**: add a
  `forgettingPolicy` field to the snapshot (per
  `COGNITIVE_MEMORY_DESIGN.md §5`); the snapshot must include
  the policy at snapshot time so that reconstruction under a
  different policy does not violate P2.
- **P4**: documented in `COGNITIVE_MEMORY_DESIGN.md`. **Gap**:
  the trace field is **not yet landed** in `TurnReplayTrace`;
  the trace goes through the snapshot only. **Work**: add
  `trcEpisodicEventIds :: [EpisodicEventId]` so that
  explainability has a per-turn handle.

### 2.9 Learning — needs-work

- **P1**: `trcLearningUpdate` is serializable (per
  `BOUNDED_LEARNING_DESIGN.md §3`).
- **P2**: the `applyLearningUpdate` function is pure; replays
  produce the same contour.
- **P3**: snapshot is the `LearningContour`; reconstruction
  is total. **Gap**: the four invariants I1–I4 are checked at
  apply time but not at snapshot time; a snapshot that
  violates an invariant is not detected. **Work**: add a
  `validateLearningContour` function that runs at snapshot
  time and emits a `trcLearningValidation` trace field.
- **P4**: documented in `BOUNDED_LEARNING_DESIGN.md`. The
  closed lists (T-01..T-07, S-01..S-05) are part of F-03/F-04.

### 2.10 Calibration — needs-work

- **P1**: calibration log entries are serializable.
- **P2**: `Learning.Calibration` is pure.
- **P3**: snapshot is the calibration log + snapshots;
  reconstruction is total. **Gap**: the calibration report
  (per F-10) is **not yet filled**; the first pass is
  pending F-09 (the corpus). **Work**: depends on F-09 + F-10.
- **P4**: documented in `CALIBRATION_BACKLOG.md`; per-parameter
  codomain check is the prerequisite.

### 2.11 Metacognition — needs-work

- **P1**: `trcMetacognition` is serializable (per
  `METACOGNITION_LOOP_DESIGN.md §3`).
- **P2**: `selfEvaluate` is pure.
- **P3**: snapshot is the `MetacognitionContour`; reconstruction
  is total. **Gap**: the contour is not yet landed (Package 9
  is in design only). **Work**: the contour's data type is in
  the design doc; the actual `ss*` field and the snapshot
  function are post-Package 9.
- **P4**: documented in `METACOGNITION_LOOP_DESIGN.md`. The
  external labels (per F-09) are the calibration ground
  truth.

### 2.12 AuthoritySurface (GF) — needs-work

- **P1**: the stub surface is serializable (per F-11).
- **P2**: the stub parser is total `Nothing`; the renderer
  is constant. Replay is trivially deterministic.
- **P3**: the snapshot is the `AuthoritySurface`; the
  round-trip property is `True` (trivially). **Gap**: the
  real parser is not landed; the round-trip coverage is 0
  in the stub. **Work**: when the real parser is landed
  (per Package 4), the round-trip coverage must be ≥ 0.99
  (per `GF_AUTHORITY_SUBSET.md §3`).
- **P4**: documented in `GF_AUTHORITY_SUBSET.md` and F-11.

### 2.13 Semantic commitments — needs-work (Package 2)

- **P1**: the commitment type is serializable (per
  `SEMANTIC_CORE_MIN_SLICE.md §3`).
- **P2**: `commit` and `validatePlan` are pure (per F-05
  walkthrough).
- **P3**: snapshot is the `ssSemanticAnchor` (typed, after
  P2 promotion); reconstruction is total. **Gap**: the
  current `ssSemanticAnchor` is **not typed** (per
  `SYSTEM_STATE_AUTHORITY.md §3`); Package 2 promotes it to
  `SemanticCommitments` (a typed set).
- **P4**: documented in `SEMANTIC_CORE_MIN_SLICE.md §4`.
  The trace field is `trcSemanticCommitment` (new in P2).

## 3. The work list

The triage's "needs-work" entries become the closure plan's
Package-by-package work list. The list is in the order
the closure plan's Packages run.

### 3.1 Salience — gap (small)

- **Action**: add `trcSalienceBias` to the Trace schema doc;
  verify the JSON shape is documented.
- **Owner**: Package 1 (P1 closure).
- **Estimate**: S.

### 3.2 Perspective — gap (medium)

- **Action**: add `PerspectiveRegistrySnapshot` Σ-type
  (projections only, not full lineage); add
  `QXFX0_PERSPECTIVE_OPERATOR_ENABLED` flag (per F-14).
- **Owner**: Package 4 (P4 closure) + Package 10 (F-14).
- **Estimate**: M.

### 3.3 Episodic memory — gap (medium)

- **Action**: add `forgettingPolicy` to the episodic
  snapshot; add `trcEpisodicEventIds` to `TurnReplayTrace`.
- **Owner**: Package 7 (P7 closure).
- **Estimate**: M.

### 3.4 Learning — gap (small)

- **Action**: add `validateLearningContour`; add
  `trcLearningValidation` to `TurnReplayTrace`.
- **Owner**: Package 8 (P8 closure).
- **Estimate**: S.

### 3.5 Calibration — gap (depends on F-09/F-10)

- **Action**: land the calibration report (F-10); first pass
  is the gate. The data is the bottleneck; the code is
  straightforward.
- **Owner**: Package 11 (P11 closure) + F-09 corpus work.
- **Estimate**: L (because the corpus is L-sized).

### 3.6 Metacognition — gap (medium)

- **Action**: land the `MetacognitionContour` Σ-type; add
  `ssMetacognitionLog`; add the snapshot function.
- **Owner**: Package 9 (P9 closure).
- **Estimate**: M.

### 3.7 AuthoritySurface (GF) — gap (depends on Package 4)

- **Action**: land the real parser; the round-trip
  coverage becomes the metric.
- **Owner**: Package 4 (P4 closure) + GF parser dependency.
- **Estimate**: M (the parser is the bulk).

### 3.8 Semantic commitments — gap (medium)

- **Action**: promote `ssSemanticAnchor` to typed
  `SemanticCommitments`; add `trcSemanticCommitment` to
  `TurnReplayTrace`; the round-trip and the explainability
  are the new gates.
- **Owner**: Package 2 (P2 closure).
- **Estimate**: M.

## 4. The deferred contours

The contours that are **deferred** until their flag is
flipped are: Essence, plus (per F-14) any feature that
does not yet have a promotion ADR. The gate does not run
on these contours; the design docs are sufficient for the
closure plan's "design complete" criterion.

## 5. Acceptance criteria for F-13

F-13 is closed when:

- [ ] This file is merged.
- [ ] Every contour in §1 has a triage row in §2.
- [ ] Every "needs-work" contour has a row in §3 with an
      owner package and an estimate.
- [ ] The "passing" and "passing-with-notes" contours
      have a test in `Test.Suite.ReplayGate` (new) that
      locks the four properties P1–P4.
- [ ] The "needs-work" contours have an explicit
      acceptance criterion in the relevant
      `docs/closure/*.md` design doc.

The triage is **regenerated** at every release; the list
in §3 is the work-in-progress for the next release.
