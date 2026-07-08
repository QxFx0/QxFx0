{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Tuning
Description : Phase II — corpus-driven calibration tuning orchestration.

Wires the extractor, candidate generator, evaluator and persistence layer
into a single CLI-callable pipeline:

1. Extract a 'TrainingDataset' from the SQLite corpus.
2. Generate a bounded grid of salience/field candidates.
3. Evaluate each candidate with the offline proxy evaluator from
   'Learning.TrainingCycle'.
4. Select the best non-regressing candidate.
5. Persist the winner to @resources/config/tuned_*.json@.

The pipeline is deterministic given the same corpus and candidate grid.
-}
module QxFx0.Learning.Tuning
  ( -- * Tuning pipeline
    runCorpusTuning
    -- * Constituents (exported for tests)
  , generateTuningCandidates
  , selectBestCandidate
  , persistTunedConfig
  , defaultTuningSignals
  ) where

import Control.Monad (when)
import Data.Aeson (encode)
import Data.List (sortOn)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import Data.Time.Clock (UTCTime, getCurrentTime)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesFileExist
  , renameFile
  )
import System.FilePath (takeDirectory, (<.>))
import System.IO (hPutStrLn, stderr)

import QxFx0.Bridge.StatePersistence (DbRunner)
import QxFx0.Learning.Calibration (CalibrationId(..))
import QxFx0.Learning.CorpusExtract (SessionId, extractCorpusDataset)
import QxFx0.Learning.TrainingCycle
  ( CalibrationCandidate(..)
  , CandidateEvaluation(..)
  , CandidateType(..)
  , CandidateVerdict(..)
  , EvaluationMetrics(..)
  , TrainingCycleOutcome(..)
  , TrainingCycleConfig(..)
  , TrainingDataset(..)
  , defaultTrainingCycleConfig
  , evaluateCandidate
  , evaluateAllCandidates
  , generateCandidates
  )
import QxFx0.Self.Field (FieldHeuristics)
import QxFx0.Self.Salience (SalienceWeights)

-- | Bounded adaptation signals used as the grid for corpus tuning.
-- Positive values nudge the system toward Holistic-bias weights;
-- negative values toward Formal-bias weights.
defaultTuningSignals :: [Double]
defaultTuningSignals = [-0.30, -0.15, 0.0, 0.15, 0.30]

-- | Run the full corpus-driven tuning pipeline.
--
-- The outcome includes every evaluated candidate (accepted first, sorted
-- by net score) and, if one passed the fail-closed policy, the promoted
-- candidate.  The promoted configuration is also written to
-- @resources/config/tuned_salience_weights.json@ or
-- @resources/config/tuned_field_heuristics.json@ depending on its type.
runCorpusTuning :: DbRunner -> Maybe SessionId -> IO TrainingCycleOutcome
runCorpusTuning withDb mSessionId = do
  dataset <- extractCorpusDataset withDb mSessionId
  tstamp <- getCurrentTime
  let cycleId = "corpus-tuning-" <> maybe "all" id mSessionId
      startId = CalibrationId 1
      cfg = (defaultTrainingCycleConfig cycleId startId)
        { tccSignals = defaultTuningSignals
        , tccMinEvalTraces = 3
        }
      candidates = generateTuningCandidates startId (tccSignals cfg) cycleId tstamp
      evaluations = evaluateAllCandidates dataset candidates
      promoted = selectBestCandidate evaluations
  case promoted of
    Just cand -> persistTunedConfig cand
    Nothing   -> hPutStrLn stderr "corpus_tuning: no non-regressing candidate selected"
  pure TrainingCycleOutcome
    { tcoCycleId           = cycleId
    , tcoDatasetStats      = case dataset of
                               TrainingDataset _ _ _ s -> s
    , tcoCandidates        = evaluations
    , tcoPromotedCandidate = promoted
    , tcoPreviousVersion   = Just startId
    , tcoRollbackEntry     = Nothing
    }

-- | Generate a bounded grid of calibration candidates.
--
-- Each signal produces one 'CandidateSalience' and one 'CandidateField'
-- candidate by applying the bounded adaptation functions from
-- 'Self.Salience' and 'Self.Field'.
generateTuningCandidates
  :: CalibrationId
  -> [Double]
  -> Text
  -> UTCTime
  -> [CalibrationCandidate]
generateTuningCandidates = generateCandidates

-- | Select the single best accepted candidate from a list of evaluations.
--
-- 'evaluateAllCandidates' already sorts accepted candidates by net score
-- descending.  This function simply takes the head of the accepted list,
-- returning 'Nothing' when every candidate was rejected.
selectBestCandidate :: [CandidateEvaluation] -> Maybe CalibrationCandidate
selectBestCandidate evaluations =
  listToMaybe
    [ ceCandidate e
    | e <- evaluations
    , ceVerdict e == CandidateAccept
    ]

-- | Persist a promoted candidate to the runtime config directory.
-- The path depends on the candidate type:
--
-- * 'CandidateSalience' -> @resources/config/tuned_salience_weights.json@
-- * 'CandidateField'    -> @resources/config/tuned_field_heuristics.json@
--
-- Missing directories are created on demand.  A candidate without its
-- expected payload is a no-op and emits a warning.
persistTunedConfig :: CalibrationCandidate -> IO ()
persistTunedConfig cand = case ccType cand of
  CandidateSalience ->
    case ccSalienceWeights cand of
      Nothing -> warnMissing "salience weights"
      Just w  -> writeJson "resources/config/tuned_salience_weights.json" w
  CandidateField ->
    case ccFieldHeuristics cand of
      Nothing -> warnMissing "field heuristics"
      Just fh -> writeJson "resources/config/tuned_field_heuristics.json" fh
  where
    warnMissing what =
      hPutStrLn stderr $
        "persist_tuned_config: missing " <> what <> " for candidate " <> show (unCalibrationId (ccId cand))
    writeJson path value = do
      createDirectoryIfMissing True (takeDirectory path)
      let tmpPath = path <.> "tmp"
          bakPath = path <.> "bak"
      BL.writeFile tmpPath (encode value)
      existing <- doesFileExist path
      when existing (copyFile path bakPath)
      renameFile tmpPath path
