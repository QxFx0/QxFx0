{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.M6FeltBenchmark
Description : M6 bounded benchmark — one replay-visible governed session
              run through the mechanical M6-FELT gate.

Per M6_WITNESS_PROTOCOL.md §7.3, the bounded benchmark is a multi-turn
domain-dialogue fixture with at least one commitment revision, tying the
C1–C4 contours together in a single replay-visible session.

The session is run through the production runtime ('bootstrapSession' +
'runTurnInSession', real PGF grammar, real SQLite persistence); each
turn's 'TurnReplayTrace' is read back from @turn_quality.replay_trace_json@
(exactly what a replay consumer would see), and the whole session is then
evaluated by 'evaluateM6FeltGate'.  The session is the same fixture the
evidence package will cite: a governed multi-turn dialogue over the
definition corpus (свобода, ответственность, истина) with a distinction
turn, a challenge turn (repair), and follow-ups.
-}
module Test.Suite.M6FeltBenchmark
  ( m6FeltBenchmarkTests
  , benchmarkSessionInputs
  , runBenchmarkSession
  , benchmarkVerdict
  ) where

import Control.Exception (finally, try)
import Control.Monad (foldM)
import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import Test.HUnit (Test(..), assertBool, assertFailure)

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , decodePersistedReplayTrace
  )

import qualified Test.Support.Runtime as Runtime
  ( Session(..)
  , bootstrapSession
  , runTurnInSession
  )
import Test.Support (withRuntimeEnv)
import QxFx0.Core.M6FeltGate
  ( FeltGate(..)
  , M6FeltEvidence(..)
  , M6FeltVerdict(..)
  , evaluateM6FeltGate
  )

-- ---------------------------------------------------------------------------
-- Session fixture
-- ---------------------------------------------------------------------------

-- | The bounded benchmark session: 12 turns over the definition corpus,
-- with one distinction turn and one challenge (repair) turn.
benchmarkSessionInputs :: [Text]
benchmarkSessionInputs =
  [ "что такое свобода?"
  , "что такое ответственность?"
  , "что такое истина?"
  , "чем отличается свобода от ответственности?"
  , "объясни подробнее, что такое свобода"
  , "приведи пример, что такое ответственность"
  , "контрпример: свобода — это не то, что ты утверждаешь"
  , "я сомневаюсь, приведи контрпример к свободе"
  , "объясни ещё раз, что такое истина"
  , "как свобода связана с ответственностью?"
  , "докажи, что свобода предполагает возможность выбора"
  , "а что если свобода — это иллюзия?"
  ]

-- | Run the benchmark session through the production runtime, reading one
-- replay trace per turn back from the persisted @turn_quality@ table.
runBenchmarkSession :: IO [TurnReplayTrace]
runBenchmarkSession =
  withRuntimeEnv "m6-benchmark" $
    do
      session0 <- Runtime.bootstrapSession True "m6-benchmark-session"
      let step (sess, acc) input = do
            result <- try (Runtime.runTurnInSession sess input)
                          :: IO (Either QxFx0Exception (Runtime.Session, Text))
            case result of
              Left err ->
                assertFailure ("benchmark turn raised: " <> show err)
              Right (sess', _) -> do
                trace <- loadLatestTrace
                  (Runtime.sessDbPath sess')
                  (Runtime.sessSessionId sess')
                pure (sess', trace : acc)
      (_, tracesRev) <- foldM step (session0, []) benchmarkSessionInputs
      pure (reverse tracesRev)

-- | Read the most recent persisted replay trace for a session.
loadLatestTrace :: FilePath -> Text -> IO TurnReplayTrace
loadLatestTrace dbPath sessionId = do
  opened <- NSQL.open dbPath
  conn <- case opened of
    Left err -> assertFailure ("cannot open benchmark trace DB: " <> T.unpack err) >> fail "unreachable"
    Right value -> pure value
  result <- (do
      prepared <- NSQL.prepare conn
        "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
      stmt <- case prepared of
        Left err -> assertFailure ("trace query failed: " <> T.unpack err) >> fail "unreachable"
        Right value -> pure value
      _ <- NSQL.bindText stmt 1 sessionId
      hasRow <- NSQL.stepRow stmt
      raw <- if hasRow then NSQL.columnTextLenient stmt 0 else pure ""
      NSQL.finalize stmt
      case decodePersistedReplayTrace (TE.encodeUtf8 raw) of
        Left err -> assertFailure ("trace decode failed: " <> err) >> fail "unreachable"
        Right trace -> pure trace
    ) `finally` NSQL.close conn
  pure result

-- | The verdict over the benchmark session.
benchmarkVerdict :: [TurnReplayTrace] -> M6FeltVerdict
benchmarkVerdict = evaluateM6FeltGate

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

-- | One-line per-turn summary, for debugging gate failures.
diagnoseTraces :: [TurnReplayTrace] -> Text
diagnoseTraces traces =
  T.unlines
    [ T.pack (intercalate " | " (summarizeLine i t))
    | (i, t) <- zip [1 :: Int ..] traces ]

summarizeLine :: Int -> TurnReplayTrace -> [String]
summarizeLine i t =
  [ show i
  , maybe ("-" :: String) T.unpack (trcContentSource t)
  , case trcAuthorityClass t of
      Just a  -> show a
      Nothing -> "-"
  , maybe ("-" :: String) T.unpack (trcFallbackReason t)
  , show (trcLinearizationOk t)
  , T.unpack (trcDialogueFocus t)
  , show (length (trcEmittedPredicates t))
  , show (T.length (trcRenderedAfterRebind t))
  , show (trcCommitmentEngaged t)
  , show (trcCommitmentContradicted t)
  , show (trcCommitmentStoreDecision t)
  , show (trcSemanticCommitmentCount t)
  , show (trcEvidenceAdmissibility t)
  ]

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

-- | The benchmark is fail-closed by construction: a real 12-turn governed
-- session over the definition corpus must either pass the gate
-- (M6FeltProven — evidence package) or fail with a precise list of gates.
--
-- Recorded result (2026-08-08): C1–C4 + governed-evidence pass on the
-- production runtime; Gate 5 (non-fallback) is the only mechanical blocker
-- — 7 of 12 turns fall back to @gf_response_plan:response_plan_without_propositions@
-- or @russian_compatibility_shim@ because the GF linearizer covers
-- definitional questions but not distinction / linkage / proof /
-- hypothesis turns.  M6-FELT therefore remains NOT PROVEN.
m6FeltBenchmarkTests :: [Test]
m6FeltBenchmarkTests =
  [ TestLabel "bounded benchmark: recorded fail-closed verdict is [FeltGate5NonFallback]" $
      TestCase $ do
        traces <- runBenchmarkSession
        let verdict = benchmarkVerdict traces
        case verdict of
          M6FeltProven evidence ->
            assertFailure $
              "bounded benchmark became M6FeltProven (" <> show evidence <> "); "
              <> "update the recorded result and the M6-FELT status"
          M6FeltNotProven failed ->
            assertBool
              ("expected exactly [FeltGate5NonFallback], got: " <> show failed
               <> "\n\nper-turn traces:\n" <> T.unpack (diagnoseTraces traces))
              (failed == [FeltGate5NonFallback])
  , TestLabel "bounded benchmark: gate is fail-closed on empty session" $
      TestCase $ do
        let verdict = benchmarkVerdict []
        case verdict of
          M6FeltNotProven failed ->
            assertBool "empty session must fail all six gates"
              (length failed == 6)
          M6FeltProven _ ->
            assertFailure "empty session must never be M6FeltProven"
  ]
