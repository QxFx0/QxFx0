{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.ReplayEnvelope
Description : Replay envelope v1 — recording, JSON compatibility, and a
              recorded-session replay through the production runtime.

The replay claim is narrow and explicit: the recorded ambient inputs
(turn time, request id, apiHealthy) plus the recorded raw input text are
sufficient to reproduce the surface and the full 'TurnReplayTrace' when
the same binary and resources are used.  Every other effect is
re-executed, not replayed (see
@docs/closure/REPLAY_ENVELOPE_V1_PREREG_2026-11-17.md@).
-}
module Test.Suite.ReplayEnvelope
  ( replayEnvelopeTests
  ) where

import Control.Monad (foldM, forM_)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Time.Calendar (Day(ModifiedJulianDay))
import Data.Time.Clock (UTCTime(..), addUTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import System.Environment (lookupEnv)
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Core.PipelineIO
  ( mkReplayPipelineIO
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Types.TurnProjection
  ( EffectSnapshot(..)
  , ReplayEnvelope(..)
  , TurnReplayTrace(..)
  , currentReplayEnvelopeVersion
  , decodePersistedReplayTrace
  )
import qualified Test.Support.Runtime as Runtime
import Test.Support (withRuntimeEnv)
import Test.Suite.M6FeltBenchmark (benchmarkSessionInputs)
import Test.Suite.ReplayDeterminism (minimalReplayTraceWith)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | Three turns that exercise the covered-definition path and a challenge
-- (the challenge turn registers a commitment contradiction in the M6
-- benchmark, so the replay covers a non-trivial finalize path too).
replayInputs :: [Text]
replayInputs =
  [ "что такое свобода?"
  , "свобода это просто отсутствие ограничений"
  , "что такое истина?"
  ]

-- | Deterministic per-turn wall clock: distinct times prove the envelope
-- wins over the replay context's own (deliberately wrong) time source.
replayTimes :: [UTCTime]
replayTimes =
  [ posixSecondsToUTCTime 1800000000
  , posixSecondsToUTCTime 1800000060
  , posixSecondsToUTCTime 1800000120
  ]

-- | The default test interpreter's fixed clock ('fixedTestTime' in
-- 'QxFx0.Core.PipelineIO.Test'): @UTCTime (ModifiedJulianDay 0) 0@.
fixedTestTime :: UTCTime
fixedTestTime = UTCTime (ModifiedJulianDay 0) 0

data RecordedTurn = RecordedTurn
  { rtInput  :: !Text
  , rtOutput :: !Text
  , rtTrace  :: !TurnReplayTrace
  }

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

replayEnvelopeTests :: [Test]
replayEnvelopeTests =
  [ TestLabel "EffectSnapshot: old JSON decodes with esCurrentTime = Nothing" $
      TestCase testSnapshotBackwardCompatible
  , TestLabel "EffectSnapshot: v1 JSON round-trips the captured time" $
      TestCase testSnapshotTimeRoundTrip
  , TestLabel "ReplayEnvelope: JSON round-trip and version" $
      TestCase testEnvelopeRoundTrip
  , TestLabel "replay overlay: recorded time, request id and apiHealthy win" $
      TestCase testOverlayReplaysRecordedValues
  , TestLabel "replay overlay: pre-v1 trace delegates to the base interpreter" $
      TestCase testOverlayDelegatesWhenUnrecorded
  , TestLabel "recorded session: surface and full trace reproduce under replay" $
      TestCase testRecordedSessionReplay
  , TestLabel "12-turn recorded session (opt-in: QXFX0_REPLAY_12_TURN=1)" $
      TestCase testTwelveTurnReplay
  ]

testSnapshotBackwardCompatible :: IO ()
testSnapshotBackwardCompatible =
  case Aeson.decode "{\"esApiHealthy\":true}" :: Maybe EffectSnapshot of
    Nothing -> assertFailure "old EffectSnapshot JSON must decode"
    Just snap -> do
      assertBool "esApiHealthy" (esApiHealthy snap)
      assertEqual "pre-v1 snapshot is not time-replayable" Nothing (esCurrentTime snap)

testSnapshotTimeRoundTrip :: IO ()
testSnapshotTimeRoundTrip = do
  let t = posixSecondsToUTCTime 1800000000
      snap = EffectSnapshot True (Just t)
  assertEqual "EffectSnapshot JSON round-trip"
    (Just snap) (Aeson.decode (Aeson.encode snap))

testEnvelopeRoundTrip :: IO ()
testEnvelopeRoundTrip = do
  let env = ReplayEnvelope currentReplayEnvelopeVersion "что такое свобода?"
  assertEqual "ReplayEnvelope JSON round-trip" (Just env) (Aeson.decode (Aeson.encode env))
  assertEqual "v1 envelope version" 1 currentReplayEnvelopeVersion

-- | The overlay must read the recorded values, not the base interpreter.
-- The base returns @False@ for apiHealthy, @fixedTestTime@ for the clock and
-- @\"request-id-test\"@ for the request id, so every assertion below fails on
-- a dropped overlay branch.
testOverlayReplaysRecordedValues :: IO ()
testOverlayReplaysRecordedValues = do
  let t = posixSecondsToUTCTime 1800000000
      trace = minimalReplayTraceWith True (Just t) "recorded-request-id"
      pio = mkReplayPipelineIO trace
  timeResult <- resolveTurnEffect pio TurnReqCurrentTime
  case timeResult of
    TurnResCurrentTime got -> assertEqual "recorded time wins" t got
    _ -> assertFailure "unexpected current-time result"
  idResult <- resolveTurnEffect pio TurnReqRequestId
  case idResult of
    TurnResRequestId rid ->
      assertEqual "recorded request id wins" "recorded-request-id" rid
    _ -> assertFailure "unexpected request-id result"
  healthResult <- resolveTurnEffect pio TurnReqApiHealth
  case healthResult of
    TurnResApiHealth h ->
      assertBool "recorded apiHealthy (True) wins over base (False)" h
    _ -> assertFailure "unexpected api-health result"

-- | Old traces are explicitly not time-replayable: a missing
-- @esCurrentTime@ and a missing snapshot both delegate to the base
-- interpreter instead of silently freezing a value.
testOverlayDelegatesWhenUnrecorded :: IO ()
testOverlayDelegatesWhenUnrecorded = do
  let preV1 = minimalReplayTraceWith True Nothing "recorded-request-id"
      bare = preV1 { trcEffectSnapshot = Nothing }
  timeResult <- resolveTurnEffect (mkReplayPipelineIO preV1) TurnReqCurrentTime
  case timeResult of
    TurnResCurrentTime got ->
      assertEqual "pre-v1 trace delegates the clock to the base" fixedTestTime got
    _ -> assertFailure "unexpected current-time result"
  healthResult <- resolveTurnEffect (mkReplayPipelineIO bare) TurnReqApiHealth
  case healthResult of
    TurnResApiHealth h ->
      assertBool "no snapshot delegates apiHealthy to the base (False)" (not h)
    _ -> assertFailure "unexpected api-health result"

testRecordedSessionReplay :: IO ()
testRecordedSessionReplay =
  withRuntimeEnv "qxfx0_test_replay_envelope.db" $ do
    let sid = "replay-envelope-session"
    recorded <- recordSession sid replayTimes replayInputs
    assertEqual "three turns recorded" 3 (length recorded)
    forM_ recorded $ \r -> do
      case trcReplayEnvelope (rtTrace r) of
        Nothing -> assertFailure "live turn must record a replay envelope"
        Just env -> do
          assertEqual "envelope version" currentReplayEnvelopeVersion (reEnvelopeVersion env)
          assertEqual "envelope carries the exact raw input" (rtInput r) (reInputText env)
      case trcEffectSnapshot (rtTrace r) of
        Nothing -> assertFailure "live turn must record an effect snapshot"
        Just snap -> assertBool "v1 snapshot carries the captured time" (esCurrentTime snap /= Nothing)

    -- Replay the recorded session in a fresh DB.  The replay context's own
    -- clock is deliberately wrong; a working overlay must still use the
    -- recorded time (and request id) from the trace.
    withRuntimeEnv "qxfx0_test_replay_envelope_replay.db" $ do
      replayed <- replaySession sid recorded
      assertEqual "three turns replayed" 3 (length replayed)
      forM_ (zip recorded replayed) $ \(r, (out, trace)) -> do
        assertEqual ("surface must reproduce for: " <> T.unpack (rtInput r))
          (rtOutput r) out
        assertTraceEqual ("full replay trace must reproduce for: " <> T.unpack (rtInput r))
          (rtTrace r) trace

-- ---------------------------------------------------------------------------
-- Session drivers
-- ---------------------------------------------------------------------------

-- | Compare two full traces without dumping both (a trace is ~1.7 MB of
-- JSON).  On a mismatch the failure names the differing JSON keys, which
-- is what a replay investigation needs first.
assertTraceEqual :: String -> TurnReplayTrace -> TurnReplayTrace -> IO ()
assertTraceEqual label expected actual
  | expected == actual = pure ()
  | otherwise =
      assertFailure (label <> ": differing trace fields: "
        <> show (differingFields expected actual))

differingFields :: TurnReplayTrace -> TurnReplayTrace -> [String]
differingFields expected actual =
  case (Aeson.toJSON expected, Aeson.toJSON actual) of
    (Aeson.Object a, Aeson.Object b) ->
      [ Key.toString k
      | k <- KeyMap.keys (KeyMap.union a b)
      , KeyMap.lookup k a /= KeyMap.lookup k b
      ]
    _ -> ["<trace is not a JSON object>"]

-- | P4 eval leg: the same mechanism on the 12-turn M6 benchmark session.
-- Opt-in because it doubles the session cost (24 turns); the bounded CI
-- leg is the 3-turn test above.
testTwelveTurnReplay :: IO ()
testTwelveTurnReplay = do
  enabled <- lookupEnv "QXFX0_REPLAY_12_TURN"
  case enabled of
    Just "1" ->
      withRuntimeEnv "qxfx0_test_replay_envelope_12.db" $ do
        let sid = "replay-envelope-12-session"
            times =
              [ posixSecondsToUTCTime (1800000000 + 60 * fromIntegral i)
              | i <- [0 .. length benchmarkSessionInputs - 1]
              ]
        recorded <- recordSession sid times benchmarkSessionInputs
        assertEqual "twelve turns recorded" 12 (length recorded)
        withRuntimeEnv "qxfx0_test_replay_envelope_12_replay.db" $ do
          replayed <- replaySession sid recorded
          assertEqual "twelve turns replayed" 12 (length replayed)
          forM_ (zip recorded replayed) $ \(r, (out, trace)) -> do
            assertEqual ("surface must reproduce for: " <> T.unpack (rtInput r))
              (rtOutput r) out
            assertTraceEqual ("full replay trace must reproduce for: " <> T.unpack (rtInput r))
              (rtTrace r) trace
    _ -> pure ()

recordSession :: Text -> [UTCTime] -> [Text] -> IO [RecordedTurn]
recordSession sid times inputs = do
  session0 <- Runtime.bootstrapSession True sid
  (_, acc) <- foldM step (session0, []) (zip times inputs)
  pure acc
  where
    step (session, acc) (t, input) = do
      let session' = session
            { Runtime.sessRuntime =
                Runtime.withRuntimeTimeSource (pure t) (Runtime.sessRuntime session)
            }
      (session'', output) <- Runtime.runTurnInSession session' input
      trace <- loadLatestTrace (Runtime.sessRuntime session'') sid
      pure (session'', acc ++ [RecordedTurn input output trace])

replaySession :: Text -> [RecordedTurn] -> IO [(Text, TurnReplayTrace)]
replaySession sid recorded = do
  session0 <- Runtime.bootstrapSession True sid
  (_, acc) <- foldM step (session0, []) recorded
  pure acc
  where
    step (session, acc) r = do
      env <- case trcReplayEnvelope (rtTrace r) of
        Nothing -> do
          assertFailure "recorded turn has no replay envelope"
          pure (ReplayEnvelope 0 "")
        Just value -> pure value
      let wrongTime = addUTCTime (-100000) (posixSecondsToUTCTime 0)
          session' = session
            { Runtime.sessRuntime =
                Runtime.withRuntimeReplayTrace (Just (rtTrace r))
                  (Runtime.withRuntimeTimeSource (pure wrongTime) (Runtime.sessRuntime session))
            }
      (session'', output) <- Runtime.runTurnInSession session' (reInputText env)
      trace <- loadLatestTrace (Runtime.sessRuntime session'') sid
      pure (session'', acc ++ [(output, trace)])

-- | Read the most recent persisted trace for a session through the runtime's
-- own DB pool (the same read path a replay consumer uses).
loadLatestTrace :: Runtime.RuntimeContext -> Text -> IO TurnReplayTrace
loadLatestTrace ctx sessionId =
  Runtime.withRuntimeDb ctx $ \db -> do
    mStmt <- NSQL.prepare db
      "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
    stmt <- case mStmt of
      Left err -> assertFailure ("cannot prepare replay trace query: " <> T.unpack err)
      Right value -> pure value
    _ <- NSQL.bindText stmt 1 sessionId
    hasRow <- NSQL.stepRow stmt
    raw <- if hasRow then NSQL.columnTextLenient stmt 0 else pure ""
    NSQL.finalize stmt
    case decodePersistedReplayTrace (TE.encodeUtf8 raw) of
      Left err -> assertFailure ("persisted replay trace failed to decode: " <> err)
      Right trace -> pure trace
