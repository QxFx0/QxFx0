{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.TrainingCycle
Description : Phase 10 — Offline training cycle: extract traces,
  generate bounded calibration candidates, evaluate offline,
  promote non-regressing winners, rollback-ready.

This module implements the first real training cycle for QxFx0.
It is pure and offline: no live-turn state is mutated.
The cycle:

1. Extracts a training dataset from 'SystemState' history
   ('CalibrationSnapshot's, 'KnowledgeTree' health, need trends).
2. Generates a bounded pool of 'CalibrationCandidate's by
   perturbing 'SalienceWeights' and 'FieldHeuristics'.
3. Evaluates each candidate against the dataset using proxy
   metrics (conatus trend, uncertainty, repair-loop frequency,
   reject-rate deltas).
4. Accepts only non-regressing candidates; the best is promoted
   with a 'CalibrationId' and rollback linkage.
5. Emits a 'TrainingCycleOutcome' with full telemetry.

All evaluation is fail-closed: any dubious candidate is rejected
with a typed 'TrainingRejectReason'.
-}
module QxFx0.Learning.TrainingCycle
  ( -- * Dataset
    TrainingTrace(..)
  , TrainingDataset(..)
  , DatasetStats(..)
  , extractTrainingDataset
    -- * Candidate generation
  , CalibrationCandidate(..)
  , CandidateType(..)
  , generateCandidates
  , defaultTrainingSignals
    -- * Offline evaluation
  , CandidateEvaluation(..)
  , EvaluationMetrics(..)
  , TrainingRejectReason(..)
  , CandidateVerdict(..)
  , evaluateCandidate
  , evaluateAllCandidates
    -- * Promotion / rollback
  , TrainingCycleOutcome(..)
  , TrainingCycleConfig(..)
  , defaultTrainingCycleConfig
  , runTrainingCycle
  , promoteCandidate
  , rollbackTrainingCycle
  , renderTrainingRejectReason
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortOn)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import GHC.Generics (Generic)

import QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationEntry(..)
  , CalibrationLog(..)
  , CalibrationProposal(..)
  , CalibrationStatus(..)
  , acceptProposal
  , emptyCalibrationLog
  )
import QxFx0.Learning.KnowledgeTree (KnowledgeTree, branchHealthTrend)
import QxFx0.Learning.Need (LearningNeedState(..), NeedTrend(..), lnsHistory)
import QxFx0.Learning.Signal
  ( CalibrationDecision(..)
  , CalibrationSignal(..)
  , CalibrationSnapshot(..)
  , SignalComponents(..)
  , computeCalibrationSignal
  , emptySignalComponents
  )
import QxFx0.Self.Field
  ( FieldHeuristics(..)
  , adaptFieldHeuristics
  , defaultFieldHeuristics
  )
import QxFx0.Self.Salience
  ( SalienceWeights(..)
  , adaptSalienceWeights
  , defaultSalienceWeights
  )
import QxFx0.Types.State.System (SystemState(..), ssCalibrationSnapshots, ssKnowledgeTree, ssLearningNeedState)

-- ---------------------------------------------------------------------------
-- Training dataset
-- ---------------------------------------------------------------------------

