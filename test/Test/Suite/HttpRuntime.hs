{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.HttpRuntime
  ( httpRuntimeTests
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, bracket, bracket_, try)
import Control.Monad (replicateM, unless, when)
import Data.Aeson (FromJSON(..), Value(..), eitherDecode, eitherDecodeStrict', object, withObject, (.:), (.=))
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
  , setRequestBodyLBS
  , setRequestMethod
  )
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getCurrentDirectory
  , listDirectory
  , removePathForcibly
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeDirectory)
import System.IO (Handle, hFlush)
import qualified Data.Text.IO as TIO
import System.IO.Error (tryIOError)
import System.Timeout (timeout)
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Process
  ( CreateProcess(cwd, std_err, std_in, std_out)
    , ProcessHandle
  , StdStream(CreatePipe, Inherit)
    , createProcess
    , proc
    , readProcess
    , readProcessWithExitCode
    , terminateProcess
    , waitForProcess
  )
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import Test.Support (freshTestDbPath, freshTestPath, removeIfExists, withEnvVar, withRuntimeEnv, withStrictRuntimeEnv)

testRuntimeReadyStubEnvVar :: String
testRuntimeReadyStubEnvVar = "QXFX0_TEST_RUNTIME_READY_STUB"

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
  , testMalformedAuthenticatedTurnFailsClosed
  , testFreshClaimRollsBackAfterFirstTurnFailure
  , testTurnSessionTokenSurvivesRestart
  , testTurnSessionTokenStoreCorruptionFailsClosed
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
  , testWorkerProtocolVersionMismatch
  , testWorkerProtocolUnknownCommandKeepsWorkerAlive
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
        gfMapOk <- requireBoolField "strict runtime-ready GF map flag" "gfmap_ok" runtimeValue
        gfMapStatus <- requireTextField "strict runtime-ready GF map status" "gfmap_status" runtimeValue
        gfMapEntries <- requireIntField "strict runtime-ready GF map entries" "gfmap_entries" runtimeValue
        decisionLocal <- requireBoolField "strict runtime-ready local decision-path flag" "decision_path_local_only" runtimeValue
        networkOptional <- requireBoolField "strict runtime-ready optional network flag" "network_optional_only" runtimeValue
        llmDecisionPath <- requireBoolField "strict runtime-ready llm decision-path flag" "llm_decision_path" runtimeValue
        assertBool "strict runtime-ready should report ready=true" runtimeReady
        assertEqual "strict runtime-ready should expose strict mode" "strict" runtimeMode
        assertEqual "strict runtime-ready should expose verified agda status" "verified" agdaStatus
        assertBool "strict runtime-ready should expose healthy GF map" gfMapOk
        assertEqual "strict runtime-ready should expose loaded GF map status" "loaded" gfMapStatus
        assertBool "strict runtime-ready should expose positive GF map entry count" (gfMapEntries > 0)
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

testMalformedAuthenticatedTurnFailsClosed :: Test
testMalformedAuthenticatedTurnFailsClosed = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_malformed_authenticated.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
        withSidecar [] $ \port -> do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          req0 <- parseRequest ("http://127.0.0.1:" <> show port <> "/turn")
          let req =
                addRequestHeader "X-API-Key" "test-api-key"
                  $ addRequestHeader "Content-Type" "application/json"
                  $ setRequestMethod "POST"
                  $ setRequestBodyLBS "{bad-json" req0
          resp <- httpLBS req
          let statusCode = getResponseStatusCode resp
          assertEqual "malformed authenticated request must fail closed" 400 statusCode
          case eitherDecode (getResponseBody resp) of
            Left err -> assertFailure ("malformed authenticated response is not valid JSON: " <> err)
            Right value -> do
              errTag <- requireTextField "malformed authenticated payload" "error" value
              errCode <- requireTextField "malformed authenticated payload code" "error_code" value
              assertEqual "malformed authenticated request must expose stable error tag" "bad_request" errTag
              assertEqual "malformed authenticated request must expose stable machine code" "malformed_authenticated_request" errCode

testTurnSessionTokenSurvivesRestart :: Test
testTurnSessionTokenSurvivesRestart = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_session_token_restart.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $ do
        port1 <- allocatePort
        token <- withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port1 [] $ do
          waitUntilSidecarHealthy port1
          assertRuntimeReady port1
          (firstCode, firstValue) <- postTurnRawAuthenticated port1 "test-api-key" Nothing "persisted-owner" "Первый turn создаёт persist token"
          assertEqual "fresh authenticated session should bootstrap before restart" 200 firstCode
          requireTextField "first turn must include session token" "session_token" firstValue
        port2 <- allocatePort
        withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port2 [] $ do
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

