{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Core.Dream.Pressure
  ( deriveDatalogPressure
  , deriveIntuitionPressure
  , reconcileDreamPressures
  , dreamPressureToBias
  , dreamPressureToCandidates
  , evaluateDreamCandidate
  , evaluateDreamCandidateWithClasses
  , applyAcceptedDreamCandidateBias
  , buildDreamOutcome
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.TurnPipeline.Types
import QxFx0.Types
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergenceSeverity(..)
  , shadowDivergenceKindText
  , shadowDivergenceSeverityText
  )
import QxFx0.Types.Thresholds (clamp01)

boolText :: Bool -> Text
boolText True = "true"
boolText False = "false"

deriveDatalogPressure :: TurnPlan -> DatalogPressure
deriveDatalogPressure tp =
  let severity = tpShadowDivergenceSeverity tp
      status = tpShadowStatus tp
      gateBonus = if tpShadowGateTriggered tp then 0.15 else 0.0
      altFamilyBonus =
        case tpShadowFamily tp of
          Just family | family /= tpPreShadowFamily tp -> 0.10
          _ -> 0.0
      legitDeficit = clamp01 (1.0 - tpLegitScore tp)
      pressureClass
        | tpShadowGateTriggered tp = DPGateEscalation
        | status == ShadowUnavailable = DPUnavailableOnly
        | severity == ShadowSeverityUnavailable = DPUnavailableOnly
        | maybe False (/= tpPreShadowFamily tp) (tpShadowFamily tp) = DPAlternativeFamilyPressure
        | severity == ShadowSeveritySafety = DPSafetyPressure
        | severity == ShadowSeverityContract = DPContractPressure
        | severity == ShadowSeverityAdvisory = DPAdvisoryMismatch
        | otherwise = DPNoPressure
      baseStrength =
        case pressureClass of
          DPNoPressure -> 0.0
          DPUnavailableOnly -> 0.10
          DPAdvisoryMismatch -> 0.30
          DPAlternativeFamilyPressure -> 0.45
          DPSafetyPressure -> 0.65
          DPContractPressure -> 0.75
          DPGateEscalation -> 0.85
      strength =
        if pressureClass == DPNoPressure
          then 0.0
          else clamp01 (baseStrength + gateBonus + altFamilyBonus + legitDeficit * 0.35)
      diagnostics = filter (not . T.null)
        [ "shadow_status=" <> shadowStatusText status
        , "shadow_message=" <> tpShadowMessage tp
        , "shadow_kind=" <> shadowDivergenceKindText (tpShadowDivergenceKind tp)
        , "shadow_severity=" <> shadowDivergenceSeverityText severity
        , "gate_triggered=" <> boolText (tpShadowGateTriggered tp)
        , "pre_shadow_family=" <> T.pack (show (tpPreShadowFamily tp))
        , "final_family=" <> T.pack (show (tpFinalFamily tp))
        ]
  in DatalogPressure
      { dpClass = pressureClass
      , dpRequestedFamily = tpPreShadowFamily tp
      , dpShadowFamily = tpShadowFamily tp
      , dpSnapshotId = Just (tpShadowSnapshotId tp)
      , dpStrength = strength
      , dpDiagnostics = diagnostics
      , dpDivergenceKind = tpShadowDivergenceKind tp
      , dpSeverity = severity
      , dpGateTriggered = tpShadowGateTriggered tp
      , dpLegitimacyDeficit = legitDeficit
      , dpShadowStatus = status
      }

deriveIntuitionPressure :: TurnSignals -> IntuitionPressure
deriveIntuitionPressure ts =
  let posterior = clamp01 (tsIntuitPosterior ts)
  in case tsFlash ts of
      Nothing
        | posterior < 0.55 ->
            IntuitionPressure
              { inpClass = IntuitionPressureNone
              , inpStrength = 0.0
              , inpPosterior = posterior
              , inpDirective = Nothing
              , inpTrigger = Nothing
              , inpOverridesAll = False
              , inpReasonTags = []
              }
        | otherwise ->
            IntuitionPressure
              { inpClass = IntuitionPressurePosterior
              , inpStrength = posterior
              , inpPosterior = posterior
              , inpDirective = Nothing
              , inpTrigger = Nothing
              , inpOverridesAll = False
              , inpReasonTags = ["posterior_signal"]
              }
      Just flash ->
        let pressureClass =
              if ifOverridesAll flash
                then IntuitionPressureFlashOverride
                else IntuitionPressureFlash
            strength = clamp01 (max posterior (ifStrength flash))
            reasonTags =
              [ "flash_trigger=" <> T.pack (show (ifTrigger flash))
              , "flash_directive=" <> ifDirective flash
              ]
        in IntuitionPressure
            { inpClass = pressureClass
            , inpStrength = strength
            , inpPosterior = posterior
            , inpDirective = Just (ifDirective flash)
            , inpTrigger = Just (ifTrigger flash)
            , inpOverridesAll = ifOverridesAll flash
            , inpReasonTags = filter (not . T.null) reasonTags
            }

reconcileDreamPressures :: DreamPressureRegime -> DatalogPressure -> IntuitionPressure -> DreamPressure
reconcileDreamPressures regime dlp inp =
  let datalogWeight = dprDatalogWeight regime * dpStrength dlp
      intuitionWeight = dprIntuitionWeight regime * inpStrength inp
      agreement
        | datalogWeight <= 1e-9 && intuitionWeight <= 1e-9 = DreamPressureNone
        | datalogWeight > 1e-9 && intuitionWeight <= 1e-9 = DreamPressureDatalogDominant
        | intuitionWeight > 1e-9 && datalogWeight <= 1e-9 = DreamPressureIntuitionDominant
        | inpOverridesAll inp && dpClass dlp `elem` [DPContractPressure, DPSafetyPressure, DPGateEscalation] = DreamPressureConflict
        | abs (datalogWeight - intuitionWeight) <= 0.15 = DreamPressureConvergent
        | datalogWeight > intuitionWeight = DreamPressureDatalogDominant
        | otherwise = DreamPressureIntuitionDominant
      bonus =
        case agreement of
          DreamPressureConvergent -> dprAgreementBonus regime
          DreamPressureConflict -> negate (dprConflictPenalty regime)
          _ -> 0.0
      strength = min (dprMaxStrength regime) (clamp01 (datalogWeight + intuitionWeight + bonus))
      bias = clampVecNorm (dprMaxBiasNorm regime) (vecAdd (vecScale datalogWeight (biasForDatalogClass (dpClass dlp))) (vecScale intuitionWeight (biasForIntuitionClass (inpClass inp))))
      suggestedFamily =
        case agreement of
          DreamPressureDatalogDominant -> dpShadowFamily dlp
          DreamPressureConvergent -> dpShadowFamily dlp
          _ -> Nothing
      reasonTags = dpDiagnostics dlp ++ inpReasonTags inp ++ [agreementTag agreement]
  in DreamPressure
      { drpAgreement = agreement
      , drpStrength = strength
      , drpBias = bias
      , drpSuggestedFamily = suggestedFamily
      , drpReasonTags = reasonTags
      , drpCandidateThreshold = dprCandidateThreshold regime
      }

dreamPressureToBias :: DreamPressure -> CoreVec
dreamPressureToBias = drpBias

dreamPressureToCandidates :: DreamPressure -> [DreamCorrectionCandidate]
dreamPressureToCandidates pressure
  | drpStrength pressure < drpCandidateThreshold pressure = []
  | otherwise =
      [ DreamCorrectionCandidate
          { dccLabel = candidateLabel pressure
          , dccKind = candidateKind pressure
          , dccStrength = drpStrength pressure
          , dccSuggestedFamily = drpSuggestedFamily pressure
          , dccReasonTags = drpReasonTags pressure
          , dccAdvisoryOnly = True
          }
      ]

evaluateDreamCandidate :: DreamPressure -> DreamCorrectionCandidate -> DreamCandidateDecision
evaluateDreamCandidate = evaluateDreamCandidateWithClasses DPNoPressure IntuitionPressureNone

evaluateDreamCandidateWithClasses :: DatalogPressureClass -> IntuitionPressureClass -> DreamPressure -> DreamCorrectionCandidate -> DreamCandidateDecision
evaluateDreamCandidateWithClasses dClass iClass pressure candidate
  | dccKind candidate == "symbolic" =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRSymbolicCandidateObservedOnly)
  | dccKind candidate == "affective" =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRAffectiveCandidateObservedOnly)
  | dccKind candidate == "conflict" =
      DreamCandidateQuarantined (QuarantinedDreamCandidate envelope DCDRConflictCandidateObservedOnly)
  | dccKind candidate == "none" =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRNoneCandidateObservedOnly)
  | dccKind candidate /= "graph_bias" =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRUnsupportedCandidateKind)
  | dClass == DPNoPressure =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRNoPressure)
  | dClass == DPUnavailableOnly =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRUnavailableOnly)
  | drpAgreement pressure == DreamPressureConflict =
      DreamCandidateQuarantined (QuarantinedDreamCandidate envelope DCDRConflictAgreement)
  | dClass == DPAlternativeFamilyPressure =
      DreamCandidateQuarantined (QuarantinedDreamCandidate envelope DCDRAlternativeFamilyPressure)
  | dClass == DPAdvisoryMismatch =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRAdvisoryMismatchOnly)
  | not thresholdFired =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRThresholdNotReached)
  | drpAgreement pressure == DreamPressureIntuitionDominant =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRAffectiveOnlyAgreement)
  | drpAgreement pressure == DreamPressureDatalogDominant =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRSymbolicOnlyAgreement)
  | drpAgreement pressure == DreamPressureConvergent =
      DreamCandidateAccepted (AcceptedDreamCandidate envelope (acceptedGraphBiasReason dClass))
  | otherwise =
      DreamCandidateRejected (RejectedDreamCandidate envelope DCDRThresholdNotReached)
  where
    thresholdFired = isThresholdFired pressure candidate
    envelope =
      DreamCandidateEnvelope
        { dceCandidate = candidate
        , dceDatalogClass = dClass
        , dceIntuitionClass = iClass
        , dceAgreement = drpAgreement pressure
        , dceUnifiedStrength = drpStrength pressure
        , dceThresholdFired = thresholdFired
        , dceBias = drpBias pressure
        }

