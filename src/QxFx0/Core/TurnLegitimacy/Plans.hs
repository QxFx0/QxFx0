{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Applies legitimacy outcomes to meaning/content plans before render finalization. -}
module QxFx0.Core.TurnLegitimacy.Plans
  ( applyLegitimacyToPlans
  ) where

import QxFx0.Core.Legitimacy
  ( applyLegitimacyPenalty
  , legitimacyStyleOverride
  )
import QxFx0.Core.TurnPlanning (buildRCP)
import QxFx0.Types

applyLegitimacyToPlans :: Double -> CanonicalMoveFamily -> ResponseMeaningPlan -> ResponseContentPlan -> RenderStyle
                      -> (Double, ResponseMeaningPlan, ResponseContentPlan, CanonicalMoveFamily, IllocutionaryForce)
applyLegitimacyToPlans legitimacy family meaningPlan contentPlan renderStyle =
  let (legitimacy', postPenaltyPlan0) = applyLegitimacyPenalty legitimacy meaningPlan
      finalFamily = rmpFamily postPenaltyPlan0
      finalForce = forceForFamily finalFamily
      postPenaltyPlan = postPenaltyPlan0 {rmpFamily = finalFamily, rmpForce = finalForce}
      styleOverride = legitimacyStyleOverride legitimacy'
      baseContentPlan =
        if finalFamily == family
          then contentPlan
          else (buildRCP finalFamily postPenaltyPlan) {rcpStyle = renderStyle}
      finalContentPlan =
        case styleOverride of
          Just style -> baseContentPlan {rcpStyle = style}
          Nothing -> baseContentPlan
   in (legitimacy', postPenaltyPlan, finalContentPlan, finalFamily, finalForce)