testFreshClaimRollsBackAfterFirstTurnFailure :: Test
testFreshClaimRollsBackAfterFirstTurnFailure = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_claim_rollback.db" $ do
      port <- allocatePort
      mStateDir <- lookupEnv "QXFX0_STATE_DIR"
      stateDir <- case mStateDir of
        Just dir -> pure dir
        Nothing -> freshTestPath "qxfx0_test_http_claim_rollback.state"
      let markerPath = stateDir </> "test-hooks" </> ("qxfx0_test_worker_turn_error_claim_rollback_" <> show port <> ".flag")
      removeIfExists markerPath
      createDirectoryIfMissing True (takeDirectory markerPath)
      withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
        withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $
        withEnvVar "QXFX0_TEST_MODE" (Just "1") $
              withEnvVar "QXFX0_TEST_WORKER_TURN_ERROR_AFTER_ACCEPT_ONCE_FILE" (Just markerPath) $
              withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port [] $ do
                waitUntilSidecarHealthy port
                assertRuntimeReady port
                (errCode, errValue) <- postTurnRawAuthenticated port "test-api-key" Nothing "rollback-owned" "Первый turn должен завершиться explicit worker error"
                assertEqual "explicit worker error should return 502 on first turn" 502 errCode
                errTag <- requireTextField "first explicit error payload" "error" errValue
                assertBool "first explicit error should be known worker error family" (errTag == "worker_turn_exception" || errTag == "worker_command_error")
                (okCode, okValue) <- postTurnRawAuthenticated port "test-api-key" Nothing "rollback-owned" "Повторный первый turn после rollback ownership"
                assertEqual "fresh ownership claim must be rolled back after first-turn failure" 200 okCode
                okProbe <- decodeAs "fresh ownership rollback successful turn" okValue
                let _ = (okProbe :: TurnProbe)
                token <- requireTextField "fresh ownership rollback should mint new token" "session_token" okValue
                assertBool "rolled back ownership should permit a new fresh claim" (not (T.null token))
      removeIfExists markerPath

testTurnSessionTokenStoreCorruptionFailsClosed :: Test
testTurnSessionTokenStoreCorruptionFailsClosed = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_session_token_corrupt.db" $
      withEnvVar "QXFX0_API_KEY" (Just "test-api-key") $ do
        mDbPath <- lookupEnv "QXFX0_DB"
        dbPath <- case mDbPath of
          Just path -> pure path
          Nothing -> assertFailure "QXFX0_DB must be set in runtime env" >> fail "unreachable"
        let tokenStorePath = dbPath <> ".http-session-tokens.json"
        writeFile tokenStorePath "{not-json"
        withSidecar [] $ \port -> do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          (statusCode, value) <- postTurnRawAuthenticated port "test-api-key" Nothing "owned" "Попытка turn при corrupt token store"
          assertEqual "corrupt token store must fail closed" 503 statusCode
          errTag <- requireTextField "corrupt token store payload" "error" value
          assertEqual "corrupt token store error must be explicit" "session_token_store_unavailable" errTag

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
        gfMapOk <- requireBoolField "runtime-ready GF map flag" "gfmap_ok" runtimeValue
        gfMapStatus <- requireTextField "runtime-ready GF map status" "gfmap_status" runtimeValue
        gfMapEntries <- requireIntField "runtime-ready GF map entries" "gfmap_entries" runtimeValue
        decisionLocal <- requireBoolField "runtime-ready local decision-path flag" "decision_path_local_only" runtimeValue
        llmDecisionPath <- requireBoolField "runtime-ready llm decision-path flag" "llm_decision_path" runtimeValue
        assertBool "/runtime-ready must check backend readiness" runtimeReady
        assertBool "/runtime-ready must expose healthy GF map" gfMapOk
        assertEqual "/runtime-ready must expose loaded GF map status" "loaded" gfMapStatus
        assertBool "/runtime-ready must expose positive GF map entry count" (gfMapEntries > 0)
        assertBool "/runtime-ready should expose local decision-path mode" decisionLocal
        assertBool "/runtime-ready should expose llm decision-path disabled" (not llmDecisionPath)
        deprecatedHeaders <- getDeprecatedHealthHeaderValues port "/health"
        assertBool "/health must keep deprecated alias header" (not (null deprecatedHeaders))

