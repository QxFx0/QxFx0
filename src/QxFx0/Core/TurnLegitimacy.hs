{-| Facade for turn-level legitimacy plan adaptation and output finalization. -}
module QxFx0.Core.TurnLegitimacy
  ( applyLegitimacyToPlans
  , finalizeOutput
  , finalizeOutputWithTopic
  , safeOutputText
  ) where

import QxFx0.Core.TurnLegitimacy.Output
  ( finalizeOutput
  , finalizeOutputWithTopic
  , safeOutputText
  )
import QxFx0.Core.TurnLegitimacy.Plans
  ( applyLegitimacyToPlans
  )
