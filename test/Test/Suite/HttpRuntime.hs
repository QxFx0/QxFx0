{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.HttpRuntime
  ( httpRuntimeTests
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, bracket, try)
import Control.Monad (replicateM, unless, when)
import Data.Aeson (FromJSON(..), Value(..), eitherDecode, object, withObject, (.:), (.=))
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Aeson.Types (parseMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Simple
  ( addRequestHeader
  , getResponseBody
  , getResponseHeader
  , getResponseStatusCode
  , httpLBS
  , httpNoBody
  , parseRequest
  , Request
  , setRequestBodyJSON
  , setRequestMethod
  )
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.IO (Handle)
import System.Timeout (timeout)
import System.Process
  ( CreateProcess(std_err, std_out)
    , ProcessHandle
  , StdStream(Inherit)
    , createProcess
    , proc
    , readProcess
    , readProcessWithExitCode
    , terminateProcess
    , waitForProcess
  )
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import Test.Support (removeIfExists, withEnvVar, withRuntimeEnv, withStrictRuntimeEnv)

data TurnProbe = TurnProbe
  { tpSessionId :: !Text
  , tpRuntimeEpoch :: !Text
  , tpRuntimeTurnIndex :: !Int
  } deriving stock (Eq, Show)

instance FromJSON TurnProbe where
  parseJSON = withObject "TurnProbe" $ \o ->
    TurnProbe
      <$> o .: "session_id"
      <*> o .: "runtime_epoch"
      <*> o .: "runtime_turn_index"

data UnknownTurnErrorProbe = UnknownTurnErrorProbe
  { uteError :: !Text
  , uteResultUnknown :: !Bool
  } deriving stock (Eq, Show)

instance FromJSON UnknownTurnErrorProbe where
  parseJSON = withObject "UnknownTurnErrorProbe" $ \o ->
    UnknownTurnErrorProbe
      <$> o .: "error"
      <*> o .: "result_unknown"

httpRuntimeTests :: [Test]
httpRuntimeTests =
  [ testHttpRuntimeSessionContinuity
  , testHttpRuntimeStrictHappyPath
  , testTurnRequiresSessionIdWhenDefaultMissing
  , testRuntimeReadyRequiresAuthWhenApiKeySet
  , testTurnAcceptsLargeInputUpToRuntimeLimit
  , testTurnRejectsInputBeyondRuntimeLimit
  , testTurnSessionTokenOwnershipWhenApiKeySet
  , testTurnSessionTokenSurvivesRestart
  , testHealthContracts
  , testRuntimeReadyProbeHasNoSessionSideEffects
  , testRuntimeReadyRejectsSessionQueryParam
  , testRuntimeReadyUsesCache
  , testRuntimeReadyRateLimitedOnBurst
  , testRuntimeReadyProbeFailureSanitizesDetails
  , testWorkerSessionCapRejectsNewSessions
  , testPostCommitTailFailureDoesNotFlipCommittedTurnToError
  , testTurnPostSendFailureHasNoAutoRetry
  , testTurnExplicitErrorPoisonsWorker
  , testServeHttpRejectsZeroBindWithoutExplicitOptIn
  , testDirectSidecarRejectsHttpEnvZeroBindWithoutExplicitOptIn
  , testHttpSidecarStartupFailsWhenPortInUse
  ]

testHttpRuntimeSessionContinuity :: Test
testHttpRuntimeSessionContinuity = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_continuity.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        assertRuntimeReady port
        first <- postTurnOk port "s1" "Что такое свобода?"
        second <- postTurnOk port "s1" "А что потом?"
        third <- postTurnOk port "s2" "Что такое контакт?"
        assertEqual "first turn should belong to s1" "s1" (tpSessionId first)
        assertEqual "second turn should belong to s1" "s1" (tpSessionId second)
        assertEqual "third turn should belong to s2" "s2" (tpSessionId third)
        assertEqual "runtime epoch must stay stable inside one live session" (tpRuntimeEpoch first) (tpRuntimeEpoch second)
        assertEqual "runtime turn index for first turn in session must be 1" 1 (tpRuntimeTurnIndex first)
        assertEqual "runtime turn index for second turn in session must be 2" 2 (tpRuntimeTurnIndex second)
        assertEqual "independent second session starts from index 1" 1 (tpRuntimeTurnIndex third)
        assertBool "runtime epoch for s2 should differ from s1 in this test run" (tpRuntimeEpoch first /= tpRuntimeEpoch third)

testHttpRuntimeStrictHappyPath :: Test
testHttpRuntimeStrictHappyPath = TestCase $
  withHttpSocketCapability $
    withStrictRuntimeEnv "qxfx0_test_http_strict_happy.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        (runtimeStatus, runtimeValue) <- getJsonStatusAndBody port "/runtime-ready"
        assertEqual "/runtime-ready must be available in strict happy-path" 200 runtimeStatus
        runtimeReady <- requireBoolField "strict runtime-ready signal" "ready" runtimeValue
        runtimeMode <- requireTextField "strict runtime-ready mode" "runtime_mode" runtimeValue
        agdaStatus <- requireTextField "strict runtime-ready agda status" "agda_status" runtimeValue
        decisionLocal <- requireBoolField "strict runtime-ready local decision-path flag" "decision_path_local_only" runtimeValue
        networkOptional <- requireBoolField "strict runtime-ready optional network flag" "network_optional_only" runtimeValue
        llmDecisionPath <- requireBoolField "strict runtime-ready llm decision-path flag" "llm_decision_path" runtimeValue
        assertBool "strict runtime-ready should report ready=true" runtimeReady
        assertEqual "strict runtime-ready should expose strict mode" "strict" runtimeMode
        assertEqual "strict runtime-ready should expose verified agda status" "verified" agdaStatus
        assertBool "strict runtime-ready must keep decision-path local-only" decisionLocal
        assertBool "strict runtime-ready should expose optional-network mode for decision-path" networkOptional
        assertBool "strict runtime-ready should expose llm-decision disabled" (not llmDecisionPath)
        first <- postTurnOk port "strict-s1" "Что такое свобода?"
        second <- postTurnOk port "strict-s1" "А что следует дальше?"
        assertEqual "strict first turn index should start at 1" 1 (tpRuntimeTurnIndex first)
        assertEqual "strict second turn index should continue to 2" 2 (tpRuntimeTurnIndex second)
        assertEqual "strict worker epoch should remain stable inside one session" (tpRuntimeEpoch first) (tpRuntimeEpoch second)

testTurnRequiresSessionIdWhenDefaultMissing :: Test
testTurnRequiresSessionIdWhenDefaultMissing = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_missing_session.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        (statusCode, value) <- postTurnRawBody port (object ["input" .= ("Без session_id" :: Text)])
        assertEqual "turn without session_id must be rejected when default is not configured" 400 statusCode
        errTag <- requireTextField "missing_session_id payload" "error" value
        assertEqual "error tag must be explicit" "missing_session_id" errTag

testRuntimeReadyRequiresAuthWhenApiKeySet :: Test
testRuntimeReadyRequiresAuthWhenApiKeySet = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_auth.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
        withSidecar [] $ \port -> do
          waitUntilSidecarHealthy port
          (unauthAliasCode, unauthAliasPayload) <- getJsonStatusAndBody port "/health"
          assertEqual "/health alias should require auth when API key is configured" 401 unauthAliasCode
          unauthAliasErr <- requireTextField "health alias unauthorized payload" "error" unauthAliasPayload
          assertEqual "health alias unauthorized payload should be explicit" "unauthorized" unauthAliasErr
          (unauthSidecarCode, unauthSidecarPayload) <- getJsonStatusAndBody port "/sidecar-health"
          assertEqual "/sidecar-health should require auth when API key is configured" 401 unauthSidecarCode
          unauthSidecarErr <- requireTextField "sidecar-health unauthorized payload" "error" unauthSidecarPayload
          assertEqual "sidecar-health unauthorized payload should be explicit" "unauthorized" unauthSidecarErr
          (authSidecarCode, authSidecarPayload) <- getJsonStatusAndBodyWithApiKey port "/sidecar-health" "test-api-key"
          assertEqual "/sidecar-health should pass with correct API key" 200 authSidecarCode
          sidecarSemantics <- requireTextField "sidecar-health authorized semantics" "semantics" authSidecarPayload
          assertEqual "authorized sidecar-health must preserve sidecar-only contract" "sidecar_liveness_only" sidecarSemantics
          (unauthCode, unauthPayload) <- getJsonStatusAndBody port "/runtime-ready"
          assertEqual "/runtime-ready should require auth when API key is configured" 401 unauthCode
          unauthErr <- requireTextField "runtime-ready unauthorized payload" "error" unauthPayload
          assertEqual "runtime-ready unauthorized payload should be explicit" "unauthorized" unauthErr
          (authCode, authPayload) <- getJsonStatusAndBodyWithApiKey port "/runtime-ready" "test-api-key"
          assertEqual "runtime-ready should pass with correct API key" 200 authCode
          ready <- requireBoolField "runtime-ready authorized ready flag" "ready" authPayload
          assertBool "runtime-ready should report ready under authorized request" ready

testTurnAcceptsLargeInputUpToRuntimeLimit :: Test
testTurnAcceptsLargeInputUpToRuntimeLimit = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_large_input_ok.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        assertRuntimeReady port
        probe <- postTurnOk port "large-input" (T.replicate 10000 "a")
        assertEqual "large input within runtime limit should still execute" 1 (tpRuntimeTurnIndex probe)

testTurnRejectsInputBeyondRuntimeLimit :: Test
testTurnRejectsInputBeyondRuntimeLimit = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_large_input_reject.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        assertRuntimeReady port
        (statusCode, value) <- postTurnRaw port "too-large-input" (T.replicate 10001 "a")
        assertEqual "input beyond shared runtime limit must be rejected" 400 statusCode
        errTag <- requireTextField "oversized input payload" "error" value
        assertEqual "oversized input rejection should stay explicit" "invalid_input" errTag

testTurnSessionTokenOwnershipWhenApiKeySet :: Test
testTurnSessionTokenOwnershipWhenApiKeySet = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_session_token.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
        withSidecar [] $ \port -> do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          (invalidCode, invalidValue) <- postTurnRawAuthenticated port "test-api-key" Nothing "owned" "   "
          assertEqual "invalid input must be rejected before session ownership is claimed" 400 invalidCode
          invalidErr <- requireTextField "invalid input payload" "error" invalidValue
          assertEqual "invalid input rejection must stay explicit" "invalid_input" invalidErr
          (firstCode, firstValue) <- postTurnRawAuthenticated port "test-api-key" Nothing "owned" "Первый turn создаёт ownership token"
          assertEqual "fresh authenticated session should bootstrap successfully" 200 firstCode
          first <- decodeAs "first authenticated turn" firstValue
          sessionToken <- requireTextField "fresh turn payload must include session token" "session_token" firstValue
          assertEqual "first turn should start at index 1" 1 (tpRuntimeTurnIndex first)
          (missingCode, missingValue) <- postTurnRawAuthenticated port "test-api-key" Nothing "owned" "Повторный turn без token"
          assertEqual "existing session should reject missing session token" 409 missingCode
          missingErr <- requireTextField "missing session token payload" "error" missingValue
          assertEqual "missing token error must be explicit" "session_token_required" missingErr
          (badCode, badValue) <- postTurnRawAuthenticated port "test-api-key" (Just "wrong-token") "owned" "Повторный turn с неверным token"
          assertEqual "existing session should reject invalid session token" 403 badCode
          badErr <- requireTextField "invalid session token payload" "error" badValue
          assertEqual "invalid token error must be explicit" "invalid_session_token" badErr
          (secondCode, secondValue) <- postTurnRawAuthenticated port "test-api-key" (Just sessionToken) "owned" "Повторный turn с корректным token"
          assertEqual "existing session should continue with valid session token" 200 secondCode
          second <- decodeAs "second authenticated turn" secondValue
          echoedToken <- requireTextField "validated turn should echo session token" "session_token" secondValue
          assertEqual "server should keep stable session token for same session" sessionToken echoedToken
          assertEqual "runtime epoch must stay stable with valid session token" (tpRuntimeEpoch first) (tpRuntimeEpoch second)
          assertEqual "turn index must continue inside same live worker" 2 (tpRuntimeTurnIndex second)

testTurnSessionTokenSurvivesRestart :: Test
testTurnSessionTokenSurvivesRestart = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_session_token_restart.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $ do
        port1 <- allocatePort
        token <- withSidecarOnPort port1 [] $ do
          waitUntilSidecarHealthy port1
          assertRuntimeReady port1
          (firstCode, firstValue) <- postTurnRawAuthenticated port1 "test-api-key" Nothing "persisted-owner" "Первый turn создаёт persist token"
          assertEqual "fresh authenticated session should bootstrap before restart" 200 firstCode
          requireTextField "first turn must include session token" "session_token" firstValue
        port2 <- allocatePort
        withSidecarOnPort port2 [] $ do
          waitUntilSidecarHealthy port2
          assertRuntimeReady port2
          (missingCode, missingValue) <- postTurnRawAuthenticated port2 "test-api-key" Nothing "persisted-owner" "После restart без token"
          assertEqual "persisted ownership should survive sidecar restart" 409 missingCode
          missingErr <- requireTextField "restart missing token payload" "error" missingValue
          assertEqual "restart missing token error must stay explicit" "session_token_required" missingErr
          (okCode, okValue) <- postTurnRawAuthenticated port2 "test-api-key" (Just token) "persisted-owner" "После restart с token"
          assertEqual "persisted session token should authorize access after restart" 200 okCode
          echoedToken <- requireTextField "restart turn should echo persisted token" "session_token" okValue
          assertEqual "persisted token should stay stable across sidecar restart" token echoedToken

testHealthContracts :: Test
testHealthContracts = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_health_contract.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        (sidecarStatus, sidecarValue) <- getJsonStatusAndBody port "/sidecar-health"
        assertEqual "/sidecar-health must be available" 200 sidecarStatus
        sidecarSemantics <- requireTextField "sidecar-health semantics" "semantics" sidecarValue
        assertEqual "/sidecar-health must report sidecar-only contract" "sidecar_liveness_only" sidecarSemantics
        (runtimeStatus, runtimeValue) <- getJsonStatusAndBody port "/runtime-ready"
        assertEqual "/runtime-ready must be available" 200 runtimeStatus
        runtimeReady <- requireBoolField "runtime-ready signal" "ready" runtimeValue
        decisionLocal <- requireBoolField "runtime-ready local decision-path flag" "decision_path_local_only" runtimeValue
        llmDecisionPath <- requireBoolField "runtime-ready llm decision-path flag" "llm_decision_path" runtimeValue
        assertBool "/runtime-ready must check backend readiness" runtimeReady
        assertBool "/runtime-ready should expose local decision-path mode" decisionLocal
        assertBool "/runtime-ready should expose llm decision-path disabled" (not llmDecisionPath)
        deprecatedHeaders <- getDeprecatedHealthHeaderValues port "/health"
        assertBool "/health must keep deprecated alias header" (not (null deprecatedHeaders))

testRuntimeReadyProbeHasNoSessionSideEffects :: Test
testRuntimeReadyProbeHasNoSessionSideEffects = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_probe.db" $
      withSidecar [] $ \port -> do
        let dbPath = "/tmp/qxfx0_test_http_runtime_ready_probe.db"
        waitUntilSidecarHealthy port
        before <- runtimeSessionsSnapshot dbPath
        runtimeStatus <- getStatusCode port "/runtime-ready"
        assertEqual "/runtime-ready must be available" 200 runtimeStatus
        after <- runtimeSessionsSnapshot dbPath
        assertEqual "/runtime-ready probe must not mutate runtime session bookkeeping" before after

testRuntimeReadyRejectsSessionQueryParam :: Test
testRuntimeReadyRejectsSessionQueryParam = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_query_param.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        (statusCode, value) <- getJsonStatusAndBody port "/runtime-ready?session_id=s1"
        assertEqual "/runtime-ready must reject per-session query override" 400 statusCode
        errTag <- requireTextField "runtime-ready query rejection payload" "error" value
        assertEqual "runtime-ready query rejection must be explicit" "unsupported_query_param" errTag

testRuntimeReadyUsesCache :: Test
testRuntimeReadyUsesCache = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_cache.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        _ <- getJsonStatusAndBody port "/runtime-ready"
        (_, secondValue) <- getJsonStatusAndBody port "/runtime-ready"
        fromCache <- requireBoolField "runtime-ready cache flag" "from_cache" secondValue
        assertBool "second runtime-ready call should be served from cache" fromCache

testRuntimeReadyRateLimitedOnBurst :: Test
testRuntimeReadyRateLimitedOnBurst = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_rate_limit.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        statuses <- replicateM 45 (getStatusCode port "/runtime-ready")
        assertBool "burst runtime-ready requests should include 429 rate_limited responses" (any (== 429) statuses)

testRuntimeReadyProbeFailureSanitizesDetails :: Test
testRuntimeReadyProbeFailureSanitizesDetails = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_sanitized_failure.db" $
      withSidecar ["--bin", "sh"] $ \port -> do
        waitUntilSidecarHealthy port
        (statusCode, value) <- getJsonStatusAndBody port "/runtime-ready"
        assertBool "runtime-ready should report non-ready status when probe binary exits non-zero" (statusCode /= 200)
        errTag <- requireTextField "runtime-ready failure payload" "error" value
        assertBool "runtime-ready should keep stable probe error tags"
          (errTag `elem` ["runtime_probe_failed", "runtime_probe_internal_error", "runtime_probe_timeout", "runtime_probe_bad_json"])
        assertBool "runtime-ready failure payload must not expose probe details" (not (hasJsonField "detail" value))

testWorkerSessionCapRejectsNewSessions :: Test
testWorkerSessionCapRejectsNewSessions = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_session_cap.db" $
      withSidecar ["--max-sessions", "1"] $ \port -> do
        waitUntilSidecarHealthy port
        first <- postTurnOk port "cap-s1" "Первый turn в первой сессии"
        (capCode, capPayload) <- postTurnRaw port "cap-s2" "Turn в новой сессии должен быть отклонён по cap"
        assertEqual "new session should be rejected when max sessions cap is reached" 503 capCode
        capErr <- requireTextField "session cap payload" "error" capPayload
        assertEqual "session cap error tag should be explicit" "session_capacity_exceeded" capErr
        active <- requireIntField "session cap payload should include current active workers" "sessions_active" capPayload
        maxSessions <- requireIntField "session cap payload should include configured maximum" "max_sessions" capPayload
        assertBool "sessions_active should be positive when cap is exceeded" (active >= 1)
        assertEqual "max_sessions should reflect configured cap" 1 maxSessions
        second <- postTurnOk port "cap-s1" "Старая сессия должна продолжать работать"
        assertEqual "existing session should continue within same worker epoch after cap rejection" (tpRuntimeEpoch first) (tpRuntimeEpoch second)

testPostCommitTailFailureDoesNotFlipCommittedTurnToError :: Test
testPostCommitTailFailureDoesNotFlipCommittedTurnToError = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_post_commit_tail.db" $ do
      port <- allocatePort
      markerPath <- pure ("/tmp/qxfx0_test_post_commit_tail_once_" <> show port <> ".flag")
      removeIfExists markerPath
      withEnvVar "QXFX0_TEST_POST_COMMIT_TAIL_EXCEPTION_ONCE_FILE" (Just markerPath) $
        withEnvVar "QXFX0_TEST_MODE" (Just "1") $
          withSidecarOnPort port [] $ do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          first <- postTurnOk port "sp" "Этот turn должен пережить late post-commit failure"
          markerTriggered <- doesFileExist markerPath
          assertBool "post-commit tail hook must trigger during first turn" markerTriggered
          second <- postTurnOk port "sp" "Следующий turn после late post-commit failure"
          assertEqual "first committed turn must still be acknowledged as turn 1" 1 (tpRuntimeTurnIndex first)
          assertEqual "worker epoch must survive late post-commit failure" (tpRuntimeEpoch first) (tpRuntimeEpoch second)
          assertEqual "continuity must continue after late post-commit failure" 2 (tpRuntimeTurnIndex second)
      removeIfExists markerPath

testTurnPostSendFailureHasNoAutoRetry :: Test
testTurnPostSendFailureHasNoAutoRetry = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_post_send_unknown.db" $ do
      port <- allocatePort
      markerPath <- pure ("/tmp/qxfx0_test_worker_crash_once_" <> show port <> ".flag")
      removeIfExists markerPath
      withEnvVar "QXFX0_TEST_MODE" (Just "1") $
        withEnvVar "QXFX0_TEST_WORKER_CRASH_AFTER_ACCEPT_ONCE_FILE" (Just markerPath) $
        withSidecarOnPort port [] $ do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          (firstCode, firstValue) <- postTurnRaw port "sx" "Первый turn должен упасть после accept"
          assertBool "post-send failure should surface as 502/504" (firstCode == 502 || firstCode == 504)
          errProbe <- decodeAs "post-send failure body" firstValue
          assertEqual "error must be explicit unknown outcome" "turn_outcome_unknown" (uteError errProbe)
          assertBool "response must mark unknown result semantics" (uteResultUnknown errProbe)
          second <- postTurnOk port "sx" "Второй turn после crash"
          assertEqual "after worker restart first successful turn must start from turn index 1" 1 (tpRuntimeTurnIndex second)
          third <- postTurnOk port "sx" "Третий turn в новом epoch"
          assertEqual "continuity should recover after restart with same worker epoch" (tpRuntimeEpoch second) (tpRuntimeEpoch third)
          assertEqual "turn index should continue inside new epoch" 2 (tpRuntimeTurnIndex third)
      removeIfExists markerPath

testTurnExplicitErrorPoisonsWorker :: Test
testTurnExplicitErrorPoisonsWorker = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_turn_explicit_error.db" $ do
      port <- allocatePort
      markerPath <- pure ("/tmp/qxfx0_test_worker_turn_error_once_" <> show port <> ".flag")
      removeIfExists markerPath
      writeFile markerPath "armed-after-first-turn\n"
      withEnvVar "QXFX0_TEST_MODE" (Just "1") $
        withEnvVar "QXFX0_TEST_WORKER_TURN_ERROR_AFTER_ACCEPT_ONCE_FILE" (Just markerPath) $
        withSidecarOnPort port [] $ do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          baseline <- postTurnOk port "se" "Базовый turn перед explicit error"
          removeIfExists markerPath
          (errCode, errValue) <- postTurnRaw port "se" "Этот turn должен завершиться explicit worker error"
          assertEqual "explicit worker error should return 502" 502 errCode
          errTag <- requireTextField "explicit error payload" "error" errValue
          assertBool "error should be known worker error family" (errTag == "worker_turn_exception" || errTag == "worker_command_error")
          unknownFlag <- requireBoolField "explicit error result_unknown" "result_unknown" errValue
          assertBool "explicit worker error should be marked as known failure" (not unknownFlag)
          recovered <- postTurnOk port "se" "Следующий turn после poisoned worker"
          assertBool "worker must be recreated after explicit error (new epoch)" (tpRuntimeEpoch recovered /= tpRuntimeEpoch baseline)
          assertEqual "new worker epoch must restart runtime turn index" 1 (tpRuntimeTurnIndex recovered)
      removeIfExists markerPath

testServeHttpRejectsZeroBindWithoutExplicitOptIn :: Test
testServeHttpRejectsZeroBindWithoutExplicitOptIn = TestCase $
  withRuntimeEnv "qxfx0_test_http_zero_bind_guard.db" $
    withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
      withEnvVar "QXFX0_HTTP_HOST" (Just "0.0.0.0") $
        withEnvVar "QXFX0_ALLOW_NON_LOOPBACK_HTTP" Nothing $ do
          binPath <- resolveQxFx0MainBinary
          (exitCode, _stdout, stderrText) <- readProcessWithExitCode binPath ["--serve-http", "9170"] ""
          case exitCode of
            ExitFailure _ -> pure ()
            ExitSuccess -> assertFailure "--serve-http should reject 0.0.0.0 without explicit non-loopback opt-in"
          assertBool "stderr should mention non-loopback opt-in requirement"
            ("QXFX0_ALLOW_NON_LOOPBACK_HTTP=1" `T.isInfixOf` T.pack stderrText)

testDirectSidecarRejectsHttpEnvZeroBindWithoutExplicitOptIn :: Test
testDirectSidecarRejectsHttpEnvZeroBindWithoutExplicitOptIn = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_direct_zero_bind_guard.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
        withEnvVar "QXFX0_HTTP_HOST" (Just "0.0.0.0") $
          withEnvVar "QXFX0_HOST" Nothing $
            withEnvVar "QXFX0_ALLOW_NON_LOOPBACK_HTTP" Nothing $ do
              root <- getCurrentDirectory
              binPath <- resolveQxFx0MainBinary
              port <- allocatePort
              let scriptPath = root </> "scripts" </> "http_runtime.py"
                  args = [scriptPath, "--port", show port, "--bin", binPath]
              timed <- timeout (10 * 1000000) (readProcessWithExitCode "python3" args "")
              case timed of
                Nothing ->
                  assertFailure "direct http sidecar should reject non-loopback env bind quickly"
                Just (exitCode, _stdout, stderrText) -> do
                  case exitCode of
                    ExitFailure _ -> pure ()
                    ExitSuccess -> assertFailure "direct http sidecar must reject 0.0.0.0 without explicit opt-in"
                  let stderrPayload = T.pack stderrText
                  assertBool "stderr should include structured non-loopback opt-in event"
                    ("non_loopback_bind_requires_opt_in" `T.isInfixOf` stderrPayload)
                  assertBool "stderr should mention QXFX0_ALLOW_NON_LOOPBACK_HTTP"
                    ("QXFX0_ALLOW_NON_LOOPBACK_HTTP=1" `T.isInfixOf` stderrPayload)

testHttpSidecarStartupFailsWhenPortInUse :: Test
testHttpSidecarStartupFailsWhenPortInUse = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_startup_port_in_use.db" $
      withOccupiedLoopbackPort $ \port -> do
        root <- getCurrentDirectory
        binPath <- resolveQxFx0MainBinary
        let scriptPath = root </> "scripts" </> "http_runtime.py"
            args =
              [ scriptPath
              , "--host", "127.0.0.1"
              , "--port", show port
              , "--bin", binPath
              ]
        timed <- timeout (10 * 1000000) (readProcessWithExitCode "python3" args "")
        case timed of
          Nothing ->
            assertFailure "http sidecar startup should fail quickly when bind port is already occupied"
          Just (exitCode, _stdout, stderrText) -> do
            case exitCode of
              ExitFailure _ -> pure ()
              ExitSuccess -> assertFailure "http sidecar startup must fail on occupied port"
            let stderrPayload = T.pack stderrText
            assertBool "stderr should include structured startup failure event"
              ("sidecar_start_failed" `T.isInfixOf` stderrPayload)
            assertBool "startup failure must classify occupied bind as port_in_use"
              ( "\"error\": \"port_in_use\"" `T.isInfixOf` stderrPayload
                  || "\"error\":\"port_in_use\"" `T.isInfixOf` stderrPayload
              )

withHttpSocketCapability :: IO () -> IO ()
withHttpSocketCapability action = do
  ready <- localhostSocketBindingAvailable
  when ready action

localhostSocketBindingAvailable :: IO Bool
localhostSocketBindingAvailable = do
  probe <- try allocatePort :: IO (Either SomeException Int)
  pure (either (const False) (const True) probe)

withSidecar :: [String] -> (Int -> IO a) -> IO a
withSidecar extraArgs action = do
  port <- allocatePort
  withSidecarOnPort port extraArgs (action port)

withOccupiedLoopbackPort :: (Int -> IO a) -> IO a
withOccupiedLoopbackPort action = do
  port <- allocatePort
  bracket
    (startPortOccupier port)
    stopSidecar
    (\_ -> do
      threadDelay 150000
      action port)

withSidecarOnPort :: Int -> [String] -> IO a -> IO a
withSidecarOnPort port extraArgs action = do
  root <- getCurrentDirectory
  binPath <- resolveQxFx0MainBinary
  let scriptPath = root </> "scripts" </> "http_runtime.py"
      args =
        [ scriptPath
        , "--host", "127.0.0.1"
        , "--port", show port
        , "--bin", binPath
        , "--session-ttl-seconds", "600"
        , "--worker-timeout-seconds", "60"
        ] <> extraArgs
  bracket
    (startSidecar args)
    stopSidecar
    (\_ -> action)

resolveQxFx0MainBinary :: IO FilePath
resolveQxFx0MainBinary = do
  output <- readProcess "cabal" ["list-bin", "qxfx0-main"] ""
  case lines output of
    (binPath:_) -> pure binPath
    [] -> fail "cabal list-bin qxfx0-main returned no executable path"

startSidecar :: [String] -> IO (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle)
startSidecar args =
  createProcess
    (proc "python3" args)
      { std_out = Inherit
      , std_err = Inherit
      }

startPortOccupier :: Int -> IO (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle)
startPortOccupier port =
  createProcess
    (proc "python3"
      [ "-c"
      , "import socket,time,sys;s=socket.socket();s.bind(('127.0.0.1', int(sys.argv[1])));s.listen(1);time.sleep(30)"
      , show port
      ])
      { std_out = Inherit
      , std_err = Inherit
      }

stopSidecar :: (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle) -> IO ()
stopSidecar (_, _, _, ph) = do
  terminateProcess ph
  _ <- waitForProcess ph
  pure ()

waitUntilSidecarHealthy :: Int -> IO ()
waitUntilSidecarHealthy port = loop 80
  where
    loop :: Int -> IO ()
    loop 0 = assertFailure "HTTP sidecar did not become healthy in time"
    loop n = do
      statusResult <- try (getStatusCodeForHealthcheck port "/sidecar-health") :: IO (Either SomeException Int)
      case statusResult of
        Right 200 -> pure ()
        _ -> threadDelay 100000 >> loop (n - 1)

assertRuntimeReady :: Int -> IO ()
assertRuntimeReady port = do
  status <- getStatusCodeForHealthcheck port "/runtime-ready"
  assertEqual "runtime-ready must return success when backend is healthy in tests" 200 status

getStatusCode :: Int -> String -> IO Int
getStatusCode port endpoint = do
  req <- parseRequest ("http://127.0.0.1:" <> show port <> endpoint)
  getResponseStatusCode <$> httpNoBody req

getStatusCodeForHealthcheck :: Int -> String -> IO Int
getStatusCodeForHealthcheck port endpoint = do
  mApiKey <- lookupEnv "QXFX0_API_KEY"
  case fmap T.pack mApiKey of
    Nothing -> getStatusCode port endpoint
    Just apiKey -> do
      req0 <- parseRequest ("http://127.0.0.1:" <> show port <> endpoint)
      let req = addRequestHeader "X-API-Key" (TE.encodeUtf8 apiKey) req0
      getResponseStatusCode <$> httpNoBody req

getJsonStatusAndBody :: Int -> String -> IO (Int, Value)
getJsonStatusAndBody port endpoint = do
  req <- parseRequest ("http://127.0.0.1:" <> show port <> endpoint)
  resp <- httpLBS req
  let statusCode = getResponseStatusCode resp
  case eitherDecode (getResponseBody resp) of
    Left err -> assertFailure ("response is not valid JSON: " <> err) >> fail "unreachable"
    Right value -> pure (statusCode, value)

getJsonStatusAndBodyWithApiKey :: Int -> String -> Text -> IO (Int, Value)
getJsonStatusAndBodyWithApiKey port endpoint apiKey = do
  req0 <- parseRequest ("http://127.0.0.1:" <> show port <> endpoint)
  let req = addRequestHeader "X-API-Key" (TE.encodeUtf8 apiKey) req0
  resp <- httpLBS req
  let statusCode = getResponseStatusCode resp
  case eitherDecode (getResponseBody resp) of
    Left err -> assertFailure ("response is not valid JSON: " <> err) >> fail "unreachable"
    Right value -> pure (statusCode, value)

getDeprecatedHealthHeaderValues :: Int -> String -> IO [Text]
getDeprecatedHealthHeaderValues port endpoint = do
  req <- parseRequest ("http://127.0.0.1:" <> show port <> endpoint)
  resp <- httpNoBody req
  pure (map decodeHeader (getResponseHeader "X-QXFX0-Deprecated" resp))
  where
    decodeHeader raw =
      case TE.decodeUtf8' raw of
        Left _ -> T.pack (show raw)
        Right txt -> txt

postTurnOk :: Int -> Text -> Text -> IO TurnProbe
postTurnOk port sessionId inputText = do
  (statusCode, value) <- postTurnRaw port sessionId inputText
  unless (statusCode == 200) $
    assertFailure ("turn request failed with status " <> show statusCode)
  decodeAs "turn success payload" value

postTurnRaw :: Int -> Text -> Text -> IO (Int, Value)
postTurnRaw port sessionId inputText = do
  postTurnRawBody port (object ["session_id" .= sessionId, "input" .= inputText])

postTurnRawAuthenticated :: Int -> Text -> Maybe Text -> Text -> Text -> IO (Int, Value)
postTurnRawAuthenticated port apiKey mSessionToken sessionId inputText =
  postTurnRawBodyWithHeaders
    port
    ( [addRequestHeader "X-API-Key" (TE.encodeUtf8 apiKey)]
      ++ maybe [] (\token -> [addRequestHeader "X-QXFX0-Session-Token" (TE.encodeUtf8 token)]) mSessionToken
    )
    (object ["session_id" .= sessionId, "input" .= inputText])

postTurnRawBody :: Int -> Value -> IO (Int, Value)
postTurnRawBody port body =
  postTurnRawBodyWithHeaders port [] body

postTurnRawBodyWithHeaders :: Int -> [Request -> Request] -> Value -> IO (Int, Value)
postTurnRawBodyWithHeaders port headerMutators body = do
  req0 <- parseRequest ("http://127.0.0.1:" <> show port <> "/turn")
  let req =
        foldr
          ($)
          ( setRequestMethod "POST"
          $ setRequestBodyJSON body
          $ addRequestHeader "Content-Type" "application/json" req0
          )
          headerMutators
  resp <- httpLBS req
  let statusCode = getResponseStatusCode resp
  case eitherDecode (getResponseBody resp) of
    Left err -> assertFailure ("turn response is not valid JSON: " <> err) >> fail "unreachable"
    Right value -> pure (statusCode, value)

decodeAs :: FromJSON a => String -> Value -> IO a
decodeAs label value =
  case parseMaybe parseJSON value of
    Just decoded -> pure decoded
    Nothing -> assertFailure (label <> " JSON shape mismatch") >> fail "unreachable"

requireTextField :: String -> Text -> Value -> IO Text
requireTextField label fieldName value =
  case value of
    Object obj ->
      case parseMaybe (.: AesonKey.fromText fieldName) obj of
        Just txt -> pure txt
        Nothing -> assertFailure (label <> " missing field: " <> T.unpack fieldName) >> fail "unreachable"
    _ -> assertFailure (label <> " expected JSON object") >> fail "unreachable"

requireBoolField :: String -> Text -> Value -> IO Bool
requireBoolField label fieldName value =
  case value of
    Object obj ->
      case parseMaybe (.: AesonKey.fromText fieldName) obj of
        Just flag -> pure flag
        Nothing -> assertFailure (label <> " missing field: " <> T.unpack fieldName) >> fail "unreachable"
    _ -> assertFailure (label <> " expected JSON object") >> fail "unreachable"

requireIntField :: String -> Text -> Value -> IO Int
requireIntField label fieldName value =
  case value of
    Object obj ->
      case parseMaybe (.: AesonKey.fromText fieldName) obj of
        Just n -> pure n
        Nothing -> assertFailure (label <> " missing field: " <> T.unpack fieldName) >> fail "unreachable"
    _ -> assertFailure (label <> " expected JSON object") >> fail "unreachable"

hasJsonField :: Text -> Value -> Bool
hasJsonField fieldName value =
  case value of
    Object obj -> AesonKeyMap.member (AesonKey.fromText fieldName) obj
    _ -> False

allocatePort :: IO Int
allocatePort = do
  raw <- readProcess
    "python3"
    [ "-c"
    , "import socket\ns=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
    ]
    ""
  pure (read (trim raw))

trim :: String -> String
trim = T.unpack . T.strip . T.pack

runtimeSessionsSnapshot :: FilePath -> IO (Bool, Int)
runtimeSessionsSnapshot dbPath = do
  exists <- doesFileExist dbPath
  if not exists
    then pure (False, 0)
    else do
      mDb <- NSQL.open dbPath
      case mDb of
        Left _ -> pure (True, 0)
        Right db -> do
          tableCount <- queryInt db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='runtime_sessions'"
          rowCount <- if tableCount > 0 then queryInt db "SELECT count(*) FROM runtime_sessions" else pure 0
          NSQL.close db
          pure (True, rowCount)

queryInt :: NSQL.Database -> Text -> IO Int
queryInt db sql = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure 0
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      result <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure result