applyAcceptedDreamCandidateBias :: AcceptedDreamCandidate -> CoreVec
applyAcceptedDreamCandidateBias accepted =
  case dccKind (dceCandidate (adcEnvelope accepted)) of
    "graph_bias" -> vecScale (min 0.25 (dccStrength (dceCandidate (adcEnvelope accepted)) * 0.25)) (dceBias (adcEnvelope accepted))
    _ -> zeroVec

isThresholdFired :: DreamPressure -> DreamCorrectionCandidate -> Bool
isThresholdFired pressure candidate = dccStrength candidate >= drpCandidateThreshold pressure

isStrongSymbolicPressure :: DatalogPressureClass -> Bool
isStrongSymbolicPressure pressureClass =
  pressureClass `elem` [DPSafetyPressure, DPContractPressure, DPGateEscalation]

acceptedGraphBiasReason :: DatalogPressureClass -> DreamCandidateDecisionReason
acceptedGraphBiasReason pressureClass =
  case pressureClass of
    DPSafetyPressure -> DCDRAcceptedSafetyGraphBias
    DPContractPressure -> DCDRAcceptedContractGraphBias
    DPGateEscalation -> DCDRAcceptedGateEscalationGraphBias
    _ -> DCDRUnsupportedCandidateKind

buildDreamOutcome :: DreamPressureRegime -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> DreamOutcome
buildDreamOutcome regime ti ts tp ta =
  let datalogPressure = deriveDatalogPressure tp
      intuitionPressure = deriveIntuitionPressure ts
      dreamPressure = reconcileDreamPressures regime datalogPressure intuitionPressure
      topicStem =
        if T.null (tiBestTopic ti)
          then T.pack (show (tdFamily (taDecision ta)))
          else tiBestTopic ti
      candidates = map (prefixCandidate topicStem) (dreamPressureToCandidates dreamPressure)
      decisions = map (evaluateDreamCandidateWithClasses (dpClass datalogPressure) (inpClass intuitionPressure) dreamPressure) candidates
      appliedBias = foldl vecAdd zeroVec [ applyAcceptedDreamCandidateBias accepted | DreamCandidateAccepted accepted <- decisions ]
  in DreamOutcome
      { doDatalogPressure = datalogPressure
      , doIntuitionPressure = intuitionPressure
      , doDreamPressure = dreamPressure
      , doBias = dreamPressureToBias dreamPressure
      , doCorrectionCandidates = candidates
      , doCandidateDecisions = decisions
      , doAppliedBias = appliedBias
      }

