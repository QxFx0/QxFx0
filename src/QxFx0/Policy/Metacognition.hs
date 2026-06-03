{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Policy.Metacognition
  ( Outcome(..)
  , Evaluation(..)
  , MetacognitionUpdate(..)
  , MetacognitionContour(..)
  , emptyMetacognitionContour
  , observeResponse
  , selfEvaluate
  , boundedCorrection
  , runMetacognitionLoop
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Prelude (Bool(..), Double, Eq(..), Int, Maybe(..), Num(..), Ord(..), Show, (&&), ($), (.), (++), (+), (==), (||), any, maybe, not, null, otherwise, pure)

import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))

-- | Outcome of a previous turn, observed from the user's response.
data Outcome
  = OutcomeAccepted
  | OutcomeRefined
  | OutcomeRejected
  | OutcomeContradicted
  | OutcomeIgnored
  | OutcomeNoFeedback
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Self-evaluation of a decision given its outcome.
data Evaluation
  = EvaluationAligned
  | EvaluationMisaligned
  | EvaluationAmbiguous
  | EvaluationUncalibrated
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | A metacognitive correction update (placeholder until P8 lands).
-- When Package 8 (bounded learning) is in place, this will be
-- replaced by or extended to a 'LearningUpdate' routed through
-- 'applyLearningUpdate'.
data MetacognitionUpdate
  = MetacognitionNoUpdate
  | MetacognitionDecrementConfidence
  | MetacognitionClipThreshold
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Running metacognitive state within a session.
data MetacognitionContour = MetacognitionContour
  { mcRecentEvaluations :: !(Seq (TurnSeq, Evaluation, Maybe MetacognitionUpdate))
  , mcMisalignCount     :: !Int
  , mcTotalCount        :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

emptyMetacognitionContour :: MetacognitionContour
emptyMetacognitionContour = MetacognitionContour
  { mcRecentEvaluations = Seq.empty
  , mcMisalignCount = 0
  , mcTotalCount = 0
  }

-- | Observe the outcome of the previous turn from the user's current
--   input text. Parser-typed, no keyword heuristics: uses a fixed
--   set of acceptance/rejection/refinement markers.
observeResponse :: Text -> Outcome
observeResponse raw =
  let txt = T.toLower (T.strip raw)
  in if any (`T.isInfixOf` txt) acceptanceMarkers
     then OutcomeAccepted
     else if any (`T.isInfixOf` txt) rejectionMarkers
          then if any (`T.isInfixOf` txt) contradictionMarkers
               then OutcomeContradicted
               else OutcomeRejected
          else if any (`T.isInfixOf` txt) refinementMarkers
               then OutcomeRefined
               else if any (`T.isInfixOf` txt) ignoreMarkers
                    then OutcomeIgnored
                    else OutcomeNoFeedback

acceptanceMarkers :: [Text]
acceptanceMarkers =
  [ "yes", "yeah", "ok", "okay", "sure", "correct", "right"
  , "да", "ага", "ok", "хорошо", "верно", "согласен"
  ]

rejectionMarkers :: [Text]
rejectionMarkers =
  [ "no", "nope", "not", "don't", "doesn't"
  , "нет", "не", "неправ", "неверн"
  ]

contradictionMarkers :: [Text]
contradictionMarkers =
  [ "actually", "but", "however", "instead"
  , "на самом деле", "но", "однако"
  ]

refinementMarkers :: [Text]
refinementMarkers =
  [ "i mean", "more precisely", "rather", "specifically"
  , "я имею в виду", "точнее", "а именно"
  ]

ignoreMarkers :: [Text]
ignoreMarkers =
  [ "let's move", "next", "another", "change topic"
  , "давай", "следующий", "другой"
  ]

-- | Self-evaluate a decision given the observed outcome.
-- Uses deliberation agreement and recovery status to produce
-- a calibrated evaluation.
selfEvaluate
  :: Double          -- ^ deliberation agreement (0=disagree, 1=agree)
  -> Bool            -- ^ was the turn in recovery?
  -> Outcome
  -> Evaluation
selfEvaluate agreement inRecovery outcome =
  case outcome of
    OutcomeAccepted
      | inRecovery -> EvaluationAmbiguous
      | otherwise  -> EvaluationAligned
    OutcomeRefined -> EvaluationAmbiguous
    OutcomeRejected
      | agreement >= 0.7 -> EvaluationMisaligned
      | otherwise        -> EvaluationAligned
    OutcomeContradicted
      | agreement >= 0.7 -> EvaluationMisaligned
      | otherwise        -> EvaluationAligned
    OutcomeIgnored
      | inRecovery -> EvaluationAligned
      | otherwise  -> EvaluationAmbiguous
    OutcomeNoFeedback -> EvaluationUncalibrated

-- | Map an evaluation to a bounded correction update.
-- Returns Nothing when no correction is needed.
boundedCorrection :: Evaluation -> Maybe MetacognitionUpdate
boundedCorrection eval =
  case eval of
    EvaluationAligned     -> Nothing
    EvaluationMisaligned  -> Just MetacognitionDecrementConfidence
    EvaluationAmbiguous   -> Nothing
    EvaluationUncalibrated -> Just MetacognitionClipThreshold

-- | Run one step of the metacognitive loop.
-- Pure: takes the current contour, the user's input, and the
-- deliberation state; returns the updated contour.
runMetacognitionLoop
  :: MetacognitionContour
  -> TurnSeq
  -> Text               -- ^ user input (for outcome observation)
  -> Double             -- ^ deliberation agreement
  -> Bool               -- ^ in recovery
  -> MetacognitionContour
runMetacognitionLoop contour turnSeq rawText agreement inRecovery =
  let outcome = observeResponse rawText
      evaluation = selfEvaluate agreement inRecovery outcome
      correction = boundedCorrection evaluation
      window = Seq.take 100 (mcRecentEvaluations contour Seq.|> (turnSeq, evaluation, correction))
  in MetacognitionContour
    { mcRecentEvaluations = window
    , mcMisalignCount = mcMisalignCount contour
      + (if evaluation == EvaluationMisaligned then 1 else 0)
    , mcTotalCount = mcTotalCount contour + 1
    }
