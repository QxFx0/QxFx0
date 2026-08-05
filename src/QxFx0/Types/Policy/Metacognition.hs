{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Policy.Metacognition
  ( Outcome(..)
  , Evaluation(..)
  , MetacognitionUpdate(..)
  , MetacognitionContour(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Sequence (Seq)
import GHC.Generics (Generic)

import QxFx0.Types.State.SemanticCommitment (TurnSeq)

data Outcome
  = OutcomeAccepted
  | OutcomeRefined
  | OutcomeRejected
  | OutcomeContradicted
  | OutcomeIgnored
  | OutcomeNoFeedback
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Evaluation
  = EvaluationAligned
  | EvaluationMisaligned
  | EvaluationAmbiguous
  | EvaluationUncalibrated
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data MetacognitionUpdate
  = MetacognitionNoUpdate
  | MetacognitionDecrementConfidence
  | MetacognitionClipThreshold
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data MetacognitionContour = MetacognitionContour
  { mcRecentEvaluations :: !(Seq (TurnSeq, Evaluation, Maybe MetacognitionUpdate))
  , mcMisalignCount     :: !Int
  , mcTotalCount        :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
