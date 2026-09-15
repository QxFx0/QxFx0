{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{-|
Module      : QxFx0.Observability.TraceAnalysis
Description : Phase 3D: Self-trace consumer activation
Copyright   : (c) 2026 QxFx0 Project
License     : Proprietary
Maintainer  : Bob

Activates consumption of Self-trace fields collected in 'TurnReplayTrace'.
Prior to Phase 3D, these fields were collected but never read — "dead neurons".
This module provides analysis functions that detect anomalies, compute metrics,
and enable observability of the Self layer.

== Design Principles

* Lightweight: < 1ms overhead per turn
* Anomaly-focused: detect deviations, not exhaustive logging
* Composable: each analyzer is independent
* Observable: integrates with existing Metrics/Logging infrastructure

== Trace Field Coverage

This module consumes:

* Recovery: 'trcLocalRecoveryPolicy', 'trcRecoveryCause', 'trcRecoveryStrategy', 'trcRecoveryEvidence'
* Conatus: 'trcConatusEnergy', 'trcConatusGateFired'
* Field: 'trcField' (5 components)
* Essence: 'trcEssenceMode', 'trcEssenceCommitted', 'trcEssenceAngstLevel', 'trcEssenceTrigger'
* Deliberation: 'trcDeliberationRule', 'trcDeliberationAgreement', 'trcDeliberationDivergence'
* Salience: 'trcSalienceDriver', 'trcSalienceHolisticBias', 'trcSalienceConfidence'
* User regime (concept v3): 'trcUserRegime' — crisis protocol verdict,
  user R5 contour, prediction residual.  Activates the previously
  write-only regime traces (audit P1-5, 2026-08-23).
* Self layer (audit P1-1, 2026-08-23): 'trcSelfDivergenceTotal',
  'trcSelfDivergenceWindowMean', 'trcSelfDivergencePredictionActive',
  'trcSelfDivergencePenalty', 'trcEssenceResetEvent' — the A-slice
  divergence group and the B-slice soft-rupture event, previously
  write-only.
-}
module QxFx0.Observability.TraceAnalysis
  ( -- * Analysis types
    RecoveryAnalysis(..)
  , ConatusAnalysis(..)
  , FieldAnalysis(..)
  , EssenceAnalysis(..)
  , DeliberationAnalysis(..)
  , SalienceAnalysis(..)
  , UserRegimeAnalysis(..)
  , SelfLayerAnalysis(..)
  , TraceAnalysisSummary(..)
    -- * Analysis functions
  , analyzeRecoveryPattern
  , analyzeConatusDynamics
  , analyzeFieldState
  , analyzeEssenceCommitment
  , analyzeDeliberation
  , analyzeSalience
  , analyzeUserRegime
  , analyzeSelfLayer
  , analyzeTrace
    -- * Anomaly detection
  , hasRecoveryAnomaly
  , hasConatusAnomaly
  , hasFieldAnomaly
  , hasEssenceAnomaly
  , hasDeliberationAnomaly
  , hasSalienceAnomaly
  , hasUserRegimeAnomaly
  , hasSelfLayerAnomaly
  , hasAnyAnomaly
    -- * Observability integration
  , emitTraceMetrics
  , logTraceAnomalies
  ) where

import Control.Monad (when)
import Data.Aeson (ToJSON(..), FromJSON(..), object, (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.TurnProjection (TurnReplayTrace(..), UserRegimeTrace(..))
import QxFx0.Types.Safety.Crisis (CrisisGuardTrace(..))
import QxFx0.Types.User.R5 (UserR5Trace(..))
import QxFx0.Types.Self.SelfDivergence (defaultSelfDivergenceTuning, sdtThreshold)
import QxFx0.Types.Self.Essence (EssenceResetEvent(..))
import QxFx0.Types.Recovery (LocalRecoveryCause(..), LocalRecoveryStrategy(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ceScalar, lowEnergyThreshold)
import QxFx0.Self.Field
  ( Field(..)
  , Resonance(..)
  , Atmosphere(..)
  , FieldConfidence(..)
  , Consolidation(..)
  , Counterfactual(..)
  )
import QxFx0.Observability.Logging
  ( LogContext
  , emptyContext
  , addContext
  , logWarn
  , logInfo
  )
import QxFx0.Observability.Metrics
  ( MetricRegistry
  , recordGauge
  , recordCounter
  )

-- | Recovery pattern analysis
data RecoveryAnalysis = RecoveryAnalysis
  { raPolicy :: !Text
    -- ^ Recovery policy text
  , raCause :: !(Maybe LocalRecoveryCause)
    -- ^ Recovery cause if triggered
  , raStrategy :: !(Maybe LocalRecoveryStrategy)
    -- ^ Recovery strategy if triggered
  , raEvidenceCount :: !Int
    -- ^ Number of evidence items
  , raTriggered :: !Bool
    -- ^ Whether recovery was triggered
  , raConatusGateTriggered :: !Bool
    -- ^ Whether Conatus gate specifically triggered recovery
  , raAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Conatus dynamics analysis
data ConatusAnalysis = ConatusAnalysis
  { caEnergy :: !ConatusEnergy
    -- ^ Full Conatus energy record
  , caScalar :: !Double
    -- ^ Scalar energy value
  , caGateFired :: !Bool
    -- ^ Whether structural gate fired
  , caEnergyTrend :: !Text
    -- ^ "healthy" | "degraded" | "critical"
  , caAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Field state analysis
data FieldAnalysis = FieldAnalysis
  { faField :: !Field
    -- ^ Full Field record
  , faResonance :: !Double
    -- ^ Resonance component
  , faAtmosphereValence :: !Double
    -- ^ Atmosphere valence
  , faAtmosphereArousal :: !Double
    -- ^ Atmosphere arousal
  , faConfidence :: !Double
    -- ^ Field confidence
  , faConsolidation :: !Double
    -- ^ Consolidation
  , faCounterfactual :: !Double
    -- ^ Counterfactual diversity
  , faBalance :: !Text
    -- ^ "balanced" | "resonance_dominant" | "low_confidence" | "high_counterfactual"
  , faAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Essence commitment analysis
data EssenceAnalysis = EssenceAnalysis
  { eaMode :: !(Maybe Text)
    -- ^ Essence mode: "witnessing" | "contemplative" | "dialogical" | "integrative"
  , eaCommitted :: !(Maybe Bool)
    -- ^ Whether essence is committed
  , eaAngstLevel :: !(Maybe Double)
    -- ^ Angst level [0, 1]
  , eaTrigger :: !(Maybe Text)
    -- ^ Commitment trigger if fired
  , eaAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Deliberation analysis
data DeliberationAnalysis = DeliberationAnalysis
  { daRule :: !(Maybe Text)
    -- ^ Reconciliation rule applied
  , daAgreement :: !(Maybe Text)
    -- ^ Agreement classification
  , daDivergence :: !(Maybe Double)
    -- ^ Divergence score [0, 1]
  , daNarrativeTone :: !(Maybe Text)
    -- ^ Narrative tone
  , daAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Salience analysis
data SalienceAnalysis = SalienceAnalysis
  { saDriver :: !Text
    -- ^ Dominant salience driver
  , saHolisticBias :: !Double
    -- ^ Holistic bias [0, 1]
  , saConfidence :: !Double
    -- ^ Salience confidence [0, 1]
  , saAnomaly :: !(Maybe Text)
    -- ^ Anomaly description if detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Complete trace analysis summary
data TraceAnalysisSummary = TraceAnalysisSummary
  { tasRecovery :: !RecoveryAnalysis
  , tasConatus :: !ConatusAnalysis
  , tasField :: !FieldAnalysis
  , tasEssence :: !EssenceAnalysis
  , tasDeliberation :: !DeliberationAnalysis
  , tasSalience :: !SalienceAnalysis
  , tasUserRegime :: !UserRegimeAnalysis
  , tasSelfLayer :: !SelfLayerAnalysis
  , tasAnomalyCount :: !Int
    -- ^ Total number of anomalies detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Analyze recovery pattern from trace
analyzeRecoveryPattern :: TurnReplayTrace -> RecoveryAnalysis
analyzeRecoveryPattern trace =
  let policy = trcLocalRecoveryPolicy trace
      cause = trcRecoveryCause trace
      strategy = trcRecoveryStrategy trace
      evidence = trcRecoveryEvidence trace
      evidenceCount = length evidence
      triggered = case cause of
        Nothing -> False
        Just _ -> True
      conatusGate = case cause of
        Just RecoveryConatusGate -> True
        _ -> False
      anomaly = detectRecoveryAnomaly policy cause strategy evidenceCount
  in RecoveryAnalysis
       { raPolicy = policy
       , raCause = cause
       , raStrategy = strategy
       , raEvidenceCount = evidenceCount
       , raTriggered = triggered
       , raConatusGateTriggered = conatusGate
       , raAnomaly = anomaly
       }

-- | Detect recovery anomalies
detectRecoveryAnomaly :: Text -> Maybe LocalRecoveryCause -> Maybe LocalRecoveryStrategy -> Int -> Maybe Text
detectRecoveryAnomaly _policy cause strategy evidenceCount
  | Just _ <- cause, Nothing <- strategy =
      Just "recovery_triggered_without_strategy"
  | Just _ <- cause, evidenceCount == 0 =
      Just "recovery_triggered_without_evidence"
  | Nothing <- cause, Just _ <- strategy =
      Just "strategy_without_cause"
  | otherwise = Nothing

-- | Analyze Conatus dynamics from trace
analyzeConatusDynamics :: TurnReplayTrace -> ConatusAnalysis
analyzeConatusDynamics trace =
  let energy = trcConatusEnergy trace
      scalar = ceScalar energy
      gateFired = trcConatusGateFired trace
      trend = classifyEnergyTrend scalar gateFired
      anomaly = detectConatusAnomaly scalar gateFired
  in ConatusAnalysis
       { caEnergy = energy
       , caScalar = scalar
       , caGateFired = gateFired
       , caEnergyTrend = trend
       , caAnomaly = anomaly
       }

-- | Conatus 'ceScalar' lives on a production log-scale codomain
-- (@0.5 * log(1+m) + ...@), not the unit interval encoded by
-- early-hand-coded thresholds (see `QxFx0.Self.Conatus.computeConatusEnergyWith`).
-- The low end is single-sourced from the runtime law
-- ('QxFx0.Self.Conatus.lowEnergyThreshold'), so "degraded" means
-- "below the gate moment", not an arbitrary 0.3.
--
-- The high end has no law constant (energy accumulates without a hard
-- cap as morphology/identity/turns grow).  We therefore flag as
-- "excessive" only values far above the healthy band (~14-15; a
-- blanket with hundreds of claims sits near ~4-5 initial and climbs
-- with substance).  A conservative ceiling of 30.0 keeps genuinely
-- surprising runaways visible without flagging every productive
-- session.
conatusExcessiveCeiling :: Double
conatusExcessiveCeiling = 30.0

-- | Classify energy trend
classifyEnergyTrend :: Double -> Bool -> Text
classifyEnergyTrend scalar gateFired
  | gateFired = "critical"
  | scalar < lowEnergyThreshold = "degraded"
  | otherwise = "healthy"

-- | Detect Conatus anomalies
detectConatusAnomaly :: Double -> Bool -> Maybe Text
detectConatusAnomaly scalar gateFired
  | gateFired && scalar > conatusExcessiveCeiling =
      Just "gate_fired_with_high_energy"
  | scalar < 0.0 =
      Just "negative_conatus_energy"
  | scalar > conatusExcessiveCeiling =
      Just "excessive_conatus_energy"
  | otherwise = Nothing

-- | Analyze Field state from trace
analyzeFieldState :: TurnReplayTrace -> FieldAnalysis
analyzeFieldState trace =
  let field = trcField trace
      resonance = unResonance (fieldResonance field)
      atmosphere = fieldAtmosphere field
      valence = atmosphereValence atmosphere
      arousal = atmosphereArousal atmosphere
      confidence = unFieldConfidence (fieldConfidence field)
      consolidation = unConsolidation (fieldConsolidation field)
      counterfactual = unCounterfactual (fieldCounterfactual field)
      balance = classifyFieldBalance resonance confidence counterfactual
      anomaly = detectFieldAnomaly resonance confidence consolidation counterfactual
  in FieldAnalysis
       { faField = field
       , faResonance = resonance
       , faAtmosphereValence = valence
       , faAtmosphereArousal = arousal
       , faConfidence = confidence
       , faConsolidation = consolidation
       , faCounterfactual = counterfactual
       , faBalance = balance
       , faAnomaly = anomaly
       }

-- | Classify Field balance
classifyFieldBalance :: Double -> Double -> Double -> Text
classifyFieldBalance resonance confidence counterfactual
  | resonance > 0.8 = "resonance_dominant"
  | confidence < 0.3 = "low_confidence"
  | counterfactual > 0.7 = "high_counterfactual"
  | otherwise = "balanced"

-- | Detect Field anomalies
detectFieldAnomaly :: Double -> Double -> Double -> Double -> Maybe Text
detectFieldAnomaly resonance confidence consolidation counterfactual
  | resonance < 0.0 || resonance > 1.0 =
      Just "resonance_out_of_range"
  | confidence < 0.0 || confidence > 1.0 =
      Just "confidence_out_of_range"
  | consolidation < 0.0 || consolidation > 1.0 =
      Just "consolidation_out_of_range"
  | counterfactual < 0.0 || counterfactual > 1.0 =
      Just "counterfactual_out_of_range"
  | otherwise = Nothing

-- | Analyze Essence commitment from trace
analyzeEssenceCommitment :: TurnReplayTrace -> EssenceAnalysis
analyzeEssenceCommitment trace =
  let mode = trcEssenceMode trace
      committed = trcEssenceCommitted trace
      angst = trcEssenceAngstLevel trace
      trigger = trcEssenceTrigger trace
      anomaly = detectEssenceAnomaly mode committed angst trigger
  in EssenceAnalysis
       { eaMode = mode
       , eaCommitted = committed
       , eaAngstLevel = angst
       , eaTrigger = trigger
       , eaAnomaly = anomaly
       }

-- | Detect Essence anomalies
detectEssenceAnomaly :: Maybe Text -> Maybe Bool -> Maybe Double -> Maybe Text -> Maybe Text
detectEssenceAnomaly mode committed angst trigger
  | Just True <- committed, Nothing <- mode =
      Just "committed_without_mode"
  | Just _ <- trigger, Just False <- committed =
      Just "trigger_without_commitment"
  | Just a <- angst, a < 0.0 || a > 1.0 =
      Just "angst_out_of_range"
  | otherwise = Nothing

-- | Analyze deliberation from trace
analyzeDeliberation :: TurnReplayTrace -> DeliberationAnalysis
analyzeDeliberation trace =
  let rule = trcDeliberationRule trace
      agreement = trcDeliberationAgreement trace
      divergence = trcDeliberationDivergence trace
      tone = trcDeliberationNarrativeTone trace
      anomaly = detectDeliberationAnomaly divergence
  in DeliberationAnalysis
       { daRule = rule
       , daAgreement = agreement
       , daDivergence = divergence
       , daNarrativeTone = tone
       , daAnomaly = anomaly
       }

-- | Detect deliberation anomalies
detectDeliberationAnomaly :: Maybe Double -> Maybe Text
detectDeliberationAnomaly divergence
  | Just d <- divergence, d < 0.0 || d > 1.0 =
      Just "divergence_out_of_range"
  | otherwise = Nothing

-- | Analyze salience from trace
analyzeSalience :: TurnReplayTrace -> SalienceAnalysis
analyzeSalience trace =
  let driver = trcSalienceDriver trace
      bias = trcSalienceHolisticBias trace
      confidence = trcSalienceConfidence trace
      anomaly = detectSalienceAnomaly bias confidence
  in SalienceAnalysis
       { saDriver = driver
       , saHolisticBias = bias
       , saConfidence = confidence
       , saAnomaly = anomaly
       }

-- | Detect salience anomalies
detectSalienceAnomaly :: Double -> Double -> Maybe Text
detectSalienceAnomaly bias confidence
  | bias < 0.0 || bias > 1.0 =
      Just "holistic_bias_out_of_range"
  | confidence < 0.0 || confidence > 1.0 =
      Just "salience_confidence_out_of_range"
  | otherwise = Nothing

-- | Concept v3 user-regime analysis (audit P1-5): activates the
-- previously write-only regime trace fields.
data UserRegimeAnalysis = UserRegimeAnalysis
  { uraProtocolB :: !Bool
    -- ^ Protocol B executed this turn.
  , uraCrisisCause :: !(Maybe Text)
    -- ^ 'crisisCauseTag' when Protocol B fired.
  , uraOutsideContour :: !Bool
    -- ^ The user state was classified outside the viability contour.
  , uraPredictionError :: !(Maybe Double)
    -- ^ Residual against the previous turn's transition prediction.
  , uraResidualWindowMean :: !(Maybe Double)
    -- ^ Mean of the bounded residual window; a sustained high value
    --   means the transition model is /persistently/ wrong, not just
    --   noisy on one turn (audit P1-2).
  , uraAnomaly :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Analyze the user-regime trace.  A hard lexical trigger is the
-- guardrail working as designed — not an anomaly.  An
-- /encoder-driven/ contour exit is exactly the decision the
-- operator must be able to see (the contour is hand-set v1), and a
-- large prediction residual means the transition model is wrong.
analyzeUserRegime :: TurnReplayTrace -> UserRegimeAnalysis
analyzeUserRegime trace =
  case trcUserRegime trace of
    Nothing ->
      UserRegimeAnalysis False Nothing False Nothing Nothing Nothing
    Just regime ->
      let crisis = urtCrisis regime
          userR5 = urtUserR5 regime
          anomaly
            | cgtCause crisis == Just "contour_exit" =
                Just "user_contour_exit"
            | Just err <- ur5PredictionError userR5
            , err > userResidualAnomalyThreshold =
                Just "user_model_high_residual"
            | Just m <- ur5WindowMean userR5
            , m > userResidualAnomalyThreshold =
                Just "user_model_sustained_residual"
            | otherwise = Nothing
      in UserRegimeAnalysis
           { uraProtocolB = cgtProtocolB crisis
           , uraCrisisCause = cgtCause crisis
           , uraOutsideContour = ur5OutsideContour userR5
           , uraPredictionError = ur5PredictionError userR5
           , uraResidualWindowMean = ur5WindowMean userR5
           , uraAnomaly = anomaly
           }

-- | Prediction-residual level that flags the transition model as
-- wrong (mean absolute component distance; 0.35 ≈ a third of the
-- axis range).  Hand-set v1.
userResidualAnomalyThreshold :: Double
userResidualAnomalyThreshold = 0.35

hasUserRegimeAnomaly :: UserRegimeAnalysis -> Bool
hasUserRegimeAnomaly analysis = uraAnomaly analysis /= Nothing

-- | Self-layer analysis (audit P1-1): activates the previously
-- write-only A-slice divergence traces and the B-slice soft-rupture
-- event.
data SelfLayerAnalysis = SelfLayerAnalysis
  { slaDivergenceTotal :: !(Maybe Double)
    -- ^ This turn's measured self-divergence (Nothing on the first
    --   turn, before a prediction exists).
  , slaDivergenceWindowMean :: !(Maybe Double)
    -- ^ Mean of the bounded divergence window (Nothing while empty).
  , slaPredictionActive :: !Bool
    -- ^ Whether the divergence was measured against a prediction.
  , slaEssenceResetTurn :: !(Maybe Int)
    -- ^ Turn of the last essence soft rupture, if one occurred.
  , slaAnomaly :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Analyze the self layer.  Three flags, in order of severity:
--
-- * @self_penalty_without_prediction@ — a nonzero divergence
--   penalty with the prediction chain off is a wiring invariant
--   violation (the penalty is gated on prior-turn divergence, which
--   presupposes an active prediction).
-- * @self_divergence_sustained@ — the divergence window mean is
--   strictly above 'sdtThreshold'; this is exactly the predicate
--   behind the @RecoverySelfDivergence@ trigger
--   ('sustainedDivergenceExceeds' with the default tuning), so a
--   sustained flag without a recovery cause on the same trace means
--   the recovery branch did not fire when it should have.
-- * @essence_soft_rupture@ — an 'EssenceResetEvent' was recorded
--   this turn; the rupture itself is the observable, the operator
--   must see it in analysis output, not only in raw JSON.
analyzeSelfLayer :: TurnReplayTrace -> SelfLayerAnalysis
analyzeSelfLayer trace =
  let total = trcSelfDivergenceTotal trace
      windowMean = trcSelfDivergenceWindowMean trace
      predictionActive = trcSelfDivergencePredictionActive trace
      anomaly
        | trcSelfDivergencePenalty trace /= 0.0 && not predictionActive =
            Just "self_penalty_without_prediction"
        | Just m <- windowMean
        , m > sdtThreshold defaultSelfDivergenceTuning =
            Just "self_divergence_sustained"
        | Just _ <- trcEssenceResetEvent trace =
            Just "essence_soft_rupture"
        | otherwise = Nothing
  in SelfLayerAnalysis
       { slaDivergenceTotal = total
       , slaDivergenceWindowMean = windowMean
       , slaPredictionActive = predictionActive
       , slaEssenceResetTurn = ereTurn <$> trcEssenceResetEvent trace
       , slaAnomaly = anomaly
       }

hasSelfLayerAnomaly :: SelfLayerAnalysis -> Bool
hasSelfLayerAnomaly analysis = slaAnomaly analysis /= Nothing

-- | Comprehensive trace analysis
analyzeTrace :: TurnReplayTrace -> TraceAnalysisSummary
analyzeTrace trace =
  let recovery = analyzeRecoveryPattern trace
      conatus = analyzeConatusDynamics trace
      field = analyzeFieldState trace
      essence = analyzeEssenceCommitment trace
      deliberation = analyzeDeliberation trace
      salience = analyzeSalience trace
      userRegime = analyzeUserRegime trace
      selfLayer = analyzeSelfLayer trace
      anomalyCount = countAnomalies recovery conatus field essence deliberation salience userRegime selfLayer
  in TraceAnalysisSummary
       { tasRecovery = recovery
       , tasConatus = conatus
       , tasField = field
       , tasEssence = essence
       , tasDeliberation = deliberation
       , tasSalience = salience
       , tasUserRegime = userRegime
       , tasSelfLayer = selfLayer
       , tasAnomalyCount = anomalyCount
       }

-- | Count total anomalies
countAnomalies :: RecoveryAnalysis -> ConatusAnalysis -> FieldAnalysis -> EssenceAnalysis -> DeliberationAnalysis -> SalienceAnalysis -> UserRegimeAnalysis -> SelfLayerAnalysis -> Int
countAnomalies recovery conatus field essence deliberation salience userRegime selfLayer =
  length $ filter (/= Nothing)
    [ raAnomaly recovery
    , caAnomaly conatus
    , faAnomaly field
    , eaAnomaly essence
    , daAnomaly deliberation
    , saAnomaly salience
    , uraAnomaly userRegime
    , slaAnomaly selfLayer
    ]

-- | Check if recovery has anomaly
hasRecoveryAnomaly :: RecoveryAnalysis -> Bool
hasRecoveryAnomaly = (/= Nothing) . raAnomaly

-- | Check if Conatus has anomaly
hasConatusAnomaly :: ConatusAnalysis -> Bool
hasConatusAnomaly = (/= Nothing) . caAnomaly

-- | Check if Field has anomaly
hasFieldAnomaly :: FieldAnalysis -> Bool
hasFieldAnomaly = (/= Nothing) . faAnomaly

-- | Check if Essence has anomaly
hasEssenceAnomaly :: EssenceAnalysis -> Bool
hasEssenceAnomaly = (/= Nothing) . eaAnomaly

-- | Check if Deliberation has anomaly
hasDeliberationAnomaly :: DeliberationAnalysis -> Bool
hasDeliberationAnomaly = (/= Nothing) . daAnomaly

-- | Check if Salience has anomaly
hasSalienceAnomaly :: SalienceAnalysis -> Bool
hasSalienceAnomaly = (/= Nothing) . saAnomaly

-- | Check if any anomaly exists
hasAnyAnomaly :: TraceAnalysisSummary -> Bool
hasAnyAnomaly summary = tasAnomalyCount summary > 0

-- | Emit trace metrics to registry
emitTraceMetrics :: MetricRegistry -> TurnReplayTrace -> TraceAnalysisSummary -> IO ()
emitTraceMetrics registry trace summary = do
  let tags = Map.fromList [("session_id", trcSessionId trace)]
  
  -- Conatus metrics
  recordGauge registry "conatus_energy" (caScalar $ tasConatus summary) tags
  recordCounter registry "conatus_gate_fired" (if caGateFired (tasConatus summary) then 1 else 0) tags
  
  -- Field metrics
  let fieldAnalysis = tasField summary
  recordGauge registry "field_resonance" (faResonance fieldAnalysis) tags
  recordGauge registry "field_confidence" (faConfidence fieldAnalysis) tags
  recordGauge registry "field_consolidation" (faConsolidation fieldAnalysis) tags
  recordGauge registry "field_counterfactual" (faCounterfactual fieldAnalysis) tags
  
  -- Essence metrics
  case eaAngstLevel (tasEssence summary) of
    Just angst -> recordGauge registry "essence_angst" angst tags
    Nothing -> pure ()
  
  -- Salience metrics
  recordGauge registry "salience_holistic_bias" (saHolisticBias $ tasSalience summary) tags
  recordGauge registry "salience_confidence" (saConfidence $ tasSalience summary) tags

  -- Self-layer metrics (audit P1-1)
  case slaDivergenceWindowMean (tasSelfLayer summary) of
    Just m -> recordGauge registry "self_divergence_window_mean" m tags
    Nothing -> pure ()
  case slaEssenceResetTurn (tasSelfLayer summary) of
    Just turn -> recordCounter registry "essence_soft_rupture" 1
                   (Map.insert "reset_turn" (T.pack (show turn)) tags)
    Nothing -> pure ()

  -- Anomaly metrics
  recordCounter registry "trace_anomalies_total" (fromIntegral $ tasAnomalyCount summary) tags
  recordCounter registry "recovery_triggered" (if raTriggered (tasRecovery summary) then 1 else 0) tags

-- | Log trace anomalies
logTraceAnomalies :: TurnReplayTrace -> TraceAnalysisSummary -> IO ()
logTraceAnomalies trace summary = do
  let baseCtx = addContext "session_id" (trcSessionId trace) $
                addContext "request_id" (trcRequestId trace) emptyContext
  
  -- Log recovery anomalies
  case raAnomaly (tasRecovery summary) of
    Just anomaly -> logWarn ("Recovery anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log Conatus anomalies
  case caAnomaly (tasConatus summary) of
    Just anomaly -> logWarn ("Conatus anomaly: " <> anomaly) $
                    addContext "energy" (T.pack $ show $ caScalar $ tasConatus summary) baseCtx
    Nothing -> pure ()
  
  -- Log Field anomalies
  case faAnomaly (tasField summary) of
    Just anomaly -> logWarn ("Field anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log Essence anomalies
  case eaAnomaly (tasEssence summary) of
    Just anomaly -> logWarn ("Essence anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log Deliberation anomalies
  case daAnomaly (tasDeliberation summary) of
    Just anomaly -> logWarn ("Deliberation anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log user-regime anomalies (concept v3)
  case uraAnomaly (tasUserRegime summary) of
    Just anomaly -> logWarn ("UserRegime anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()

  -- Log self-layer anomalies (A-slice divergence / B-slice rupture)
  case slaAnomaly (tasSelfLayer summary) of
    Just anomaly -> logWarn ("SelfLayer anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()

  -- Log Salience anomalies
  case saAnomaly (tasSalience summary) of
    Just anomaly -> logWarn ("Salience anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log summary if no anomalies
  when (tasAnomalyCount summary == 0) $
    logInfo "Trace analysis: no anomalies detected" baseCtx

