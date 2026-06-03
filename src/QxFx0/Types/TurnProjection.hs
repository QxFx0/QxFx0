{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , PreActorFailureKind(..)
  , PreActorFailureEvent(..)
  , TurnProjection(..)
  ) where

import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..), Register(..), SemanticLayer(..), WarrantedMoveMode(..))
import QxFx0.Types.Decision (RenderStyle(..), ShadowStatus(..), LegitimacyReason(..), PlannerMode(..), ParserMode(..), DecisionDisposition(..))
import QxFx0.Types.Observability (ArtifactManifest, AssemblyPath, AuthorityClass, ContractProvenance, ConvMove(..), ReplayProvenanceStatus, ResponseSurfaceKind, SurfaceProvenance, TruthContractStatus)
import QxFx0.Types.Recovery (LocalRecoveryCause, LocalRecoveryStrategy)
import QxFx0.Types.Thresholds (LegitimacyStatus(..), ScenePressure(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId)
import QxFx0.Types.Decision (ClaimAst)
import QxFx0.Types.State.Perspective (PerspectiveProjection)
import QxFx0.Types.Sense (SenseAxis, SenseOperator)
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase)
import QxFx0.Types.Domain.User (IdentityClaimRef)
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Field (Field)
import QxFx0.Memory.Episodic
  ( EpisodicQuery
  , EpisodicId
  , ReuseAnnotation
  )
import Data.Aeson (ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

data PreActorFailureKind
  = PreActorTransportFailure
  | PreActorFallbackNonAuthoritative
  | PreActorNoExecutableTool
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON)

data PreActorFailureEvent = PreActorFailureEvent
  { pafeKind :: !PreActorFailureKind
  , pafeActionKind :: !Text
  , pafeReason :: !Text
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON)

