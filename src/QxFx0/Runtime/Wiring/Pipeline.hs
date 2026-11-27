{-| Pipeline interpreter wiring from runtime context to effectful turn requests. -}
module QxFx0.Runtime.Wiring.Pipeline
  ( toPipelineIO
  ) where

import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , mkReplayPipelineIOWith
  )
import QxFx0.Core.PipelineIO.Internal (PipelineIO(..), defaultStateIntegrityPrior)
import QxFx0.Runtime.Mode (RuntimeMode(..))
import QxFx0.Runtime.Wiring.Handlers (handleTurnEffect)
import QxFx0.Runtime.Wiring.Context
  ( RuntimeCaches(..)
  , RuntimeContext(..)
  , modifyConsciousLoop
  , modifyIntuition
  , rcMode
  , updateHistoryStrict
  )
import QxFx0.Runtime.AuthorityParse (parseAuthoritySurfaceIO)
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))

toPipelineIO :: RuntimeContext -> PipelineIO
toPipelineIO ctx =
  case rcReplayTrace ctx of
    Nothing -> live
    Just trace -> mkReplayPipelineIOWith live trace
  where
    live = PipelineIO
      { pioRuntimeMode = case rcMode ctx of
          StrictRuntime -> RuntimeStrict
          DegradedRuntime -> RuntimeDegraded
      , pioShadowPolicy = case rcMode ctx of
          StrictRuntime -> ShadowBlockOnUnavailableOrDivergence
          DegradedRuntime -> ShadowObserve
      , pioLocalRecoveryPolicy = LocalRecoveryEnabled
      , pioInterpreter = handleTurnEffect ctx
      , pioUpdateHistory = updateHistoryStrict
      , pioModifyConsciousLoop = modifyConsciousLoop ctx
      , pioModifyIntuition = modifyIntuition ctx
      , pioStateIntegrityPrior = defaultStateIntegrityPrior
      , pioParseAuthoritySurface = parseAuthoritySurfaceIO (rtcPgf (rcCaches ctx))
      }
