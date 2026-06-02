# SystemState Field Authority Map (QxFx0_v3)

- **Status**: Active (closure-phase follow-up F-01, Package 1)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/AUTHORITY_MAP.md` §8, AGENTS.md
- **Related**:
  - `docs/AUTHORITY_BOUNDARY.md` (2026-05-26) §3
  - `docs/closure/SELF_LAYER_STATUS.md`

## 0. Why this document exists

`AUTHORITY_MAP.md §8` promised a per-field classification of
every `ss*` field on `SystemState` as a follow-up. This is
that follow-up. The table below classifies every field by:

- **role**: one of `canonical`, `canonical-flag-off`,
  `derived`, `supplier-input`, `observer`, `legacy`.
- **writer**: the module(s) that may write to the field.
- **reader**: the module(s) that may read the field.
- **replay-visible**: does the field appear in the replay
  envelope (per `REPLAY_GATE_SPEC.md`)?
- **notes**: anything else relevant to authority.

The field list is from
`src/QxFx0/Types/State/System.hs` (and the related types in
`src/QxFx0/Types/State/`). Field names are taken from the
Haskell source.

## 1. Field authority table

The table is sorted by field name for stable diffs.

### 1.1 Identity / session

| Field | Role | Writer | Reader | Replay-visible | Notes |
|---|---|---|---|---|---|
| `ssSessionId :: !Text` | `canonical` | `Runtime.Session.Bootstrap` | all | yes | The session id is the primary key for replay. |
| `ssOutputMode :: !DialogueOutputMode` | `canonical` | runtime / API | render | yes | |
| `ssTurnCount :: !Int` | `canonical` | orchestrator | all | yes | Monotonic per session. |

### 1.2 Self layer

| Field | Role | Writer | Reader | Replay-visible | Notes |
|---|---|---|---|---|---|
| `ssEssence :: !Essence` | `canonical-flag-off` | `Core.TurnPipeline.Finalize.State` (gated by `essenceCommitmentEnabled`) | `Self.Essence`, `Self.Deliberation` (reconcile courtesy) | yes (`trcEssence*`) | Flag-off default; per AGENTS.md "landed but default False". |
| `ssSalienceWeights :: !SalienceWeights` | `canonical` | `Self.Salience.defaultSalienceWeights` (init); `QxFx0.Learning.Contour` (when bounded learning lands) | `Self.Salience.computeSalience` | yes (`trcSalience*`) | Calibration-knob per Package 11. |
| `ssFieldHeuristics :: !FieldHeuristics` | `canonical` | `Self.Field.defaultFieldHeuristics` (init); `QxFx0.Learning.Contour` | `Self.Field` | yes | Calibration-knob per Package 11. |
| `ssShadowVetoState :: !ShadowVetoState` | `derived` | rebuilt from canonical history on load | `Core.TurnPipeline.Route.Render` | yes | Demoted on non-authoritative restore per `AUTHORITY_BOUNDARY.md §3`. |
| `ssLastGuardReport :: !GuardReport` | `compatibility-only` | `Core.Guard` (cleared before persistence) | diagnostic | partial | Not in canonical load path; per `AUTHORITY_BOUNDARY.md §3`. |
| `ssLastTurnDecision :: !TurnDecision` | `canonical` (under review `SLICE-TD-001`) | `Core.TurnPipeline.Finalize.State` | downstream | yes | Whole-field authority `NOT PROVEN` per `AUTHORITY_BOUNDARY.md §3`; under `SLICE-TD-001` review. |
| `ssGovernanceProjection :: !GovernanceProjection` | `derived` | rebuilt from `ssGovernanceHistory` on load | `Core.Governance` | yes | Per `AUTHORITY_BOUNDARY.md §3`. |
| `ssGovernanceHistory :: ![GovernanceEvent]` | `canonical` | `Core.Governance` | `Core.Governance`, `Bridge.StatePersistence` | yes | Canonical source for governance restoration. |
| `ssGovernanceRuntimeFault :: !(Maybe GovernanceRuntimeFault)` | `canonical` | `Core.Governance` | runtime | yes | |
| `ssPerspectiveRegistry :: !PerspectiveRegistry` | `canonical-flag-off` (lineage) + `derived` (projection) | `Self.Perspective.Operator` (gated); `Self.Perspective.Projection` (derived) | `render` (projection only) | yes | Per AGENTS.md P4; "replay/render may consume only `PerspectiveProjection`". |
| `ssTruthContractStatus :: !TruthContractStatus` | `canonical` | `Core.Governance` | all | yes | Non-authoritative rebuild gate per `AUTHORITY_BOUNDARY.md §3`. |
| `ssLastFamily :: !CanonicalMoveFamily` | `canonical` | `Core.TurnRouting` | downstream | yes | |
| `ssLastTopic :: !Text` | `canonical` | `Core.TopicTransition` | downstream | yes | |
| `ssLastForce :: !ForceTag` | `canonical` | `Core.TurnRouting` | downstream | yes | |
| `ssLastLayer :: !LayerTag` | `canonical` | `Core.TurnRouting` | downstream | yes | |
| `ssLastEmbedding :: !(Maybe Vector)` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |

### 1.3 Memory / history

| Field | Role | Writer | Reader | Replay-visible | Notes |
|---|---|---|---|---|---|
| `ssHistory :: ![HistoryEntry]` | `canonical` (per-turn) | `Core.TurnPipeline` | all | yes | The per-turn history list. The closure plan's Package 7 turns this into usable episodic memory. |
| `ssRawInputHistory :: ![Text]` | `canonical` | `Core.TurnPipeline` | replay | yes | Raw input for replay. |
| `ssOrbitalMemory :: !OrbitalMemory` | `canonical` | `Core.IdentitySignal` | `Core.Ego` | yes | |
| `ssRecentFamilies :: ![CanonicalMoveFamily]` | `canonical` | `Core.TurnRouting` | `Core.TurnRouting` | yes | |
| `ssRecentNarrativeSuccess :: ![Bool]` | `canonical` | `Core.Metacognition` (post-Package 9) | `Core.Metacognition` | yes | Pre-Package 9: keyword-conditional in `observeOwnResponse`. |
| `ssHolisticStreak :: !Int` | `canonical` | `Core.ConsciousnessLoop` | `Self.Salience` | yes | |
| `ssRecentNarrativeSuccess` (count) | `canonical` | post-Package 9 | post-Package 9 | yes | |

### 1.4 Salience / deliberation / kernel pulse

| Field | Role | Writer | Reader | Replay-visible | Notes |
|---|---|---|---|---|---|
| `ssKernelPulse :: !KernelPulse` | `canonical` | `Core.TurnPipeline.PrepareStatic` (M6) | `Self.Salience`, downstream | yes | Single source of truth per M6 (AGENTS.md). |
| `ssIntuitConfidence :: !Double` | `canonical` | `Self.Salience.computeSalience` | downstream | yes (`trcSalienceConfidence`) | |
| `ssIntuitionState :: !IntuitionState` | `canonical` | `Core.Intuition` | downstream | yes | |
| `ssLastSalienceBias :: !Double` | `canonical` | `Self.Salience.computeSalience` | downstream | yes (`trcSalienceHolisticBias`) | |
| `ssDreamState :: !DreamState` | `observer` | `Core.DreamDynamics` | trace only | yes | Observer-only. |
| `ssDreamAxiom :: !DreamAxiom` | `observer` | `Core.DreamDynamics` | trace only | yes | Observer-only. |
| `ssSemanticAnchor :: !SemanticAnchor` | `compatibility / demoted` | persisted for compatibility; demoted on non-authoritative restore | replay / diagnostic | partial | Per `AUTHORITY_BOUNDARY.md §3`. Package 2 promotes this to typed semantic commitments. |
| `ssDiscourse :: !Discourse` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |
| `ssIdentityClaims :: ![IdentityClaim]` | `canonical` | `Core.IdentitySignal` | downstream | yes | |
| `ssUserState :: !UserState` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |
| `ssEgo :: !Ego` | `canonical` | `Core.Ego` | downstream | yes | |
| `ssActiveScene :: !Scene` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |
| `ssBlockedConcepts :: ![Text]` | `canonical` | `Core.Guard` | downstream | yes | |
| `ssClusters :: ![Cluster]` | `canonical` | `Core.MeaningGraph` | downstream | yes | |
| `ssDialogueThread :: !DialogueThread` | `canonical` | `Core.DialogueThread` | downstream | yes | |
| `ssDialoguePhase :: !DialoguePhase` | `canonical` | `Core.TurnPipeline` | downstream | yes | Per `docs/adr/0032-dialogue-development-contours.md`. |
| `ssDialogueCommitmentLedger :: !DialogueCommitmentLedger` | `canonical` | `Core.TurnPipeline` | downstream | yes | Per `docs/adr/0032`. |
| `ssDialogueOutcomeLearning :: !DialogueOutcomeLearningState` | `canonical-flag-off` | post-Package 8 (LearningContour client) | `QxFx0.Learning.Contour` | yes | Pre-Package 8: zero/stub signals. |
| `ssSpeechPolicyState :: !SpeechPolicyState` | `canonical` | `Core.TurnRouting` (reads); `Core.SpeechPolicy` | downstream | yes | Per AGENTS.md "route reads speech policy". |
| `ssBeliefStore :: !BeliefStore` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |
| `ssKnowledgeTree :: !KnowledgeTree` | `canonical` | `Core.KnowledgeTree` | downstream | yes | Per `docs/adr/0025-rooted-knowledge-tree.md`. |
| `ssToolReliability :: !(M.Map Text Double)` | `canonical` | `Core.ToolRegistry` | downstream | yes | |
| `ssProvisionalAtoms :: ![ProvisionalAtom]` | `canonical` | `Core.AtomFindingAdmission` | downstream | yes | |
| `ssLearningNeedState :: !LearningNeedState` | `canonical` | `QxFx0.Learning.Contour` (post-Package 8) | `Core.TurnPipeline.Route.Render.buildLocalRecoveryPlan` | yes | Pre-Package 8: persisted; read by recovery. |
| `ssGuardrailState :: !GuardrailState` | `canonical` | `Core.Guard` | downstream | yes | |
| `ssCalibrationLog :: !CalibrationLog` | `canonical-flag-off` (pre-Package 11) → `derived` (post-Package 11) | `QxFx0.Learning.Contour` (post-Package 8) | trace | yes | |
| `ssCalibrationSnapshots :: ![CalibrationSnapshot]` | `canonical-flag-off` → `derived` | post-Package 11 | trace | yes | |
| `ssAdaptiveMutationLog :: ![AdaptiveMutationRecord]` | `canonical-flag-off` (pre-Package 8) → `derived` (post-Package 8) | `QxFx0.Learning.Contour` (post-Package 8) | trace | yes | Per AGENTS.md "weak acknowledgement phrases are observational and must not trigger strong mutation without a shared `AdaptiveMutationRecord`". |
| `ssObservability :: !ObservabilityState` | `canonical` | `Core.Observability` | trace | yes | |

### 1.5 Semantic / morphology

| Field | Role | Writer | Reader | Replay-visible | Notes |
|---|---|---|---|---|---|
| `ssSemantic :: !SemanticState` | `canonical` | `Core.TurnPipeline.Effects` | downstream | yes | |
| `ssSemanticConfig :: !SemanticConfig` | `canonical` | `QxFx0.Semantic.Config` (init) | `Core.TurnPipeline.Effects` | yes | |
| `ssMorphology :: !MorphologyData` | `canonical` | `QxFx0.Lexicon.Morphology` (post-Package 5) | downstream | yes | Post-Package 5: `services/morphology/server.py` is gone; field is populated by the Haskell parser. |

### 1.6 Closure-plan additions (P2 / P7 / P8 / P9 / P11)

These fields are added by the closure plan and are `Nothing`
in `emptySystemState`. They become `Just _` only after the
corresponding package lands.

| Field | Role | Owner-package | When populated |
|---|---|---|---|
| `ssSemanticCommitments :: !(Maybe SemanticCommitmentStore)` | `canonical` (post-Package 2) | P2 | after `commitObservation` |
| `ssEpisodic :: !(Maybe EpisodicStore)` | `canonical` (post-Package 7) | P7 | after `encode` |
| `ssLearning :: !(Maybe LearningContour)` | `canonical` (post-Package 8) | P8 | after first `applyLearningUpdate` |
| `ssMetacognition :: !(Maybe MetacognitionContour)` | `canonical` (post-Package 9) | P9 | after first `selfEvaluate` |

## 2. Boundary rules for `ss*` writes

1. **Writers must be in the allowed list.** A new writer for
   a `canonical` field must be added to this table before
   being merged. The CI check is: every module that writes to
   a `canonical` `ss*` field appears in the `Writer` column.
2. **Flag-off fields are written only when the flag is on.**
   A write to `ssEssence` (or other `canonical-flag-off`
   fields) when the flag is off is a `check_architecture.sh`
   violation. The runtime gate is `essenceCommitmentEnabled`
   (or equivalent).
3. **Derived fields are never directly written.** A
   `derived` field is computed from canonical sources on
   load; it is **not** persisted as a writer's output.
4. **Compatibility fields are demoted on non-authoritative
   restore.** A compatibility field's content is preserved
   on authoritative restore and demoted (cleared) on
   non-authoritative restore, per `AUTHORITY_BOUNDARY.md §3`.
5. **Observer fields are read by trace only.** A reader of
   an `observer` field that is not a trace renderer is a
   `check_architecture.sh` violation.

## 3. Open items

1. `ssLastTurnDecision` is under `SLICE-TD-001` review per
   `AUTHORITY_BOUNDARY.md §3`. The verdict of that review
   may change this field's role from `canonical (under
   review)` to `derived` or `canonical` outright.
2. `ssSemanticAnchor` is currently a compatibility field;
   Package 2 promotes it (or replaces it) with typed
   `SemanticCommitmentStore`. The exact migration is
   Package 2's implementation detail.
3. `ssAdaptiveMutationLog` is currently zero-signal per
   AGENTS.md. Package 8 wires it to the `LearningContour`;
   after that, it becomes `derived` from learning updates.
4. `ssDialogueOutcomeLearning` follows the same path as
   `ssAdaptiveMutationLog` (zero-signal → bounded learning
   consumer).
5. New fields may be added by future packages (e.g. a
   `ssBeliefRevisionLog` from a future Package 2.x). The
   rule is: every new field gets an entry in this table at
   the same PR.

## 4. Acceptance criteria for F-01

F-01 is closed when:

- [ ] This file is merged.
- [ ] Every `ss*` field on `SystemState` is in the table.
- [ ] The five boundary rules of §2 are enforced by
      `check_architecture.sh`.
- [ ] The closure plan's `SLICE-TD-001` verdict is reflected
      in the `ssLastTurnDecision` row.
- [ ] The Package 2, 7, 8, 9, 11 changes to the table are
      updated as those packages land.
