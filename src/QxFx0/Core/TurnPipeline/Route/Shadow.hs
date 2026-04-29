{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}

{-| Route-stage shadow verdict context and policy-based resolution logic. -}
module QxFx0.Core.TurnPipeline.Route.Shadow
  ( ShadowContext(..)
  , ShadowResolution(..)
  , computeShadowContext
  , resolveShadowFamily
  ) where

import QxFx0.Types
import QxFx0.Core.PipelineIO
  ( ShadowPolicy(..)
  , ShadowResult(..)
  )
import QxFx0.Core.Legitimacy (legitimacyScore)
import QxFx0.Core.Semantic.Embedding (EmbeddingQuality(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , ShadowSnapshotId
  , computeShadowLegitimacyPenaltyWithSeverity
  )
import QxFx0.Types.Thresholds
  ( embSimilarityBonusThreshold
  , embSimilarityLegitimacyBonus
  , intuitConfidenceBonusThreshold
  , intuitConfidenceLegitimacyBonus
  )

import Data.Text (Text)
import qualified Data.Text as T

data ShadowContext = ShadowContext
  { scAdjustedBaseLegit :: !Double
  , scShadowStatus :: !ShadowStatus
  , scShadowHasDivergence :: !Bool
  , scShadowDivergenceKind :: !ShadowDivergenceKind
  , scShadowDivergenceSeverity :: !ShadowDivergenceSeverity
  , scShadowSnapshotId :: !ShadowSnapshotId
  , scShadowFamily :: !(Maybe CanonicalMoveFamily)
  , scShadowForce :: !(Maybe IllocutionaryForce)
  , scShadowMessage :: !Text
  }

data ShadowResolution = ShadowResolution
  { srEffectiveFamily :: !CanonicalMoveFamily
  , srGateTriggered :: !Bool
  }

computeShadowContext :: ShadowResult -> InputPropositionFrame -> AtomTrace -> Double -> EmbeddingQuality -> Double -> Bool -> ShadowContext
computeShadowContext shadowResult frame newTrace intuitConfidence embeddingQuality embSimilarity apiHealthy =
  let divergence = srDivergence shadowResult
      shadowStatus = srStatus shadowResult
      mismatchTags = concat
        [ ["family" | sdFamilyMismatch divergence]
        , ["force" | sdForceMismatch divergence]
        , ["clause" | sdClauseMismatch divergence]
        , ["layer" | sdLayerMismatch divergence]
        , ["warranted" | sdWarrantedMismatch divergence]
        ]
      diagnosticTags = srDiagnostics shadowResult
      shadowHasDivergence = shadowStatus == ShadowDiverged || not (null mismatchTags)
      shadowFamily = fst <$> srDatalogVerdict shadowResult
      shadowMessage =
        case (shadowStatus, mismatchTags, diagnosticTags) of
          (ShadowUnavailable, _, []) -> "shadow_unavailable"
          (ShadowUnavailable, _, diags) -> "shadow_unavailable:" <> T.intercalate "|" diags
          (ShadowMatch, [], []) -> "shadow_match"
          (ShadowMatch, [], diags) -> "shadow_match:" <> T.intercalate "|" diags
          (ShadowMatch, mismatches, []) -> "shadow_match_inconsistent:" <> T.intercalate "," mismatches
          (ShadowMatch, mismatches, diags) ->
            "shadow_match_inconsistent:" <> T.intercalate "," mismatches <> "|diag:" <> T.intercalate "|" diags
          (ShadowDiverged, mismatches, []) -> "shadow_diverged:" <> T.intercalate "," mismatches
          (ShadowDiverged, mismatches, diags) ->
            "shadow_diverged:" <> T.intercalate "," mismatches <> "|diag:" <> T.intercalate "|" diags
      severity = classifyShadowDivergenceSeverity shadowStatus shadowFamily divergence diagnosticTags
      baseLegit =
        legitimacyScoreWithPenalty
          (ipfConfidence frame)
          (computeShadowLegitimacyPenaltyWithSeverity severity divergence)
          (atCurrentLoad newTrace)
          apiHealthy
      embBonus =
        if embeddingQuality == EmbeddingQualityModeled && embSimilarity > embSimilarityBonusThreshold
          then embSimilarityLegitimacyBonus
          else 0.0
      intuitBonus =
        if intuitConfidence > intuitConfidenceBonusThreshold
          then intuitConfidenceLegitimacyBonus
          else 0.0
      adjustedBaseLegit = min 1.0 (baseLegit + embBonus + intuitBonus)
  in ShadowContext
      { scAdjustedBaseLegit = adjustedBaseLegit
      , scShadowStatus = shadowStatus
      , scShadowHasDivergence = shadowHasDivergence
      , scShadowDivergenceKind = sdKind divergence
      , scShadowDivergenceSeverity = severity
      , scShadowSnapshotId = srSnapshotId shadowResult
      , scShadowFamily = shadowFamily
      , scShadowForce = snd <$> srDatalogVerdict shadowResult
      , scShadowMessage = shadowMessage
      }

resolveShadowFamily :: ShadowPolicy -> CanonicalMoveFamily -> ShadowContext -> ShadowResolution
resolveShadowFamily policy requestedFamily sc =
  case policy of
    ShadowObserve ->
      ShadowResolution requestedFamily False
    ShadowPreferVerified ->
      if scShadowHasDivergence sc
        then ShadowResolution (maybe requestedFamily id (scShadowFamily sc)) False
        else ShadowResolution requestedFamily False
    ShadowBlockOnUnavailableOrDivergence ->
      case scShadowDivergenceSeverity sc of
        ShadowSeverityUnavailable -> ShadowResolution CMRepair True
        ShadowSeveritySafety -> ShadowResolution (maybe CMRepair id (scShadowFamily sc)) True
        ShadowSeverityContract -> ShadowResolution (maybe CMRepair id (scShadowFamily sc)) True
        ShadowSeverityAdvisory -> ShadowResolution (maybe requestedFamily id (scShadowFamily sc)) False
        ShadowSeverityClean -> ShadowResolution requestedFamily False

legitimacyScoreWithPenalty :: Double -> Double -> Double -> Bool -> Double
legitimacyScoreWithPenalty parserConfidence shadowPenalty emaLoad apiHealthy =
  let fullPenaltyScore = legitimacyScore parserConfidence ShadowDivergence
        { sdKind = ShadowNoDivergence
        , sdFamilyMismatch = False
        , sdForceMismatch = False
        , sdClauseMismatch = False
        , sdLayerMismatch = False
        , sdWarrantedMismatch = False
        } emaLoad apiHealthy
  in max 0.0 (min 1.0 (fullPenaltyScore - shadowPenalty))

classifyShadowDivergenceSeverity :: ShadowStatus -> Maybe CanonicalMoveFamily -> ShadowDivergence -> [Text] -> ShadowDivergenceSeverity
classifyShadowDivergenceSeverity status shadowFamily divergence diagnostics =
  case status of
    ShadowUnavailable -> ShadowSeverityUnavailable
    ShadowMatch
      | not (hasDivergence divergence) -> ShadowSeverityClean
      | advisoryShift -> ShadowSeverityAdvisory
      | safetyShift -> ShadowSeveritySafety
      | otherwise -> ShadowSeverityContract
    ShadowDiverged
      | safetyShift -> ShadowSeveritySafety
      | advisoryShift -> ShadowSeverityAdvisory
      | otherwise -> ShadowSeverityContract
  where
    hasDivergence d =
      or
        [ sdFamilyMismatch d
        , sdForceMismatch d
        , sdClauseMismatch d
        , sdLayerMismatch d
        , sdWarrantedMismatch d
        ]
    safetyShift =
      shadowFamily `elem` map Just [CMRepair, CMContact, CMConfront]
        || any isSafetyDiagnostic diagnostics
    advisoryShift =
      shadowFamily `elem` map Just [CMDeepen, CMClarify, CMDefine, CMDistinguish, CMReflect, CMAnchor, CMGround]
        && any isAdvisoryDiagnostic diagnostics
        && not safetyShift
    isSafetyDiagnostic d =
      any (`T.isPrefixOf` d)
        [ "repair_signal:"
        , "repair_detail:"
        , "contact_signal:"
        , "contact_detail:"
        , "confront_signal:"
        , "agency_loss"
        ]
    isAdvisoryDiagnostic d =
      any (`T.isPrefixOf` d)
        [ "requested_family_shift:"
        , "input_force_mismatch:"
        , "deepen_signal:"
        , "deepen_detail:"
        , "search_detail:"
        , "clarify_signal:"
        , "clarify_detail:"
        , "anchor_signal:"
        , "anchor_detail:"
        ]