testRuntimeReadyProbeHasNoSessionSideEffects :: Test
testRuntimeReadyProbeHasNoSessionSideEffects = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_probe.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        mDbPath <- lookupEnv "QXFX0_DB"
        dbPath <- case mDbPath of
          Just path -> pure path
          Nothing -> assertFailure "QXFX0_DB must be set in runtime env" >> fail "unreachable"
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
        assertBool "second stubbed runtime-ready call should report cached-shape semantics" fromCache

testRuntimeReadyRateLimitedOnBurst :: Test
testRuntimeReadyRateLimitedOnBurst = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_rate_limit.db" $
      withSidecar [] $ \port -> do
        waitUntilSidecarHealthy port
        statuses <- replicateM 45 (getStatusCode port "/runtime-ready")
        assertBool "stubbed runtime-ready should remain healthy under burst requests" (all (== 200) statuses)

testRuntimeReadyProbeFailureSanitizesDetails :: Test
testRuntimeReadyProbeFailureSanitizesDetails = TestCase $
  withHttpSocketCapability $
    withRuntimeEnv "qxfx0_test_http_runtime_ready_sanitized_failure.db" $
      withRealRuntimeReadySidecar ["--bin", "sh"] $ \port -> do
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
      mStateDir <- lookupEnv "QXFX0_STATE_DIR"
      stateDir <- case mStateDir of
        Just dir -> pure dir
        Nothing -> freshTestPath "qxfx0_test_http_post_commit_tail.state"
      let markerPath = stateDir </> "test-hooks" </> ("qxfx0_test_post_commit_tail_once_" <> show port <> ".flag")
      removeIfExists markerPath
      createDirectoryIfMissing True (takeDirectory markerPath)
      withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
        withEnvVar "QXFX0_TEST_POST_COMMIT_TAIL_EXCEPTION_ONCE_FILE" (Just markerPath) $
        withEnvVar "QXFX0_TEST_MODE" (Just "1") $
          withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port [] $ do
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
      mStateDir <- lookupEnv "QXFX0_STATE_DIR"
      stateDir <- case mStateDir of
        Just dir -> pure dir
        Nothing -> freshTestPath "qxfx0_test_http_post_send_unknown.state"
      let markerPath = stateDir </> "test-hooks" </> ("qxfx0_test_worker_crash_once_" <> show port <> ".flag")
      removeIfExists markerPath
      createDirectoryIfMissing True (takeDirectory markerPath)
      withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
        withEnvVar "QXFX0_TEST_MODE" (Just "1") $
              withEnvVar "QXFX0_TEST_WORKER_CRASH_AFTER_ACCEPT_ONCE_FILE" (Just markerPath) $
              withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port [] $ do
                waitUntilSidecarHealthy port
                assertRuntimeReady port
                (crashCode, crashValue) <- postTurnRaw port "sx" "Первый turn должен упасть после accept"
                assertBool "post-send failure should surface as 502/504" (crashCode == 502 || crashCode == 504)
                errProbe <- decodeAs "post-send failure body" crashValue
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
      mStateDir <- lookupEnv "QXFX0_STATE_DIR"
      stateDir <- case mStateDir of
        Just dir -> pure dir
        Nothing -> freshTestPath "qxfx0_test_http_turn_explicit_error.state"
      let markerPath = stateDir </> "test-hooks" </> ("qxfx0_test_worker_turn_error_once_" <> show port <> ".flag")
      removeIfExists markerPath
      createDirectoryIfMissing True (takeDirectory markerPath)
      withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
        withEnvVar "QXFX0_TEST_MODE" (Just "1") $
              withEnvVar "QXFX0_TEST_WORKER_TURN_ERROR_AFTER_ACCEPT_ONCE_FILE" (Just markerPath) $
              withEnvVar testRuntimeReadyStubEnvVar (Just "1") $ withSidecarOnPort port [] $ do
                waitUntilSidecarHealthy port
                assertRuntimeReady port
                (errCode, errValue) <- postTurnRaw port "se" "Этот turn должен завершиться explicit worker error"
                assertEqual "explicit worker error should return 502" 502 errCode
                errTag <- requireTextField "explicit error payload" "error" errValue
                assertBool "error should be known worker error family" (errTag == "worker_turn_exception" || errTag == "worker_command_error")
                unknownFlag <- requireBoolField "explicit error result_unknown" "result_unknown" errValue
                assertBool "explicit worker error should be marked as known failure" (not unknownFlag)
                recovered <- postTurnOk port "se" "Следующий turn после poisoned worker"
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
          assertBool "stderr should not be empty on zero-bind rejection"
            (not (T.null (T.strip (T.pack stderrText))))

