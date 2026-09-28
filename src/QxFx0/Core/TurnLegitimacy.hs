{-| Facade for turn-level legitimacy plan adaptation and output finalization. -}
module QxFx0.Core.TurnLegitimacy
  ( applyLegitimacyToPlans
  , finalizeOutput
  , finalizeOutputWithTopic
  , finalizeOutputWithTopicReason
  , safeOutputText
  ) where

import QxFx0.Core.TurnLegitimacy.Output
  ( finalizeOutput
  , finalizeOutputWithTopic
  , finalizeOutputWithTopicReason
  , safeOutputText
  )
import QxFx0.Core.TurnLegitimacy.Plans
  ( applyLegitimacyToPlans
  )