-- | Canonical replay/projection envelope for a turn.
-- Rich replay visibility does not imply that every field carries canonical
-- authority: this record intentionally mixes canonical truth caps,
-- projection-truth classifications, observational fields, and
-- compatibility/shim markers in one replay plane.
data TurnReplayTrace = TurnReplayTrace
  { trcRequestId :: !Text
  , trcSessionId :: !Text
  , trcRuntimeMode :: !Text
  , trcShadowPolicy :: !Text
  , trcLocalRecoveryPolicy :: !Text
  , trcRecoveryCause :: !(Maybe LocalRecoveryCause)
  , trcRecoveryStrategy :: !(Maybe LocalRecoveryStrategy)
  , trcRecoveryEvidence :: ![Text]
  , trcSemanticIntrospectionEnabled :: !Bool
  , trcWarnMorphologyFallbackEnabled :: !Bool
  , trcRequestedFamily :: !CanonicalMoveFamily
  , trcStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , trcNarrativeHint :: !(Maybe Text)
  , trcIntuitionHint :: !(Maybe Text)
  , trcPreShadowFamily :: !CanonicalMoveFamily
  , trcShadowSnapshotId :: !ShadowSnapshotId
  , trcShadowStatus :: !ShadowStatus
  , trcShadowDivergenceKind :: !ShadowDivergenceKind
  , trcShadowDivergenceSeverity :: !ShadowDivergenceSeverity
  , trcShadowResolvedFamily :: !CanonicalMoveFamily
  , trcFinalFamily :: !CanonicalMoveFamily
  , trcFinalForce :: !IllocutionaryForce
  , trcDecisionDisposition :: !DecisionDisposition
  , trcLegitimacyReason :: !LegitimacyReason
  , trcParserConfidence :: !Double
  , trcParserBackend :: !Text
  , trcParserStatus :: !Text
  , trcParserDegradationReason :: !(Maybe Text)
  , trcParserLatencyMs :: !Int
  , trcEmbeddingQuality :: !Text
  , trcClaimAst :: !(Maybe ClaimAst)
  , trcPreSafetyRenderedRaw :: !Text
  , trcRenderedAfterRebind :: !Text
  , trcLinearizationLang :: !(Maybe Text)
  , trcLinearizationOk :: !Bool
  , trcFallbackReason :: !(Maybe Text)
  , trcContractProvenance :: !(Maybe ContractProvenance)
  , trcSurfaceProvenance :: !(Maybe SurfaceProvenance)
   , trcAuthorityClass :: !(Maybe AuthorityClass)
     -- ^ Response/projection authority classification for the executed turn.
     --   This is not itself the canonical authority root; it is a typed
     --   outcome classification persisted in the replay plane.
   , trcTruthContractStatus :: !TruthContractStatus
     -- ^ Canonical truth-contract cap mirrored into replay. Replay persistence
     --   does not upgrade this field beyond the authoritative state machine.
   , trcResponseSurfaceKind :: !(Maybe ResponseSurfaceKind)
   , trcAssemblyPath :: !(Maybe AssemblyPath)
   , trcArtifactManifest :: !(Maybe ArtifactManifest)
     -- ^ Provenance/audit manifest for the rendered surface. It is a replay
     --   and operator-facing proof aid, not a standalone source-of-truth root.
   , trcReplayProvenanceStatus :: !ReplayProvenanceStatus
     -- ^ Replay completeness / trustworthiness warning surface. This status is
     --   about replay/provenance quality, not canonical runtime authority.
  , trcDerivationTags :: ![Text]
  , trcSalienceDriver :: !Text
    -- ^ Phase 5.5e: rendered snake_case tag for the dominant
    --   'QxFx0.Self.Salience.SalienceDriver' on this turn.
    --   Closed enum tag; stable across builds.
  , trcSalienceHolisticBias :: !Double
    -- ^ Phase 5.5e: 'salienceHolisticBias' in @[0, 1]@.
    --   @0@ = pure formal, @1@ = pure holistic, @0.5@ = neutral.
  , trcSalienceConfidence :: !Double
    -- ^ Phase 5.5e: 'salienceConfidence' in @[0, 1]@.
    --   @1@ = one driver decisively dominates,
    --   @0@ = contributions cancel.
  , trcDeliberationRule :: !(Maybe Text)
  , trcDeliberationAgreement :: !(Maybe Text)
  , trcDeliberationDivergence :: !(Maybe Double)
  , trcDeliberationNarrativeTone :: !(Maybe Text)
  , trcEssenceMode :: !(Maybe Text)
    -- ^ Phase 9: snake_case 'renderEssenceMode' tag of the
    --   post-turn essence.  @Just "witnessing"@ pre-commit;
    --   @Just "contemplative" | "dialogical" | "integrative"@
    --   post-commit (Phase 10).  @Nothing@ only when the essence
    --   layer is statically disabled (not currently exposed).
  , trcEssenceCommitted :: !(Maybe Bool)
    -- ^ Phase 9: @Just False@ pre-commit, @Just True@ post-commit
    --   (Phase 10).  Always @Just False@ in Phase 9 by contract.
  , trcEssenceAngstLevel :: !(Maybe Double)
    -- ^ Phase 9: 'etAngstLevel' of the post-turn trajectory in
    --   @[0, 1]@.  Tracks accumulated unresolved divergence.
  , trcEssenceTrigger :: !(Maybe Text)
    -- ^ Phase 9: snake_case 'renderCommitmentTrigger' tag set only
    --   on the turn a commitment fires (Phase 10).  Always
    --   @Nothing@ in Phase 9.
  , trcLearningQueryType :: !(Maybe Text)
    -- ^ Phase 8: type of learning query, e.g. "definition",
    --   "declension", "concept".  Nothing when no learning loop
    --   was activated this turn.
  , trcExternalTool :: !(Maybe Text)
    -- ^ Phase 8: canonical tool name selected for the learning query.
  , trcLearningValidationStatus :: !(Maybe Text)
    -- ^ Phase 8: "accept" | "reject" | "invalid_response" |
    --   "sandbox_reject" | "not_attempted".
  , trcLearningSandboxResult :: !(Maybe Text)
    -- ^ Phase 8: JSON-encoded 'SandboxMetrics' or reject reason.
  , trcLearningGraftTurn :: !(Maybe Int)
    -- ^ Phase 8: turn number when the fruit was grafted (if accepted).
  , trcLearningRejectReason :: !(Maybe Text)
    -- ^ Phase 8: human-readable reject reason for audit.
  , trcExternalActionReason :: !(Maybe Text)
    -- ^ AS1-03: typed allow/deny/no-action rationale rendered into a stable text tag.
  , trcExternalActionNeed :: !(Maybe Text)
    -- ^ AS1-03: active learning need associated with the outbound action decision.
  , trcPreActorFailureEvent :: !(Maybe PreActorFailureEvent)
    -- ^ AS1-04: typed failure event for outbound attempts that failed before
    --   any executed actor identity existed. Denied/no-action paths remain
    --   actor-clean without fabricating this event.
  , trcSenseAnchor :: !Text
  , trcSenseOperator :: !(Maybe SenseOperator)
  , trcSensePreservedAxes :: ![SenseAxis]
  , trcDialogueFocus :: !Text
  , trcDialogueFocusBefore :: !Text
  , trcDialogueFocusAfter :: !Text
  , trcDialoguePhase :: !DialoguePhase
  , trcDialoguePhaseBefore :: !DialoguePhase
  , trcDialoguePhaseAfter :: !DialoguePhase
  , trcDialogueCommitmentCount :: !Int
  , trcDialogueCommitmentCountBefore :: !Int
   , trcDialogueCommitmentCountAfter :: !Int
   , trcMicroPlanMoves :: ![Text]
   , trcMicroPlanExplicitness :: !Double
   , trcDreamPressureDatalogClass :: !(Maybe Text)
   , trcDreamPressureIntuitionClass :: !(Maybe Text)
   , trcDreamPressureAgreement :: !(Maybe Text)
   , trcDreamPressureStrength :: !(Maybe Double)
   , trcDreamPressureCandidateThresholdFired :: !(Maybe Bool)
   , trcDreamPressureCandidateKinds :: ![Text]
   , trcDreamPressureBiasApplied :: !(Maybe Bool)
   , trcDreamCandidateLifecycleStatuses :: ![Text]
   , trcDreamCandidateDecisionReasons :: ![Text]
   , trcDreamCandidateApplied :: !(Maybe Bool)
   , trcPerspectiveProjection :: !(Maybe PerspectiveProjection)
     -- ^ P4: runtime-safe endorsed perspective projection. Raw candidate
    --   internals and registry lineage are not exposed to render/replay.
  , trcPerspectiveProjections :: ![PerspectiveProjection]
    -- ^ P4: bounded list of active safe projections, preserving the fact
    --   that the canonical registry may contain multiple active scopes.
  , trcConatusEnergy :: !ConatusEnergy
    -- ^ P3: full ConatusEnergy record (ceScalar + ceComponents) from the
    --   current turn's PrepareStatic. Replay can reconstruct the scalar
    --   and per-axis decomposition from this field alone.
  , trcConatusGateFired :: !Bool
    -- ^ P3: True when the structural-energy gate fired this turn
    --   (conatusGateFires). Together with trcConatusEnergy enables
    --   replay-time explanation of Conatus-driven behaviour.
  , trcField :: !Field
    -- ^ P3: full Field Σ-type (resonance, atmosphere, confidence,
    --   consolidation, counterfactual) from the current turn.
    --   Carries all five components so replay has full reconstructability.
  , trcIdentityClaims :: ![IdentityClaimRef]
    -- ^ P3: identity claim references active at turn time,
    --   sourced from ssIdentityClaims. Enables replay-time inspection
    --   of which identity claims were in play.
  , trcEpisodicEncoding :: ![EpisodicId]
    -- ^ P7: EpisodicIds encoded on this turn, empty if no encode was
    --   performed. Enables replay-time explanation of what was recorded.
  , trcEpisodicRetrieval :: !(Maybe (EpisodicQuery, Int))
    -- ^ P7: the query and result count for any episodic retrieval this
    --   turn. @Nothing@ if no retrieval was performed.
  , trcEpisodicForgetting :: !(Int, Maybe EpisodicId)
    -- ^ P7: (count of forgotten events, maybe the last forgotten id).
    --   Enables replay-time explanation of forgetting that occurred.
  , trcRegimeVersion :: !Int
    -- ^ M5: math version active during this turn (from
    --   'QxFx0.Types.RuntimeRegime.currentMathVersion').
    --   Replay can use this to select the correct calibration corpus.
  , trcFamilyDivergenceActive :: !Bool
    -- ^ M5: whether holistic-formal family divergence modulation was active
    --   during this turn (ADR-0019). Replay needs this to reconstruct
    --   salience-modulated routing decisions.
  , trcSemanticCommitmentCount :: !Int
    -- ^ C3 (Package 2): number of active semantic commitments in
    --   'ssSemanticCommitments' at turn completion. Zero when the store
    --   is Nothing (Package 2 not yet initialised). Non-zero indicates
    --   typed domain commitments are accumulating.
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON)

