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
-}
module QxFx0.Observability.TraceAnalysis
  ( -- * Analysis types
    RecoveryAnalysis(..)
  , ConatusAnalysis(..)
  , FieldAnalysis(..)
  , EssenceAnalysis(..)
  , DeliberationAnalysis(..)
  , SalienceAnalysis(..)
  , TraceAnalysisSummary(..)
    -- * Analysis functions
  , analyzeRecoveryPattern
  , analyzeConatusDynamics
  , analyzeFieldState
  , analyzeEssenceCommitment
  , analyzeDeliberation
  , analyzeSalience
  , analyzeTrace
    -- * Anomaly detection
  , hasRecoveryAnomaly
  , hasConatusAnomaly
  , hasFieldAnomaly
  , hasEssenceAnomaly
  , hasDeliberationAnomaly
  , hasSalienceAnomaly
  , hasAnyAnomaly
    -- * Observability integration
  , emitTraceMetrics
  , logTraceAnomalies
  ) where

import Control.Monad (when)
import Data.Aeson (ToJSON(..), object, (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.TurnProjection (TurnReplayTrace(..))
import QxFx0.Types.Recovery (LocalRecoveryCause(..), LocalRecoveryStrategy(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ceScalar)
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
    deriving anyclass (ToJSON)

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
    deriving anyclass (ToJSON)

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
    deriving anyclass (ToJSON)

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
    deriving anyclass (ToJSON)

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
    deriving anyclass (ToJSON)

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
    deriving anyclass (ToJSON)

-- | Complete trace analysis summary
data TraceAnalysisSummary = TraceAnalysisSummary
  { tasRecovery :: !RecoveryAnalysis
  , tasConatus :: !ConatusAnalysis
  , tasField :: !FieldAnalysis
  , tasEssence :: !EssenceAnalysis
  , tasDeliberation :: !DeliberationAnalysis
  , tasSalience :: !SalienceAnalysis
  , tasAnomalyCount :: !Int
    -- ^ Total number of anomalies detected
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON)

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

-- | Classify energy trend
classifyEnergyTrend :: Double -> Bool -> Text
classifyEnergyTrend scalar gateFired
  | gateFired = "critical"
  | scalar < 0.3 = "degraded"
  | otherwise = "healthy"

-- | Detect Conatus anomalies
detectConatusAnomaly :: Double -> Bool -> Maybe Text
detectConatusAnomaly scalar gateFired
  | gateFired && scalar > 0.5 =
      Just "gate_fired_with_high_energy"
  | scalar < 0.0 =
      Just "negative_conatus_energy"
  | scalar > 10.0 =
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

-- | Comprehensive trace analysis
analyzeTrace :: TurnReplayTrace -> TraceAnalysisSummary
analyzeTrace trace =
  let recovery = analyzeRecoveryPattern trace
      conatus = analyzeConatusDynamics trace
      field = analyzeFieldState trace
      essence = analyzeEssenceCommitment trace
      deliberation = analyzeDeliberation trace
      salience = analyzeSalience trace
      anomalyCount = countAnomalies recovery conatus field essence deliberation salience
  in TraceAnalysisSummary
       { tasRecovery = recovery
       , tasConatus = conatus
       , tasField = field
       , tasEssence = essence
       , tasDeliberation = deliberation
       , tasSalience = salience
       , tasAnomalyCount = anomalyCount
       }

-- | Count total anomalies
countAnomalies :: RecoveryAnalysis -> ConatusAnalysis -> FieldAnalysis -> EssenceAnalysis -> DeliberationAnalysis -> SalienceAnalysis -> Int
countAnomalies recovery conatus field essence deliberation salience =
  length $ filter (/= Nothing)
    [ raAnomaly recovery
    , caAnomaly conatus
    , faAnomaly field
    , eaAnomaly essence
    , daAnomaly deliberation
    , saAnomaly salience
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
  
  -- Log Salience anomalies
  case saAnomaly (tasSalience summary) of
    Just anomaly -> logWarn ("Salience anomaly: " <> anomaly) baseCtx
    Nothing -> pure ()
  
  -- Log summary if no anomalies
  when (tasAnomalyCount summary == 0) $
    logInfo "Trace analysis: no anomalies detected" baseCtx

