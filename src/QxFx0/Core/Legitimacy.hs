{-| Legitimacy façade exposing scoring, policy hooks, and shadow divergence penalties. -}
module QxFx0.Core.Legitimacy
  ( legitimacyScore
  , applyLegitimacyPenalty
  , legitimacyRecoveryBonus
  , legitimacyStyleOverride
  , styleFromLegitimacy
  , ShadowDivergence(..)
  , emptyShadowDivergence
  , computeShadowLegitimacyPenalty
  ) where

import QxFx0.Core.Legitimacy.Policy
  ( applyLegitimacyPenalty
  , legitimacyStyleOverride
  , styleFromLegitimacy
  )
import QxFx0.Core.Legitimacy.Scoring
  ( legitimacyRecoveryBonus
  , legitimacyScore
  )
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , emptyShadowDivergence
  , computeShadowLegitimacyPenalty
  )
