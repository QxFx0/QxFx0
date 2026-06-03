{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage planning and commit bundles shared across precommit/commit orchestration. -}
module QxFx0.Core.TurnPipeline.Finalize.Types
  ( FinalizeStatic(..)
  , FinalizePrecommitRequest(..)
  , FinalizePrecommitPlan(..)
  , FinalizePrecommitResults(..)
  , FinalizePrecommitBundle(..)
  , FinalizeCommitPlan(..)
  , FinalizeCommitResults(..)
  ) where

import Data.Text (Text)
import Data.Time.Clock (UTCTime)

import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, ResponseObservation)
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Essence (CommitmentTrigger, EssenceViolation)
import QxFx0.Types

data FinalizeStatic = FinalizeStatic
  { fsOutcomeFamily :: !CanonicalMoveFamily
  , fsOutcomeVerdict :: !R5Verdict
  , fsConsecReflect :: !Int
  , fsTransitionWon :: !Bool
  , fsMeaningGraphBase :: !MeaningGraph
  } deriving stock (Eq, Show)

data FinalizePrecommitRequest
  = FinalizeReqSemanticIntrospectionEnv
  deriving stock (Eq, Show)

data FinalizePrecommitPlan = FinalizePrecommitPlan
  { fppStatic :: !FinalizeStatic
  , fppCapturedCurrentTime :: !UTCTime
  , fppConatusEnergy :: !ConatusEnergy
  , fppIntrospectionRequest :: !FinalizePrecommitRequest
  } deriving stock (Eq, Show)

data FinalizePrecommitResults = FinalizePrecommitResults
  { fprCurrentTime :: !UTCTime
  , fprRuntimeMode :: !Text
  , fprShadowPolicy :: !Text
  , fprLocalRecoveryPolicy :: !Text
  , fprSemanticIntrospectionEnabled :: !Bool
  , fprWarnMorphologyFallbackEnabled :: !Bool
  } deriving stock (Eq, Show)

data FinalizePrecommitBundle = FinalizePrecommitBundle
  { fpbNextSs :: !SystemState
  , fpbProjection :: !TurnProjection
  , fpbOutput :: !Text
  , fpbFinalSafetyStatus :: !Guard.SafetyStatus
  , fpbOutcomeFamily :: !CanonicalMoveFamily
  , fpbDecision :: !TurnDecision
  , fpbRewireEventsCount :: !Int
  , fpbEssenceValidation :: !(Either EssenceViolation ())
    -- ^ Phase 10: pre-commitment essence validation result.
    --   Computed from the pre-turn 'tiEssence' against the
    --   reconciled 'Plan'.  Passed to 'Finalize.Commit' via the
    --   commit plan bundle.
  , fpbCommitmentTrigger :: !(Maybe CommitmentTrigger)
    -- ^ WP1 (contour closure): the 'shouldCommit' result from
    --   'buildNextSystemState'.  Used to detect
    --   'ViolationRefusedCommitment' and to avoid re-computing
    --   'shouldCommit' in 'computeEssenceValidation'.
  } deriving stock (Eq, Show)

data FinalizeCommitPlan = FinalizeCommitPlan
  { fcpResponseObservation :: !ResponseObservation
  , fcpPreviewConsciousLoop :: !ConsciousnessLoop
  , fcpPreviewIntuition :: !IntuitiveState
  , fcpCapturedCurrentTime :: !UTCTime
  , fcpPreviousState :: !SystemState
  , fcpSaveState :: !SystemState
  , fcpSessionId :: !Text
  , fcpProjection :: !TurnProjection
  , fcpRewireEventsCount :: !Int
  , fcpEssenceValidation :: !(Either EssenceViolation ())
    -- ^ Phase 10: pre-commitment essence validation result.
    --   A 'Left' here becomes 'EssenceRupture' in
    --   'resolveFinalizeCommit' before persistence.
  } deriving stock (Show)

data FinalizeCommitResults = FinalizeCommitResults
  { fcrSavedSs :: !SystemState
  , fcrSaveStart :: !UTCTime
  , fcrSaveEnd :: !UTCTime
  } deriving stock (Eq, Show)
