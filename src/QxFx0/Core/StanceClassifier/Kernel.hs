{-| Kernel-level consciousness facade over initialization and pulse heuristics. -}
module QxFx0.Core.StanceClassifier.Kernel
  ( qxfx0UnconsciousKernel
  , emptyConsciousState
  , initialConsciousness
  , kernelPulse
  ) where

import QxFx0.Core.StanceClassifier.Kernel.Init
  ( emptyConsciousState
  , initialConsciousness
  , qxfx0UnconsciousKernel
  )
import QxFx0.Core.StanceClassifier.Kernel.Pulse (kernelPulse)
