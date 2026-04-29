{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Quantitative legitimacy scoring over parser confidence, shadow divergence, and load. -}
module QxFx0.Core.Legitimacy.Scoring
  ( legitimacyScore
  , legitimacyRecoveryBonus
  ) where

import QxFx0.Types.Thresholds
  ( legitimacyApiPenalty
  , legitimacyConfidencePenaltyWeight
  , legitimacyHighLoadPenalty
  , legitimacyHighLoadThreshold
  , legitimacyShadowAgreementBonus
  , legitimacyStableRouteBonus
  )
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence
  , computeShadowLegitimacyPenalty
  )

legitimacyScore :: Double -> ShadowDivergence -> Double -> Bool -> Double
legitimacyScore parserConfidence shadowDivergence emaLoad apiHealthy =
  let base = 1.0
      confidencePenalty = max 0.0 (1.0 - parserConfidence) * legitimacyConfidencePenaltyWeight
      shadowPenalty = computeShadowLegitimacyPenalty shadowDivergence
      emaPenalty =
        if emaLoad > legitimacyHighLoadThreshold
          then legitimacyHighLoadPenalty
          else 0.0
      apiPenalty =
        if apiHealthy
          then 0.0
          else legitimacyApiPenalty
   in max 0.0 (min 1.0 (base - confidencePenalty - shadowPenalty - emaPenalty - apiPenalty))

legitimacyRecoveryBonus :: Bool -> Bool -> Double
legitimacyRecoveryBonus shadowMatched stableRoute =
  shadowBonus + stableBonus
  where
    shadowBonus =
      if shadowMatched
        then legitimacyShadowAgreementBonus
        else 0.0
    stableBonus =
      if stableRoute
        then legitimacyStableRouteBonus
        else 0.0
