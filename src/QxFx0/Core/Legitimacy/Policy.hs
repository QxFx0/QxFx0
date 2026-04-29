{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Policy-level plan adjustments driven by legitimacy score bands. -}
module QxFx0.Core.Legitimacy.Policy
  ( applyLegitimacyPenalty
  , legitimacyStyleOverride
  , styleFromLegitimacy
  ) where

import QxFx0.Types
import QxFx0.Types.Thresholds
  ( legitimacyCautionThreshold
  , legitimacyPassThreshold
  , legitimacyRecoveryThreshold
  )

applyLegitimacyPenalty :: Double -> ResponseMeaningPlan -> (Double, ResponseMeaningPlan)
applyLegitimacyPenalty score meaningPlan
  | score >= legitimacyPassThreshold = (score, meaningPlan)
  | score >= legitimacyRecoveryThreshold =
      ( score
      , meaningPlan
          { rmpStance = degradeStance (rmpStance meaningPlan)
          , rmpDepthMode =
              if score < legitimacyCautionThreshold
                then SurfaceDepth
                else rmpDepthMode meaningPlan
          }
      )
  | otherwise =
      (score, meaningPlan {rmpFamily = CMRepair, rmpStance = Honest})

legitimacyStyleOverride :: Double -> Maybe RenderStyle
legitimacyStyleOverride score
  | score >= legitimacyPassThreshold = Nothing
  | score >= legitimacyCautionThreshold = Nothing
  | score >= legitimacyRecoveryThreshold = Just StyleCautious
  | otherwise = Just StyleRecovery

styleFromLegitimacy :: Double -> Maybe RenderStyle
styleFromLegitimacy = legitimacyStyleOverride

degradeStance :: StanceMarker -> StanceMarker
degradeStance Commit = Honest
degradeStance Firm = Observe
degradeStance Honest = Tentative
degradeStance Explore = Tentative
degradeStance stance = stance