testServeHttpInstalledArtifactOutsideCheckout :: Test
testServeHttpInstalledArtifactOutsideCheckout = TestCase $
  withHttpSocketCapability $
    withInstalledRuntimeEnv "qxfx0_test_http_installed_artifact.db" $ do
      port <- allocatePort
      binPath <- resolveQxFx0MainBinary
      mArtifactRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
      artifactRoot <- case mArtifactRoot of
        Just root -> pure root
        Nothing -> assertFailure "QXFX0_RESOURCE_ROOT must be set in installed artifact env" >> fail "unreachable"
      let tempWorkdir = artifactRoot
          stagedBin = artifactRoot </> "bin" </> "qxfx0-main"
      createDirectoryIfMissing True (takeDirectory stagedBin)
      copyFile binPath stagedBin
      bracket
        (createProcess ((proc stagedBin ["--serve-http", show port]) { std_out = Inherit, std_err = Inherit, cwd = Just tempWorkdir }))
        stopSidecar
        (\_ -> do
          waitUntilSidecarHealthy port
          assertRuntimeReady port
          probe <- postTurnOk port "artifact-s1" "Что такое свобода?"
          assertEqual "installed-artifact serve-http should execute first turn outside checkout" 1 (tpRuntimeTurnIndex probe))

testWorkerProtocolVersionMismatch :: Test
testWorkerProtocolVersionMismatch = TestCase $
  withRuntimeEnv "qxfx0_test_worker_protocol_mismatch.db" $
    withWorkerStdio "worker-proto-mismatch" $ \hin hout -> do
      sendWorkerLine hin "{\"command\":\"hello\",\"protocol_version\":\"999\",\"capabilities\":[]}"
      response <- readWorkerJsonLine hout
      errTag <- requireTextField "worker protocol mismatch payload" "error" response
      restartRequired <- requireBoolField "worker protocol mismatch payload" "restart_required" response
      assertEqual "worker protocol mismatch should be explicit" "protocol_version_mismatch" errTag
      assertBool "worker protocol mismatch should require restart" restartRequired

testWorkerProtocolUnknownCommandKeepsWorkerAlive :: Test
testWorkerProtocolUnknownCommandKeepsWorkerAlive = TestCase $
  withRuntimeEnv "qxfx0_test_worker_protocol_unknown.db" $
    withWorkerStdio "worker-proto-unknown" $ \hin hout -> do
      sendWorkerLine hin "[\"mystery\"]"
      firstResponse <- readWorkerJsonLine hout
      errTag <- requireTextField "unknown worker command payload" "error" firstResponse
      restartRequired <- requireBoolField "unknown worker command payload" "restart_required" firstResponse
      assertEqual "unknown worker command should stay explicit" "unknown_command" errTag
      assertBool "unknown worker command should not require restart" (not restartRequired)
      sendWorkerLine hin "[\"ping\"]"
      secondResponse <- readWorkerJsonLine hout
      status <- requireTextField "worker ping payload after unknown command" "status" secondResponse
      message <- requireTextField "worker ping payload after unknown command" "message" secondResponse
      assertEqual "worker should stay alive after unknown command" "ok" status
      assertEqual "worker ping should still succeed after unknown command" "pong" message

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
                  assertBool "stderr should not be empty on direct sidecar zero-bind rejection"
                    (not (T.null (T.strip stderrPayload)))

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
  withEnvVar testRuntimeReadyStubEnvVar (Just "1") $
    withSidecarOnPort port extraArgs (action port)

withRealRuntimeReadySidecar :: [String] -> (Int -> IO a) -> IO a
withRealRuntimeReadySidecar extraArgs action = do
  port <- allocatePort
  withEnvVar testRuntimeReadyStubEnvVar (Just "0") $
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
  mStub <- lookupEnv testRuntimeReadyStubEnvVar
  let scriptPath = root </> "scripts" </> "http_runtime.py"
      args =
        [ scriptPath
        , "--host", "127.0.0.1"
        , "--port", show port
        , "--bin", binPath
        , "--session-ttl-seconds", "600"
        , "--worker-timeout-seconds", "60"
        ] <> extraArgs
      launch = bracket (startSidecar args) stopSidecar (\_ -> action)
  case mStub of
    Just _ -> launch
    Nothing -> withEnvVar testRuntimeReadyStubEnvVar (Just "1") launch

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

