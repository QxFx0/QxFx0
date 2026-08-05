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
  , detectLearningNeedWithPressure
  , defaultLearningPressureConfig
  , LearningPressureConfig(..)
  , renderLearningNeed
  , learningNeedLevel
  , learningNeedTrend
  , learningNeedPersistence
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Self.Field (Field(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))
import QxFx0.Self.Salience (Salience(..), salienceHolisticBias)
import QxFx0.Types.Learning.Need

-- | A typed deficit that the system can report to itself (and
-- optionally to an external tool) as a reason to acquire new
-- knowledge.
-- | Trend of a need across the observation window.
-- | State of the diagnostic drive.  Kept in 'SystemState' and
-- updated once per turn in 'buildNextSystemState'.
emptyLearningNeedState :: LearningNeedState
emptyLearningNeedState = LearningNeedState
  { lnsCurrentNeed = NeedNone
  , lnsCandidateNeed = NeedNone
  , lnsLevel = 0.0
  , lnsTrend = TrendStable
  , lnsPersistence = 0
  , lnsLastSeenTurn = 0
  , lnsHistory = []
  , lnsUnknownWindowCount = 0
  , lnsWindowStartTurn = 0
  , lnsWindowGraftBaseline = 0
  }

-- | WP6.1: configuration for learning-pressure-driven triggers.
defaultLearningPressureConfig :: LearningPressureConfig
defaultLearningPressureConfig = LearningPressureConfig
  { lpcWindowSize = 10
  , lpcMinUnknownCount = 2
  , lpcStagnationTurns = 5
  }

-- | Thresholds for raising a learning need.
minPersistenceThreshold :: Int
minPersistenceThreshold = 3

maxHistoryLength :: Int
maxHistoryLength = 20

-- | Backward-compatible wrapper: delegates to 'detectLearningNeedWithPressure'
-- with empty pressure signals (keeps old conatus-based lexicon heuristic).
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
  detectLearningNeedWithPressure
    defaultLearningPressureConfig
    conatusEnergy
    field
    repairCount
    unknownTopicCount
    turnCount
    oldState
    False   -- isTopicUnknown
    0       -- currentGraftedCount

-- | WP6.1: Detect a learning need with separate learning-pressure signals.
--
-- 'NeedLexiconExtension' is now driven by learning-pressure signals
-- (unknown-topic window count, graft stagnation) instead of the Conatus
-- scalar floor.  This decouples substrate-learning from structural
-- health so that a large, healthy morphology does not permanently
-- suppress lexicon extension.
--
-- Rules (priority order):
-- 1. 'NeedLexiconExtension' — learning-pressure signals indicate
--    substrate gap (unknown mentions in window + graft stagnation).
-- 2. 'NeedSalienceCalibration' — unchanged (Conatus + field signals).
-- 3. 'NeedKeywordEnrichment' — unchanged (field signals).
-- 4. Otherwise 'NeedNone'.
detectLearningNeedWithPressure
  :: LearningPressureConfig
  -> ConatusEnergy
  -> Field
  -> Int
  -> Int
  -> Int
  -> LearningNeedState
  -> Bool        -- ^ Is the current topic unknown (not in morphology/tree)?
  -> Int         -- ^ Current ktGraftedCount (for stagnation detection).
  -> LearningNeedState
detectLearningNeedWithPressure cfg conatusEnergy field _repairCount unknownTopicCount turnCount oldState isTopicUnknown currentGraftedCount =
  let -- Window management
      windowSize = lpcWindowSize cfg
      windowExpired = turnCount - lnsWindowStartTurn oldState > windowSize
      -- Reset window if expired or on first call (windowStartTurn == 0)
      newWindowStart = if windowExpired || lnsWindowStartTurn oldState == 0
                         then turnCount
                         else lnsWindowStartTurn oldState
      newUnknownCount = if windowExpired
                          then (if isTopicUnknown then 1 else 0)
                          else lnsUnknownWindowCount oldState + (if isTopicUnknown then 1 else 0)
      newGraftBaseline = if windowExpired
                           then currentGraftedCount
                           else lnsWindowGraftBaseline oldState
      graftsInWindow = max 0 (currentGraftedCount - newGraftBaseline)
      stagnation = (turnCount - newWindowStart) >= lpcStagnationTurns cfg
                     && graftsInWindow == 0
                     && newUnknownCount >= lpcMinUnknownCount cfg

      -- WP6.1: Lexicon-extension heuristic — learning pressure, NOT conatus floor
      lexiconLevel =
        if newUnknownCount >= lpcMinUnknownCount cfg && stagnation
           then 0.7 + 0.05 * fromIntegral (min 5 newUnknownCount)
           else 0.0

      -- Salience-calibration heuristic: unchanged (Conatus + field)
      salienceLevel =
        let conf = unFieldConfidence (fieldConfidence field)
            cf   = unCounterfactual (fieldCounterfactual field)
        in if conf < 0.4 && cf > 0.5
              then 0.5 + 0.2 * (0.5 - conf) + 0.2 * cf
              else 0.0

      -- Keyword-enrichment heuristic: unchanged
      keywordLevel =
        let cons = unConsolidation (fieldConsolidation field)
            cf   = unCounterfactual (fieldCounterfactual field)
        in if cf > 0.6 && cons < 0.3
              then 0.6 + 0.2 * cf - 0.2 * cons
              else 0.0

      (candidateNeed, candidateLevel) =
        if lexiconLevel > 0.0
           then (NeedLexiconExtension, min 1.0 lexiconLevel)
           else if salienceLevel > 0.0
                then (NeedSalienceCalibration, min 1.0 salienceLevel)
                else if keywordLevel > 0.0
                     then (NeedKeywordEnrichment, min 1.0 keywordLevel)
                     else (NeedNone, 0.0)

      newPersistence =
        if candidateNeed == lnsCandidateNeed oldState && candidateNeed /= NeedNone
           then lnsPersistence oldState + 1
           else if candidateNeed == NeedNone
                then 0
                else 1

      newHistory = take maxHistoryLength ((turnCount, candidateLevel) : lnsHistory oldState)
      newTrend = computeTrend newHistory

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
       , lnsUnknownWindowCount = newUnknownCount
       , lnsWindowStartTurn = newWindowStart
       , lnsWindowGraftBaseline = newGraftBaseline
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
