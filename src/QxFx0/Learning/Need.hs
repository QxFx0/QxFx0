{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Need
Description : WP1 — Endogenous learning diagnostic drive.

Computes a typed 'LearningNeed' from persistent runtime signal patterns.
A need is raised only when a pattern is stable across a minimum window
of turns; single-turn noise does not create a need.

The three need classes mirror the three sustainable growth axes:

* 'NeedSalienceCalibration' — weights are drifting but no empirical
  signal is available to correct them.
* 'NeedKeywordEnrichment' — atom-trace shows repeated Searching hits
  with low consolidation (high counterfactual entropy).
* 'NeedLexiconExtension' — morphology gaps are causing repeated
  fallback / unknown-topic recovery.
-}
module QxFx0.Learning.Need
  ( LearningNeed(..)
  , NeedTrend(..)
  , LearningNeedState(..)
  , emptyLearningNeedState
  , detectLearningNeed
  , renderLearningNeed
  , learningNeedLevel
  , learningNeedTrend
  , learningNeedPersistence
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Self.Field (Field(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))
import QxFx0.Self.Salience (Salience(..), salienceHolisticBias)

-- | A typed deficit that the system can report to itself (and
-- optionally to an external tool) as a reason to acquire new
-- knowledge.
data LearningNeed
  = NeedSalienceCalibration
    -- ^ Salience weights may be mis-calibrated; calibration data is
    --   needed to adjust 'SalienceWeights' empirically.
  | NeedKeywordEnrichment
    -- ^ Atom trace shows unresolved Searching / Doubt patterns with
    --   low consolidation; keyword coverage is insufficient.
  | NeedLexiconExtension
    -- ^ Morphology gaps cause repeated unknown-topic recovery or
    --   template fallback.
  | NeedNone
    -- ^ No persistent deficit detected in the current window.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Trend of a need across the observation window.
data NeedTrend
  = TrendRising
    -- ^ Deficit metric is increasing (getting worse).
  | TrendStable
    -- ^ Deficit metric is within a dead band.
  | TrendFalling
    -- ^ Deficit metric is decreasing (improving).
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | State of the diagnostic drive.  Kept in 'SystemState' and
-- updated once per turn in 'buildNextSystemState'.
data LearningNeedState = LearningNeedState
  { lnsCurrentNeed :: !LearningNeed
    -- ^ The currently active need (or 'NeedNone').
    --   This is the threshold-gated need exposed to downstream.
  , lnsCandidateNeed :: !LearningNeed
    -- ^ The raw dominant need before persistence threshold is applied.
    --   Used internally so that persistence can accumulate across turns
    --   even when the threshold has not yet been met.
  , lnsLevel :: !Double
    -- ^ Normalised deficit severity in [0, 1].  0 = no deficit.
  , lnsTrend :: !NeedTrend
    -- ^ Direction of change over the observation window.
  , lnsPersistence :: !Int
    -- ^ How many consecutive turns this need has been observed.
    --   Resets to 0 when the need class changes or drops to None.
  , lnsLastSeenTurn :: !Int
    -- ^ Turn count of the most recent observation.
  , lnsHistory :: ![(Int, Double)]
    -- ^ (turn, level) pairs for the last N turns (capped at 20).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON LearningNeedState where
  toJSON s = object
    [ "currentNeed" .= lnsCurrentNeed s
    , "candidateNeed" .= lnsCandidateNeed s
    , "level" .= lnsLevel s
    , "trend" .= lnsTrend s
    , "persistence" .= lnsPersistence s
    , "lastSeenTurn" .= lnsLastSeenTurn s
    , "history" .= lnsHistory s
    ]

instance FromJSON LearningNeedState where
  parseJSON = withObject "LearningNeedState" $ \o ->
    LearningNeedState
      <$> o .:? "currentNeed" .!= NeedNone
      <*> o .:? "candidateNeed" .!= NeedNone
      <*> o .:? "level" .!= 0.0
      <*> o .:? "trend" .!= TrendStable
      <*> o .:? "persistence" .!= 0
      <*> o .:? "lastSeenTurn" .!= 0
      <*> o .:? "history" .!= []

emptyLearningNeedState :: LearningNeedState
emptyLearningNeedState = LearningNeedState
  { lnsCurrentNeed = NeedNone
  , lnsCandidateNeed = NeedNone
  , lnsLevel = 0.0
  , lnsTrend = TrendStable
  , lnsPersistence = 0
  , lnsLastSeenTurn = 0
  , lnsHistory = []
  }

-- | Thresholds for raising a learning need.
minPersistenceThreshold :: Int
minPersistenceThreshold = 3

maxHistoryLength :: Int
maxHistoryLength = 20

-- | Detect a learning need from the current turn signals.
--
-- Rules (applied in priority order):
--
-- 1. 'NeedLexiconExtension' — if the Conatus scalar is below a
--    conservative floor AND the morphology component of the gradient
--    was dominant in recent recovery, we lack substrate.
-- 2. 'NeedSalienceCalibration' — if salience bias is stuck in a
--    narrow band (low confidence / high counterfactual) across the
--    window, empirical calibration is needed.
-- 3. 'NeedKeywordEnrichment' — if field counterfactual is high
--    (candidate entropy) but consolidation is low, meaning atoms are
--    not resolving into clusters.
-- 4. Otherwise 'NeedNone'.
--
-- The returned level is a composite of the underlying metric
-- normalised to [0, 1].
detectLearningNeed
  :: ConatusEnergy
  -> Field
  -> Int
     -- ^ Number of repair-loop recoveries in the last 10 turns.
  -> Int
     -- ^ Number of unknown-topic recoveries in the last 10 turns.
  -> Int
     -- ^ Current turn count.
  -> LearningNeedState
  -> LearningNeedState
detectLearningNeed conatusEnergy field repairCount unknownTopicCount turnCount oldState =
  let -- Lexicon-extension heuristic: low conatus + high unknown-topic rate
      lexiconLevel =
        if ceScalar conatusEnergy < 0.5
           && unknownTopicCount >= 2
           then 0.7 + 0.1 * fromIntegral (min 3 unknownTopicCount)
           else 0.0

      -- Salience-calibration heuristic: low confidence + high counterfactual
      salienceLevel =
        let conf = unFieldConfidence (fieldConfidence field)
            cf   = unCounterfactual (fieldCounterfactual field)
        in if conf < 0.4 && cf > 0.5
              then 0.5 + 0.2 * (0.5 - conf) + 0.2 * cf
              else 0.0

      -- Keyword-enrichment heuristic: high counterfactual + low consolidation
      keywordLevel =
        let cons = unConsolidation (fieldConsolidation field)
            cf   = unCounterfactual (fieldCounterfactual field)
        in if cf > 0.6 && cons < 0.3
              then 0.6 + 0.2 * cf - 0.2 * cons
              else 0.0

      -- Select the dominant need by level (priority order as tie-breaker)
      (candidateNeed, candidateLevel) =
        if lexiconLevel > 0.0
           then (NeedLexiconExtension, min 1.0 lexiconLevel)
           else if salienceLevel > 0.0
                then (NeedSalienceCalibration, min 1.0 salienceLevel)
                else if keywordLevel > 0.0
                     then (NeedKeywordEnrichment, min 1.0 keywordLevel)
                     else (NeedNone, 0.0)

      -- Update persistence: increment if same *candidate* class, else reset.
      -- We compare against lnsCandidateNeed (raw, pre-threshold) so that
      -- persistence accumulates even when the threshold has not yet been met.
      newPersistence =
        if candidateNeed == lnsCandidateNeed oldState && candidateNeed /= NeedNone
           then lnsPersistence oldState + 1
           else if candidateNeed == NeedNone
                then 0
                else 1

      -- Update history
      newHistory = take maxHistoryLength ((turnCount, candidateLevel) : lnsHistory oldState)

      -- Compute trend from history (simple slope over last 3 points)
      newTrend = computeTrend newHistory

      -- Final need: only return a non-None need if persistence is above threshold
      finalNeed =
        if candidateNeed /= NeedNone && newPersistence >= minPersistenceThreshold
           then candidateNeed
           else NeedNone

      finalLevel = if finalNeed == NeedNone then 0.0 else candidateLevel

  in LearningNeedState
       { lnsCurrentNeed = finalNeed
       , lnsCandidateNeed = candidateNeed
       , lnsLevel = finalLevel
       , lnsTrend = newTrend
       , lnsPersistence = newPersistence
       , lnsLastSeenTurn = turnCount
       , lnsHistory = newHistory
       }

computeTrend :: [(Int, Double)] -> NeedTrend
computeTrend history =
  case history of
    [] -> TrendStable
    [_] -> TrendStable
    -- Compare last two points
    (_, y1) : (_, y0) : _
      | abs (y1 - y0) < 0.05 -> TrendStable
      | y1 > y0              -> TrendRising
      | otherwise            -> TrendFalling

-- | Render a 'LearningNeed' to a short telemetry tag.
renderLearningNeed :: LearningNeed -> Text
renderLearningNeed NeedSalienceCalibration = "need_salience_calibration"
renderLearningNeed NeedKeywordEnrichment   = "need_keyword_enrichment"
renderLearningNeed NeedLexiconExtension    = "need_lexicon_extension"
renderLearningNeed NeedNone                = "need_none"

-- | Convenience accessors for telemetry.
learningNeedLevel :: LearningNeedState -> Double
learningNeedLevel = lnsLevel

learningNeedTrend :: LearningNeedState -> NeedTrend
learningNeedTrend = lnsTrend

learningNeedPersistence :: LearningNeedState -> Int
learningNeedPersistence = lnsPersistence
