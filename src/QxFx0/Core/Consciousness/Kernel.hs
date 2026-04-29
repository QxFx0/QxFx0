{-| Kernel-level consciousness facade over initialization and pulse heuristics. -}
module QxFx0.Core.Consciousness.Kernel
  ( qxfx0UnconsciousKernel
  , emptyConsciousState
  , initialConsciousness
  , kernelPulse
  ) where

import QxFx0.Core.Consciousness.Kernel.Init
  ( emptyConsciousState
  , initialConsciousness
  , qxfx0UnconsciousKernel
  )
import QxFx0.Core.Consciousness.Kernel.Pulse (kernelPulse)
