{-| Facade for narrative/intuition and tension modulation utilities. -}
module QxFx0.Core.TurnModulation
  ( modulateRMPWithNarrative
  , modulateRCPWithFlash
  , computeTensionDelta
  , narrativeFamilyHint
  , intuitionFamilyHint
  ) where

import QxFx0.Core.TurnModulation.Narrative
  ( intuitionFamilyHint
  , modulateRCPWithFlash
  , modulateRMPWithNarrative
  , narrativeFamilyHint
  )
import QxFx0.Core.TurnModulation.Tension (computeTensionDelta)
