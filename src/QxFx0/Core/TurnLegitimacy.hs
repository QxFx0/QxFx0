{-| Facade for turn-level legitimacy plan adaptation and output finalization. -}
module QxFx0.Core.TurnLegitimacy
  ( applyLegitimacyToPlans
  , finalizeOutput
  , safeOutputText
  ) where

import QxFx0.Core.TurnLegitimacy.Output
  ( finalizeOutput
  , safeOutputText
  )
import QxFx0.Core.TurnLegitimacy.Plans
  ( applyLegitimacyToPlans
  )
