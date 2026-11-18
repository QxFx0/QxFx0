{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : supplier — Deterministic replay 'PipelineIO' (effect snapshot + replay envelope v1).

Replay reads recorded ambient inputs instead of sampling the live world:

  * 'TurnReqApiHealth'  — 'esApiHealthy' from 'trcEffectSnapshot';
  * 'TurnReqCurrentTime' — 'esCurrentTime' from 'trcEffectSnapshot' (v1
    envelope); old traces delegate to the base interpreter;
  * 'TurnReqRequestId'   — 'trcRequestId' (always present).

Every other request delegates to the base interpreter.  The narrow
'mkReplayPipelineIO' keeps the original test-harness base (fail-closed
defaults), so it remains suitable for unit-test replay.  The wide
'mkReplayPipelineIOWith' accepts a live base and is the opt-in session
replay mode used by 'QxFx0.Runtime.Wiring.toPipelineIO' when
'rcReplayTrace' is set.

For further effects (nix, shadow, embedding, GF), grow 'EffectSnapshot'
fields and add 'TurnEffectRequest' cases here.

NOTE: This module contains no 'unsafePerformIO'.  'mkReplayPipelineIO' is
a pure function of the input 'TurnReplayTrace'; replay is stateless and
reads recorded effect snapshots instead of sampling the live world.  The
two mutable cells used by the test harness ('consciousState' and
'intuitionState' in 'QxFx0.Core.PipelineIO.Test') are deliberately not
recreated here: replay does not persist consciousness/intuition evolution
across modify calls, so determinism holds by construction.
-}
module QxFx0.Core.PipelineIO.Replay
  ( mkReplayPipelineIO
  , mkReplayPipelineIOWith
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

-- | Replay the recorded ambient effects on top of a base 'PipelineIO'.
--
-- Only the three non-deterministic inputs recorded by the envelope are
-- overridden; everything else (persistence, nix, shadow, GF, ...) keeps
-- the base interpreter's behaviour.  A 'Nothing' snapshot / missing
-- 'esCurrentTime' delegates to the base, which keeps old traces
-- explicitly not time-replayable instead of silently freezing them.
mkReplayPipelineIOWith :: PipelineIO -> TurnReplayTrace -> PipelineIO
mkReplayPipelineIOWith base trace =
  base { pioInterpreter = replayInterpreter }
  where
    replayInterpreter req =
      case req of
        TurnReqApiHealth ->
          case trcEffectSnapshot trace of
            Just snap -> pure (TurnResApiHealth (esApiHealthy snap))
            Nothing   -> pioInterpreter base req
        TurnReqCurrentTime ->
          case trcEffectSnapshot trace >>= esCurrentTime of
            Just t  -> pure (TurnResCurrentTime t)
            Nothing -> pioInterpreter base req
        TurnReqRequestId ->
          pure (TurnResRequestId (trcRequestId trace))
        _ ->
          pioInterpreter base req

-- | Build a stateless 'PipelineIO' whose interpreter replays the
-- recorded ambient effects from the trace.  Unrecorded requests fall
-- through to 'defaultTestInterpreter' (test-harness defaults).
mkReplayPipelineIO :: TurnReplayTrace -> PipelineIO
mkReplayPipelineIO trace =
  mkReplayPipelineIOWith statelessTestBase trace

statelessTestBase :: PipelineIO
statelessTestBase = PipelineIO
  { pioRuntimeMode = RuntimeDegraded
  , pioShadowPolicy = ShadowObserve
  , pioLocalRecoveryPolicy = LocalRecoveryEnabled
  , pioInterpreter = defaultTestInterpreter
  , pioUpdateHistory = \new hist ->
      let updated = new Seq.<| hist
      in Seq.take 50 updated
  -- Replay is a stateless, test-only harness: consciousness/intuition
  -- evolution is not persisted across modify calls, so there is no MVar
  -- and hence no 'unsafePerformIO' — the determinism fix must not smuggle
  -- impurity back in.  The wide path threads a live base instead.
  , pioModifyConsciousLoop = \f -> snd <$> f initialLoop
  , pioModifyIntuition = \f -> snd <$> f defaultIntuitiveState
  , pioConatusPrior = defaultConatusPrior
  , pioParseAuthoritySurface = pure . parseAuthoritySurfacePattern
  }
