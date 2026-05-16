{-| Pipeline interpreter wiring from runtime context to effectful turn requests. -}
module QxFx0.Runtime.Wiring.Pipeline
  ( toPipelineIO
  ) where

import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  )
import QxFx0.Core.PipelineIO.Internal (PipelineIO(..))
import QxFx0.Runtime.Mode (RuntimeMode(..))
import QxFx0.Runtime.Wiring.Handlers (handleTurnEffect)
import QxFx0.Runtime.Wiring.Context
  ( RuntimeContext(..)
  , rcMode
  , updateHistoryStrict
  )
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))

toPipelineIO :: RuntimeContext -> PipelineIO
toPipelineIO ctx = PipelineIO
  { pioRuntimeMode = case rcMode ctx of
      StrictRuntime -> RuntimeStrict
      DegradedRuntime -> RuntimeDegraded
  , pioShadowPolicy = case rcMode ctx of
      StrictRuntime -> ShadowBlockOnUnavailableOrDivergence
      DegradedRuntime -> ShadowObserve
  , pioLocalRecoveryPolicy = LocalRecoveryEnabled
  , pioInterpreter = handleTurnEffect ctx
  , pioUpdateHistory = updateHistoryStrict
  }
