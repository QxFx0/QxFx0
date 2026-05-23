{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , TurnProjection(..)
  ) where

import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..), Register(..), SemanticLayer(..), WarrantedMoveMode(..))
import QxFx0.Types.Decision (RenderStyle(..), ShadowStatus(..), LegitimacyReason(..), PlannerMode(..), ParserMode(..), DecisionDisposition(..))
import QxFx0.Types.Observability (ConvMove(..))
import QxFx0.Types.Recovery (LocalRecoveryCause, LocalRecoveryStrategy)
import QxFx0.Types.Thresholds (LegitimacyStatus(..), ScenePressure(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId)
import QxFx0.Types.Decision (ClaimAst)
import QxFx0.Self.Essence (Essence (..), EssenceTrajectory (..), EssenceCommitment (..), renderEssenceMode, renderCommitmentTrigger)
import QxFx0.Types.State.Perspective (PerspectiveProjection)
import QxFx0.Semantic.Sense (SenseAxis, SenseOperator)
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase)
import Data.Aeson (ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

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
  , trcEmbeddingQuality :: !Text
  , trcClaimAst :: !(Maybe ClaimAst)
  , trcLinearizationLang :: !(Maybe Text)
  , trcLinearizationOk :: !Bool
  , trcFallbackReason :: !(Maybe Text)
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
  , trcSenseAnchor :: !Text
  , trcSenseOperator :: !(Maybe SenseOperator)
  , trcSensePreservedAxes :: ![SenseAxis]
  , trcDialogueFocus :: !Text
  , trcDialoguePhase :: !DialoguePhase
  , trcDialogueCommitmentCount :: !Int
  , trcMicroPlanMoves :: ![Text]
  , trcMicroPlanExplicitness :: !Double
  , trcPerspectiveProjection :: !(Maybe PerspectiveProjection)
    -- ^ P4: runtime-safe endorsed perspective projection. Raw candidate
    --   internals and registry lineage are not exposed to render/replay.
  , trcPerspectiveProjections :: ![PerspectiveProjection]
    -- ^ P4: bounded list of active safe projections, preserving the fact
    --   that the canonical registry may contain multiple active scopes.
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