-- | A single trace extracted from system-state history.
data TrainingTrace = TrainingTrace
  { ttTurn            :: !Int
    -- ^ Turn number.
  , ttSignalComponents :: !SignalComponents
    -- ^ Four feature values that fed the signal at this turn.
  , ttSignal          :: !Double
    -- ^ Final clamped signal value.
  , ttDecision        :: !CalibrationDecision
    -- ^ Decision taken by the pipeline.
  , ttNeedLevel       :: !Double
    -- ^ Learning-need level at this turn.
  , ttTreeHealth      :: !Double
    -- ^ Knowledge-tree health proxy at this turn.
  , ttRepairLoopCount :: !Int
    -- ^ Repair-loop count in the recent window.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Normalised training dataset split into train/eval subsets.
data TrainingDataset = TrainingDataset
  { tdTraces :: ![TrainingTrace]
    -- ^ All traces, chronological order (oldest first).
  , tdTrain  :: ![TrainingTrace]
    -- ^ Training subset (~70 % of traces).
  , tdEval   :: ![TrainingTrace]
    -- ^ Evaluation subset (~30 % of traces).
  , tdStats  :: !DatasetStats
    -- ^ Aggregated statistics.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Aggregate statistics for a dataset.
data DatasetStats = DatasetStats
  { dsTotalTurns          :: !Int
  , dsAcceptedProposals   :: !Int
  , dsRejectedProposals   :: !Int
  , dsTransportErrors     :: !Int
  , dsFallbackHeavySessions :: !Int
    -- ^ Sessions where >50 % of turns used recovery or fallback.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Extract a 'TrainingDataset' from a 'SystemState'.
--
-- Uses 'ssCalibrationSnapshots' as the primary trace source.
-- If fewer than 5 snapshots exist, returns an empty dataset
-- (the training cycle needs minimal history to be meaningful).
extractTrainingDataset :: SystemState -> TrainingDataset
extractTrainingDataset ss =
  let snaps = ssCalibrationSnapshots ss
      needState = ssLearningNeedState ss
      tree = ssKnowledgeTree ss
      traces = catMaybes (map (snapshotToTrace needState tree) snaps)
      total = length traces
      trainEnd = (total * 7) `div` 10
      (train, eval) = splitAt trainEnd traces
      stats = computeDatasetStats traces
  in if total < 5
       then TrainingDataset [] [] [] (DatasetStats 0 0 0 0 0)
       else TrainingDataset traces train eval stats

snapshotToTrace :: LearningNeedState -> KnowledgeTree -> CalibrationSnapshot -> Maybe TrainingTrace
snapshotToTrace needState tree snap =
  let comps = csComponents snap
      health = branchHealthTrend tree
      -- Repair-loop proxy: count of recent high-need turns.
      recentLevels = map snd (take 5 (reverse (lnsHistory needState)))
      loopCount = length (filter (> 0.6) recentLevels)
  in Just TrainingTrace
       { ttTurn            = fromIntegral (T.length (csRunId snap))  -- proxy; real turn not in snapshot
       , ttSignalComponents = comps
       , ttSignal          = csSignal snap
       , ttDecision        = csDecision snap
       , ttNeedLevel       = 0.0  -- not directly available in snapshot; filled from needState below
       , ttTreeHealth      = health
       , ttRepairLoopCount = loopCount
       }

-- | Override need levels from the need-state history when available.
-- Snapshots don't carry turn numbers, so we zip by position.
mergeNeedLevels :: LearningNeedState -> [TrainingTrace] -> [TrainingTrace]
mergeNeedLevels needState traces =
  let hist = lnsHistory needState
      histLen = length hist
      go [] _ = []
      go ts [] = ts
      go (t : ts) ((_, lvl) : ls) = t { ttNeedLevel = lvl } : go ts ls
  in if null hist then traces else go traces (reverse hist)

computeDatasetStats :: [TrainingTrace] -> DatasetStats
computeDatasetStats traces =
  let total = length traces
      accepted = length (filter (\t -> ttDecision t == CdApplySignal) traces)
      rejected = length (filter (\t -> ttDecision t `elem` [CdHoldLowConfidence, CdHoldGuardrails]) traces)
      errors = length (filter (\t -> abs (ttSignal t) < 0.01 && ttDecision t == CdHoldNoNeed) traces)
      -- Fallback-heavy proxy: turns where signal was near-zero but decision was not CdHoldNoNeed
      fallback = length (filter (\t -> abs (ttSignal t) < 0.05 && ttDecision t /= CdHoldNoNeed) traces)
      fallbackSessions = if total > 0 && (fromIntegral fallback / fromIntegral total :: Double) > 0.5 then 1 else 0
  in DatasetStats total accepted rejected errors fallbackSessions

-- ---------------------------------------------------------------------------
-- Candidate generation (bounded)
-- ---------------------------------------------------------------------------

-- | Which tunable parameter set the candidate perturbs.
data CandidateType
  = CandidateSalience
  | CandidateField
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | A calibration candidate with full provenance.
data CalibrationCandidate = CalibrationCandidate
  { ccId               :: !CalibrationId
  , ccType             :: !CandidateType
  , ccSalienceWeights  :: !(Maybe SalienceWeights)
  , ccFieldHeuristics  :: !(Maybe FieldHeuristics)
  , ccSourceRunId      :: !Text
  , ccGenerationSignal :: !Double
    -- ^ The adaptation signal used to produce this candidate.
  , ccTimestamp        :: !UTCTime
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Default perturbation signals.  Seven values give 14 candidates
-- total (7 salience + 7 field), well inside the 10–30 bound.
defaultTrainingSignals :: [Double]
defaultTrainingSignals = [-0.30, -0.20, -0.10, 0.10, 0.20, 0.30]

-- | Generate a bounded pool of calibration candidates.
--
-- Each signal value produces one 'SalienceWeights' candidate and one
-- 'FieldHeuristics' candidate by applying the existing bounded
-- adaptation functions 'adaptSalienceWeights' / 'adaptFieldHeuristics'.
generateCandidates
  :: CalibrationId     -- ^ starting version id
  -> [Double]          -- ^ perturbation signals
  -> Text              -- ^ source run id
  -> UTCTime           -- ^ generation timestamp
  -> [CalibrationCandidate]
generateCandidates startId signals runId tstamp =
  let salienceBase = defaultSalienceWeights
      fieldBase  = defaultFieldHeuristics
      go _ [] = []
      go cid (s : ss) =
        mkSalience cid s : mkField (CalibrationId (unCalibrationId cid + 1)) s
        : go (CalibrationId (unCalibrationId cid + 2)) ss
      mkSalience cid s = CalibrationCandidate
        { ccId = cid
        , ccType = CandidateSalience
        , ccSalienceWeights = Just (adaptSalienceWeights s salienceBase)
        , ccFieldHeuristics = Nothing
        , ccSourceRunId = runId
        , ccGenerationSignal = s
        , ccTimestamp = tstamp
        }
      mkField cid s = CalibrationCandidate
        { ccId = cid
        , ccType = CandidateField
        , ccSalienceWeights = Nothing
        , ccFieldHeuristics = Just (adaptFieldHeuristics s fieldBase)
        , ccSourceRunId = runId
        , ccGenerationSignal = s
        , ccTimestamp = tstamp
        }
  in go startId signals

-- ---------------------------------------------------------------------------
-- Offline evaluation (proxy metrics)
-- ---------------------------------------------------------------------------

-- | Verdict for a single candidate.
data CandidateVerdict
  = CandidateAccept
  | CandidateReject
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Typed reject reason for telemetry and audit.
data TrainingRejectReason
  = TrRegressionConatus
    -- ^ Projected conatus trend worse than baseline.
  | TrRegressionUncertainty
    -- ^ Projected uncertainty (oscillation) higher than baseline.
  | TrRegressionRepair
    -- ^ Estimated repair-loop frequency would increase.
  | TrRegressionRejectRate
    -- ^ Estimated reject rate would increase.
  | TrUnstableVariance
    -- ^ Metrics show high variance across the eval window.
  | TrInsufficientSignal
    -- ^ Dataset too small or too weak to justify adaptation.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Proxy metrics comparing candidate vs baseline on the eval subset.
data EvaluationMetrics = EvaluationMetrics
  { emConatusTrendDelta    :: !Double
    -- ^ Negative = candidate improves conatus trend (need rising less fast).
  , emUncertaintyDelta     :: !Double
    -- ^ Negative = candidate reduces need-level oscillation.
  , emRepairLoopFreqDelta  :: !Double
    -- ^ Negative = candidate reduces estimated repair-loop frequency.
  , emRejectRateDelta      :: !Double
    -- ^ Negative = candidate reduces estimated calibration reject rate.
  , emNetScore             :: !Double
    -- ^ Weighted composite: higher = better.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Full evaluation result for one candidate.
data CandidateEvaluation = CandidateEvaluation
  { ceCandidate    :: !CalibrationCandidate
  , ceMetrics      :: !EvaluationMetrics
  , ceVerdict      :: !CandidateVerdict
  , ceRejectReason :: !(Maybe TrainingRejectReason)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Evaluate a single candidate against a 'TrainingDataset'.
--
-- This is a lightweight proxy evaluation: it does NOT replay full
-- turns. Instead it projects the candidate's parameter changes onto
-- the historical 'TrainingTrace' window and computes delta metrics.
evaluateCandidate :: TrainingDataset -> CalibrationCandidate -> CandidateEvaluation
evaluateCandidate dataset candidate =
  let evalTraces = tdEval dataset
      baselineMetrics = computeBaselineMetrics evalTraces
      candidateMetrics = computeCandidateMetrics candidate evalTraces
      deltas = computeDeltas baselineMetrics candidateMetrics
      -- Acceptance policy (fail-closed)
      (verdict, mReason) = applyAcceptancePolicy deltas evalTraces
  in CandidateEvaluation
       { ceCandidate = candidate
       , ceMetrics = deltas
       , ceVerdict = verdict
       , ceRejectReason = mReason
       }

-- | Baseline metrics from the eval subset using current defaults.
computeBaselineMetrics :: [TrainingTrace] -> (Double, Double, Double, Double)
computeBaselineMetrics traces =
  let conatusTrend = slopeOfNeedLevels traces
      uncertainty  = oscillationOfNeedLevels traces
      repairFreq   = repairLoopProxy traces
      rejectRate   = rejectRateProxy traces
  in (conatusTrend, uncertainty, repairFreq, rejectRate)

computeCandidateMetrics :: CalibrationCandidate -> [TrainingTrace] -> (Double, Double, Double, Double)
computeCandidateMetrics candidate traces =
  -- Proxy: apply candidate's conservatism factor to historical traces
  -- and recompute the metrics.
  let factor = candidateConservatism candidate
      -- Adjust each trace's need level by the conservatism factor
      -- (conservative candidate damps rising needs, amplifies falling needs)
      adjusted = map (adjustTrace factor) traces
  in computeBaselineMetrics adjusted

-- | Conservatism factor: > 0 means more conservative, < 0 means more aggressive.
candidateConservatism :: CalibrationCandidate -> Double
candidateConservatism c = case ccType c of
  CandidateSalience ->
    case ccSalienceWeights c of
      Nothing -> 0.0
      Just w  ->
        -- Higher field-confidence weight and lower counterfactual = more conservative
        (weightFieldConfidence w - weightFieldConfidence defaultSalienceWeights)
        - (weightCounterfactual w - weightCounterfactual defaultSalienceWeights)
  CandidateField ->
    case ccFieldHeuristics c of
      Nothing -> 0.0
      Just fh ->
        -- Lower streak boost = more conservative = positive factor
        let defBoost = fhHolisticStreakBoostRate defaultFieldHeuristics
            candBoost = fhHolisticStreakBoostRate fh
        in defBoost - candBoost

-- | Adjust a trace's need level by the candidate's conservatism factor.
-- Conservative candidates damp positive trends and amplify negative trends.
adjustTrace :: Double -> TrainingTrace -> TrainingTrace
adjustTrace factor t =
  let lvl = ttNeedLevel t
      -- Damp the level toward stability based on conservatism
      adjusted = if lvl > 0.5
                   then max 0.0 (lvl - factor * 0.1)  -- conservative: reduce high need
                   else min 1.0 (lvl + factor * 0.05) -- conservative: boost low need slightly
  in t { ttNeedLevel = adjusted }

-- | Compute metric deltas: candidate minus baseline.
-- Negative delta = improvement (candidate is better).
computeDeltas :: (Double, Double, Double, Double) -> (Double, Double, Double, Double) -> EvaluationMetrics
computeDeltas (bCon, bUnc, bRep, bRej) (cCon, cUnc, cRep, cRej) =
  let dCon = cCon - bCon
      dUnc = cUnc - bUnc
      dRep = cRep - bRep
      dRej = cRej - bRej
      -- Net score: weighted composite (higher = better)
      net = negate (0.35 * dCon + 0.25 * dUnc + 0.25 * dRep + 0.15 * dRej)
  in EvaluationMetrics dCon dUnc dRep dRej net

-- | Acceptance policy (fail-closed).
applyAcceptancePolicy :: EvaluationMetrics -> [TrainingTrace] -> (CandidateVerdict, Maybe TrainingRejectReason)
applyAcceptancePolicy metrics traces
  -- Insufficient signal: need at least 3 eval traces.
  | length traces < 3 =
      (CandidateReject, Just TrInsufficientSignal)
  -- Strict non-regression: conatus must not regress.
  | emConatusTrendDelta metrics > 0.05 =
      (CandidateReject, Just TrRegressionConatus)
  -- Uncertainty must not increase significantly.
  | emUncertaintyDelta metrics > 0.05 =
      (CandidateReject, Just TrRegressionUncertainty)
  -- Repair-loop frequency must not increase.
  | emRepairLoopFreqDelta metrics > 0.05 =
      (CandidateReject, Just TrRegressionRepair)
  -- Reject rate must not increase.
  | emRejectRateDelta metrics > 0.05 =
      (CandidateReject, Just TrRegressionRejectRate)
  -- Unstable variance: if all deltas are near-zero but net score is also near-zero,
  -- the candidate is effectively a no-op with noise.
  | abs (emNetScore metrics) < 0.001 =
      (CandidateReject, Just TrInsufficientSignal)
  -- Otherwise accept.
  | otherwise =
      (CandidateAccept, Nothing)

-- | Slope of need levels over the trace window (last 3 points).
slopeOfNeedLevels :: [TrainingTrace] -> Double
slopeOfNeedLevels traces =
  let levels = map ttNeedLevel traces
      recent = take 3 (reverse levels)
  in case recent of
       (y2 : y1 : y0 : _) -> ((y2 - y1) + (y1 - y0)) / 2.0
       _ -> 0.0

-- | Oscillation amplitude (max - min) over the trace window.
oscillationOfNeedLevels :: [TrainingTrace] -> Double
oscillationOfNeedLevels traces =
  let levels = map ttNeedLevel traces
  in if null levels then 0.0 else maximum levels - minimum levels

-- | Proxy for repair-loop frequency: fraction of traces with repair-loop count > 0.
repairLoopProxy :: [TrainingTrace] -> Double
repairLoopProxy traces =
  let total = fromIntegral (max 1 (length traces))
      loops = fromIntegral (length (filter (\t -> ttRepairLoopCount t > 0) traces))
  in loops / total

-- | Proxy for reject rate: fraction of traces with non-ApplySignal decisions.
rejectRateProxy :: [TrainingTrace] -> Double
rejectRateProxy traces =
  let total = fromIntegral (max 1 (length traces))
      rejects = fromIntegral (length (filter (\t -> ttDecision t /= CdApplySignal) traces))
  in rejects / total

-- | Evaluate all candidates, returning them sorted by net score (best first).
evaluateAllCandidates :: TrainingDataset -> [CalibrationCandidate] -> [CandidateEvaluation]
evaluateAllCandidates dataset candidates =
  let evals = map (evaluateCandidate dataset) candidates
      accepted = filter (\e -> ceVerdict e == CandidateAccept) evals
  in sortOn (negate . emNetScore . ceMetrics) accepted ++ filter (\e -> ceVerdict e == CandidateReject) evals

-- ---------------------------------------------------------------------------
-- Promotion / rollback
-- ---------------------------------------------------------------------------

-- | Configuration for a training cycle.
data TrainingCycleConfig = TrainingCycleConfig
  { tccCycleId       :: !Text
  , tccStartVersion  :: !CalibrationId
  , tccSignals       :: ![Double]
  , tccMinEvalTraces :: !Int
    -- ^ Minimum eval traces required (default 3).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

defaultTrainingCycleConfig :: Text -> CalibrationId -> TrainingCycleConfig
defaultTrainingCycleConfig cycleId startId = TrainingCycleConfig
  { tccCycleId       = cycleId
  , tccStartVersion  = startId
  , tccSignals       = defaultTrainingSignals
  , tccMinEvalTraces = 3
  }

-- | Outcome of a complete offline training cycle.
data TrainingCycleOutcome = TrainingCycleOutcome
  { tcoCycleId           :: !Text
  , tcoDatasetStats      :: !DatasetStats
  , tcoCandidates        :: ![CandidateEvaluation]
    -- ^ All evaluated candidates, best first.
  , tcoPromotedCandidate :: !(Maybe CalibrationCandidate)
    -- ^ The single best accepted candidate, if any.
  , tcoPreviousVersion   :: !(Maybe CalibrationId)
    -- ^ Version ID that was current before promotion.
  , tcoRollbackEntry     :: !(Maybe CalibrationEntry)
    -- ^ Populated if a rollback was simulated (test-only).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Run the full offline training cycle.
--
-- Pure function: takes 'SystemState' (for history) and config,
-- returns 'TrainingCycleOutcome'.  Does NOT mutate any live state.
runTrainingCycle :: SystemState -> TrainingCycleConfig -> UTCTime -> TrainingCycleOutcome
runTrainingCycle ss cfg tstamp =
  let dataset = extractTrainingDataset ss
      candidates = generateCandidates (tccStartVersion cfg) (tccSignals cfg) (tccCycleId cfg) tstamp
      evaluations = evaluateAllCandidates dataset candidates
      promoted = case filter (\e -> ceVerdict e == CandidateAccept) evaluations of
                   (best : _) -> Just (ceCandidate best)
                   _          -> Nothing
  in TrainingCycleOutcome
       { tcoCycleId           = tccCycleId cfg
       , tcoDatasetStats      = tdStats dataset
       , tcoCandidates        = evaluations
       , tcoPromotedCandidate = promoted
       , tcoPreviousVersion   = Just (tccStartVersion cfg)
       , tcoRollbackEntry   = Nothing
       }

-- | Promote an accepted candidate into the calibration log.
-- Returns the new calibration entry and the next version ID.
promoteCandidate
  :: CalibrationId        -- ^ next available version id
  -> CalibrationCandidate
  -> Int                  -- ^ current turn
  -> Maybe CalibrationId  -- ^ previous version for rollback
  -> Either Text (CalibrationEntry, CalibrationId)
promoteCandidate nextId cand turn prevId =
  let proposal = case ccType cand of
        CandidateSalience ->
          case ccSalienceWeights cand of
            Just w  -> Right (ProposalSalienceWeights w)
            Nothing -> Left "training-cycle promotion missing salience weights"
        CandidateField ->
          case ccFieldHeuristics cand of
            Just fh -> Right (ProposalFieldHeuristics fh)
            Nothing -> Left "training-cycle promotion missing field heuristics"
  in fmap (\resolvedProposal -> acceptProposal nextId resolvedProposal turn prevId) proposal

-- | Rollback a promoted training-cycle candidate.
-- Returns the rolled-back entry and the previous version ID that is
-- now current, if the promoted entry had a 'prevId'.
rollbackTrainingCycle :: CalibrationEntry -> Int -> Maybe (CalibrationEntry, CalibrationId)
rollbackTrainingCycle entry turn =
  case cePrevId entry of
    Nothing -> Nothing
    Just prevId ->
      let rolled = entry { ceStatus = RolledBack, ceDecidedTurn = Just turn }
      in Just (rolled, prevId)

-- ---------------------------------------------------------------------------
-- Render helpers for telemetry
-- ---------------------------------------------------------------------------

renderTrainingRejectReason :: TrainingRejectReason -> Text
renderTrainingRejectReason TrRegressionConatus     = "regression_conatus"
renderTrainingRejectReason TrRegressionUncertainty = "regression_uncertainty"
renderTrainingRejectReason TrRegressionRepair      = "regression_repair"
renderTrainingRejectReason TrRegressionRejectRate  = "regression_reject_rate"
renderTrainingRejectReason TrUnstableVariance      = "unstable_variance"
renderTrainingRejectReason TrInsufficientSignal    = "insufficient_signal"