biasForDatalogClass :: DatalogPressureClass -> CoreVec
biasForDatalogClass pressureClass = case pressureClass of
  DPNoPressure -> zeroVec
  DPUnavailableOnly -> zeroVec
  DPAdvisoryMismatch -> CoreVec 0.01 0.00 0.02 0.02 0.01
  DPAlternativeFamilyPressure -> CoreVec 0.02 0.01 0.03 0.03 0.02
  DPSafetyPressure -> CoreVec 0.02 0.03 0.03 0.02 0.00
  DPContractPressure -> CoreVec 0.01 0.02 0.03 0.03 0.01
  DPGateEscalation -> CoreVec 0.02 0.03 0.04 0.03 0.01

biasForIntuitionClass :: IntuitionPressureClass -> CoreVec
biasForIntuitionClass pressureClass = case pressureClass of
  IntuitionPressureNone -> zeroVec
  IntuitionPressurePosterior -> CoreVec 0.02 0.00 0.01 0.02 0.02
  IntuitionPressureFlash -> CoreVec 0.02 0.01 0.02 0.03 0.03
  IntuitionPressureFlashOverride -> CoreVec 0.02 0.02 0.02 0.04 0.03

agreementTag :: DreamPressureAgreement -> Text
agreementTag agreement = case agreement of
  DreamPressureNone -> "pressure=none"
  DreamPressureConvergent -> "pressure=convergent"
  DreamPressureDatalogDominant -> "pressure=datalog_dominant"
  DreamPressureIntuitionDominant -> "pressure=intuition_dominant"
  DreamPressureConflict -> "pressure=conflict"

candidateLabel :: DreamPressure -> Text
candidateLabel pressure =
  case drpAgreement pressure of
    DreamPressureConvergent -> "dream_pressure_reconcile"
    DreamPressureDatalogDominant -> maybe "dream_pressure_datalog" familyLabel (drpSuggestedFamily pressure)
    DreamPressureIntuitionDominant -> "dream_pressure_intuition"
    DreamPressureConflict -> "dream_pressure_review"
    DreamPressureNone -> "dream_pressure_none"
  where
    familyLabel family = "dream_pressure_family:" <> T.pack (show family)

candidateKind :: DreamPressure -> Text
candidateKind pressure =
  case drpAgreement pressure of
    DreamPressureNone -> "none"
    DreamPressureConvergent -> "graph_bias"
    DreamPressureDatalogDominant -> "symbolic"
    DreamPressureIntuitionDominant -> "affective"
    DreamPressureConflict -> "conflict"

prefixCandidate :: Text -> DreamCorrectionCandidate -> DreamCorrectionCandidate
prefixCandidate stem candidate =
  candidate { dccLabel = stem <> ":" <> dccLabel candidate }