withWorkerStdio :: Text -> (Handle -> Handle -> IO a) -> IO a
withWorkerStdio sessionId action = do
  binPath <- resolveQxFx0MainBinary
  bracket
    (createProcess (proc binPath ["--session-id", T.unpack sessionId, "--worker-stdio"]) { std_in = CreatePipe, std_out = CreatePipe, std_err = Inherit })
    stopSidecar
    (\(mIn, mOut, _, _) -> case (mIn, mOut) of
        (Just hin, Just hout) -> action hin hout
        _ -> assertFailure "worker stdio handles were not created" >> fail "unreachable")

sendWorkerLine :: Handle -> Text -> IO ()
sendWorkerLine handle line = do
  TIO.hPutStrLn handle line
  hFlush handle

readWorkerJsonLine :: Handle -> IO Value
readWorkerJsonLine handle = do
  line <- TIO.hGetLine handle
  case eitherDecodeStrict' (TE.encodeUtf8 line) of
    Left err -> assertFailure ("worker line is not valid JSON: " <> err) >> fail "unreachable"
    Right value -> pure value

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

withInstalledRuntimeEnv :: FilePath -> IO a -> IO a
withInstalledRuntimeEnv dbName action = do
  root <- getCurrentDirectory
  tmpDir <- testTempDir
  ts <- getPOSIXTime
  let suffix = show (round (ts * 1000000) :: Integer)
      dbPath = tmpDir <> "/" <> dbName <> "-" <> suffix
      artifactRoot = tmpDir </> (dbName <> "-artifact-" <> suffix)
      artifactScript = artifactRoot </> "scripts" </> "http_runtime.py"
      artifactStateDir = artifactRoot </> "state"
  bracket_
    (prepareInstalledArtifactRoot root artifactRoot)
    (do removePathIfExists artifactRoot
        mapM_ removeIfExists (runtimeArtifacts dbPath))
    $ withEnvVar "QXFX0_ROOT" Nothing
    $ withEnvVar "QXFX0_RESOURCE_ROOT" (Just artifactRoot)
    $ withEnvVar "QXFX0_STATE_DIR" (Just artifactStateDir)
    $ withEnvVar "QXFX0_HTTP_RUNTIME" (Just artifactScript)
    $ withEnvVar testRuntimeReadyStubEnvVar (Just "1")
    $ withEnvVar "QXFX0_DB" (Just dbPath)
    $ withEnvVar "QXFX0_RUNTIME_MODE" (Just "degraded")
      action

testTempDir :: IO FilePath
testTempDir = do
  root <- getCurrentDirectory
  let dir = root <> "/.test-tmp"
  createDirectoryIfMissing True dir
  pure dir

runtimeArtifacts :: FilePath -> [FilePath]
runtimeArtifacts dbPath =
  [ dbPath
  , dbPath <> "-wal"
  , dbPath <> "-shm"
  , dbPath <> ".http-session-tokens.json"
  , dbPath <> ".http-session-tokens.json.tmp"
  ]

removePathIfExists :: FilePath -> IO ()
removePathIfExists path = do
  isDir <- doesDirectoryExist path
  if isDir
    then removePathForcibly path
    else removeIfExists path

prepareInstalledArtifactRoot :: FilePath -> FilePath -> IO ()
prepareInstalledArtifactRoot sourceRoot artifactRoot = do
  removePathIfExists artifactRoot
  createDirectoryIfMissing True artifactRoot
  mapM_
    (\relative -> copyTree (sourceRoot </> relative) (artifactRoot </> relative))
    [ "semantics"
    , "resources"
    , "spec"
    , "migrations"
    , "scripts"
    ]

copyTree :: FilePath -> FilePath -> IO ()
copyTree source destination = do
  isDir <- doesDirectoryExist source
  if isDir
    then do
      createDirectoryIfMissing True destination
      entries <- listDirectory source
      mapM_ (\entry -> copyTree (source </> entry) (destination </> entry)) entries
    else do
      createDirectoryIfMissing True (takeDirectory destination)
      copyFile source destination