data TurnProjection = TurnProjection
  { tqpTurn              :: !Int
  , tqpParserMode        :: !ParserMode
  , tqpParserConfidence  :: !Double
  , tqpParserErrors      :: ![Text]
  , tqpPlannerMode       :: !PlannerMode
  , tqpPlannerDecision   :: !CanonicalMoveFamily
  , tqpAtomRegister      :: !Register
  , tqpAtomLoad          :: !Double
  , tqpScenePressure     :: !ScenePressure
  , tqpSceneRequest      :: !Text
  , tqpSceneStance       :: !SemanticLayer
  , tqpRenderLane        :: !ConvMove
  , tqpRenderStyle       :: !RenderStyle
  , tqpLegitimacyStatus  :: !LegitimacyStatus
  , tqpLegitimacyReason  :: !LegitimacyReason
  , tqpWarrantedMode     :: !WarrantedMoveMode
  , tqpDecisionDisposition :: !DecisionDisposition
  , tqpOwnerFamily       :: !CanonicalMoveFamily
  , tqpOwnerForce        :: !IllocutionaryForce
  , tqpShadowStatus      :: !ShadowStatus
  , tqpShadowSnapshotId  :: !ShadowSnapshotId
  , tqpShadowDivergenceKind :: !ShadowDivergenceKind
  , tqpShadowFamily      :: !(Maybe CanonicalMoveFamily)
  , tqpShadowForce       :: !(Maybe IllocutionaryForce)
  , tqpShadowMessage     :: !Text
  , tqpReplayTrace       :: !TurnReplayTrace
  , tqpDivergence        :: !Bool
  } deriving stock (Show, Eq)
