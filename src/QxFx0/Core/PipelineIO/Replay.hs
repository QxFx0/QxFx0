{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : Deterministic replay 'PipelineIO' — narrow fix for legitimacy-score path.

'Narrow fix' means only the 'apiHealthy' effect is replayed from the
trace snapshot ('trcEffectSnapshot').  All other effects fall through to
the default test interpreter (fail-closed defaults), so this module is
suitable for unit-test replay, not production replay of arbitrary turns.

For the wide path (all resolved effects become replay inputs), grow
'EffectSnapshot' fields and add 'TurnEffectRequest' cases here.
-}
module QxFx0.Core.PipelineIO.Replay
  ( mkReplayPipelineIO
  ) where

import QxFx0.Core.ConsciousnessLoop (initialLoop)
import QxFx0.Core.Intuition (defaultIntuitiveState)
import QxFx0.Core.PipelineIO.Internal
  ( PipelineIO(..)
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , defaultConatusPrior
  )
import QxFx0.Core.PipelineIO.Test
  ( defaultTestInterpreter
  )
import QxFx0.Render.Authority (parseAuthoritySurfacePattern)
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))
import QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , EffectSnapshot(..)
  )

import Data.Sequence (Seq)
import qualified Data.Sequence as Seq

-- | Build a 'PipelineIO' whose 'pioInterpreter' reads effect snapshots
-- from 'trcEffectSnapshot' instead of making live calls.
--
-- Current coverage (narrow fix):
--
--   * 'TurnReqApiHealth' — returns the 'esApiHealthy' value captured
--     at prepare time.  Falls back to 'False' when the trace has no
--     snapshot (pre-vX traces).
--
-- All other requests delegate to 'defaultTestInterpreter' (test-harness
-- defaults) so replay of arbitrary turns does not hang or crash.
mkReplayPipelineIO :: TurnReplayTrace -> PipelineIO
mkReplayPipelineIO trace =
  let replayInterpreter req =
        case req of
          TurnReqApiHealth ->
            pure (TurnResApiHealth apiHealthyFromTrace)
          _ ->
            defaultTestInterpreter req

      apiHealthyFromTrace :: Bool
      apiHealthyFromTrace =
        case trcEffectSnapshot trace of
          Just snap -> esApiHealthy snap
          Nothing   -> False  -- pre-vX trace: not apiHealthy-deterministic

  in PipelineIO
      { pioRuntimeMode = RuntimeDegraded
      , pioShadowPolicy = ShadowObserve
      , pioLocalRecoveryPolicy = LocalRecoveryEnabled
      , pioInterpreter = replayInterpreter
      , pioUpdateHistory = \new hist ->
          let updated = new Seq.<| hist
          in Seq.take 50 updated
      -- Replay is a stateless, test-only harness: consciousness/intuition
      -- evolution is not persisted across modify calls, so there is no MVar
      -- and hence no 'unsafePerformIO' — the determinism fix must not smuggle
      -- impurity back in.  The wide path can thread these from the trace if
      -- it ever needs to.
      , pioModifyConsciousLoop = \f -> snd <$> f initialLoop
      , pioModifyIntuition = \f -> snd <$> f defaultIntuitiveState
      , pioConatusPrior = defaultConatusPrior
      , pioParseAuthoritySurface = parseAuthoritySurfacePattern
      }
