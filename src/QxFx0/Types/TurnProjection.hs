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
