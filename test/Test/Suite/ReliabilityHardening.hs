{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ReliabilityHardening
  ( reliabilityHardeningTests
  ) where

import qualified Data.ByteString as BS
import qualified Data.Text as T
import Network.HTTP.Client (HttpException(..), HttpExceptionContent(..), defaultManagerSettings, newManager, parseRequest)
import Test.HUnit

import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  , selectTool
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationEntry(..)
  , CalibrationStatus(..)
  , CalibrationProposal(..)
  , CalibrationLog(..)
  , currentCalibrationVersion
  )
import QxFx0.Learning.GameTheory (solveMixedStrategy)
import QxFx0.Lexicon.GfMap
  ( topicToGfLexemeId
  , lookupGfLexemeForms
  , defaultGfLexemeId
  , GfMapLoadStatus(..)
  , gfMapLoadStatus
  , loadGfMapFromContent
  )
import QxFx0.Bridge.ExternalLLM
  ( llmEndpointAllowlist
  , llmUntrustedHostOverrideWarningTag
  , validateEndpointUrl
  , validateEndpointUrlWithContext
  , buildTransportFromEnvWithManager
  , LLMTransport(..)
  , extractStructured
  , decodeLlmBodyLimited
  , redactUpstreamError
  , classifyHttpException
  , classifyBodyReadFailure
  )
import QxFx0.Types.ExternalQuery (ExternalQueryError(..), TransportFallbackReason(..))
import Test.Support (withEnvVar)

-- | 1. Tool selection with empty candidate list -> total (no crash).
testSelectToolEmptyPool :: Test
testSelectToolEmptyPool = TestCase $ do
  let tools = []
      result = selectTool NeedLexiconExtension tools
  assertEqual "empty tool pool must yield Nothing" Nothing result

-- | 2. Tool selection with mismatched domain and no general fallback -> total.
testSelectToolNoMatchingDomain :: Test
testSelectToolNoMatchingDomain = TestCase $ do
  let tools =
        [ ExternalTool "script" DomainSalience 0.9 True
        ]
      result = selectTool NeedLexiconExtension tools
  assertEqual "no matching domain and no general fallback must yield Nothing"
    Nothing result

-- | 3. Calibration current version with empty accepted list -> total.
testCalibrationVersionEmptyLog :: Test
testCalibrationVersionEmptyLog = TestCase $ do
  let calLog = CalibrationLog []
      result = currentCalibrationVersion calLog
  assertEqual "empty calibration log must yield Nothing" Nothing result

-- | 4. Calibration current version with no accepted entries -> total.
testCalibrationVersionNoAccepted :: Test
testCalibrationVersionNoAccepted = TestCase $ do
  let calLog = CalibrationLog
        [ CalibrationEntry (CalibrationId 1) (ProposalRule "rule") Pending 0 Nothing Nothing
        , CalibrationEntry (CalibrationId 2) (ProposalRule "rule") Rejected 0 Nothing Nothing
        ]
      result = currentCalibrationVersion calLog
  assertEqual "log without accepted entries must yield Nothing" Nothing result

-- | 5. LP with valid uniform matrix -> Just probabilities.
testLPValidUniformMatrix :: Test
testLPValidUniformMatrix = TestCase $ do
  let a = replicate 3 (replicate 3 1.0)
      result = solveMixedStrategy a
  assertBool "uniform 3x3 matrix must return Just" (result /= Nothing)

-- | 6. LP with jagged rows -> safe reject (Nothing).
testLPJaggedRows :: Test
testLPJaggedRows = TestCase $ do
  let a =
        [ [1.0, 2.0]
        , [3.0]        -- jagged: second row shorter
        ]
      result = solveMixedStrategy a
  assertEqual "jagged matrix must yield Nothing (fail-closed)"
    Nothing result

-- | 7. LP with empty matrix -> safe reject.
testLPEmptyMatrix :: Test
testLPEmptyMatrix = TestCase $ do
  assertEqual "empty matrix must yield Nothing" Nothing (solveMixedStrategy [])

-- | 8. GfMap fallback deterministic (unknown topic -> default lexeme id).
testGfMapUnknownTopicFallback :: Test
testGfMapUnknownTopicFallback = TestCase $ do
  let result = topicToGfLexemeId "xyz_nonexistent_topic"
  assertEqual "unknown topic must fallback to defaultGfLexemeId"
    defaultGfLexemeId result

-- | 9. GfMap lookup unknown fun id -> Nothing (no crash).
testGfMapLookupUnknownFun :: Test
testGfMapLookupUnknownFun = TestCase $ do
  let result = lookupGfLexemeForms "nonexistent_fun"
  assertEqual "lookup of unknown fun must yield Nothing" Nothing result

-- | 10. GfMap missing resource -> explicit GfMapLoadFailed with structured reason.
testGfMapMissingResource :: Test
testGfMapMissingResource = TestCase $ do
  let (_data', status) = loadGfMapFromContent Nothing
  assertEqual "missing resource must yield explicit failed status"
    (GfMapLoadFailed "resource_missing_or_unreadable") status

-- | 11. GfMap empty/unparseable content -> explicit GfMapLoadFailed.
testGfMapEmptyContent :: Test
testGfMapEmptyContent = TestCase $ do
  let (_data', status) = loadGfMapFromContent (Just "")
  assertEqual "empty content must yield explicit failed status"
    (GfMapLoadFailed "resource_empty_or_unparseable") status

-- | 12. GfMap valid content -> GfMapLoaded with positive count.
testGfMapValidContent :: Test
testGfMapValidContent = TestCase $ do
  let tsv = "fun\tlemma\tpos\tnom\tgen\tprep\nfun1\tlemma1\tn\tлемма1\tлеммы\tлемме\n"
      (_data', status) = loadGfMapFromContent (Just tsv)
  case status of
    GfMapLoaded n -> assertBool "valid content must load >0 entries" (n > 0)
    other -> assertFailure ("expected GfMapLoaded, got: " ++ show other)

-- | 13. GfMap runtime load status must be healthy in test environment.
testGfMapRuntimeLoadHealthy :: Test
testGfMapRuntimeLoadHealthy = TestCase $ do
  case gfMapLoadStatus of
    GfMapLoaded n -> assertBool "runtime load must have >0 entries" (n > 0)
    GfMapLoadFailed reason -> assertFailure
      ("runtime GF map load failed in test env: " ++ show reason)

-- | 14. Allowed LLM endpoint (Mistral official) -> pass.
testLlmAllowlistMistral :: Test
testLlmAllowlistMistral = TestCase $ do
  let result = validateEndpointUrl "https://api.mistral.ai/v1/chat/completions" Nothing
  assertEqual "official mistral endpoint must be allowed" (Right ()) result

-- | 15. Allowed LLM endpoint (Fireworks official) -> pass.
testLlmAllowlistFireworks :: Test
testLlmAllowlistFireworks = TestCase $ do
  let result = validateEndpointUrl "https://api.fireworks.ai/inference/v1/chat/completions" Nothing
  assertEqual "official fireworks endpoint must be allowed" (Right ()) result

-- | 16. Blocked host without override -> fail-closed with TfrBlockedHost.
testLlmBlockedHostNoOverride :: Test
testLlmBlockedHostNoOverride = TestCase $ do
  let result = validateEndpointUrl "https://evil.com/api" Nothing
  assertEqual "untrusted host without override must be blocked"
    (Left TfrBlockedHost) result

-- | 17. Blocked host WITH single override -> fail-closed.
testLlmBlockedHostWithOverride :: Test
testLlmBlockedHostWithOverride = TestCase $ do
  let result = validateEndpointUrl "https://evil.com/api" (Just "1")
  assertEqual "single untrusted-host override must not be sufficient"
    (Left TfrUntrustedOverrideRejected) result

-- | 18. Blocked host with explicit test/dev context only -> still rejected.
testLlmBlockedHostWithDevOverride :: Test
testLlmBlockedHostWithDevOverride = TestCase $ do
  let result = validateEndpointUrlWithContext "https://evil.com/api" (Just "1") (Just "test") Nothing
  assertEqual "dev/test override without double confirmation must be rejected"
    (Left TfrUntrustedOverrideRejected) result

-- | 19. Blocked host with double confirmation only -> still rejected.
testLlmBlockedHostWithDoubleConfirm :: Test
testLlmBlockedHostWithDoubleConfirm = TestCase $ do
  let result = validateEndpointUrlWithContext "https://evil.com/api" (Just "1") Nothing (Just "1")
  assertEqual "double confirmation without dev/test context must be rejected"
    (Left TfrUntrustedOverrideRejected) result

-- | 19b. Blocked host with dev/test marker and double confirmation -> allowed.
testLlmBlockedHostWithDevAndDoubleConfirm :: Test
testLlmBlockedHostWithDevAndDoubleConfirm = TestCase $ do
  let result = validateEndpointUrlWithContext "https://evil.com/api" (Just "1") (Just "test") (Just "1")
  assertEqual "untrusted host with dev/test marker and double confirmation must return warning tag"
    (Right (Just llmUntrustedHostOverrideWarningTag)) result

-- | 20. Non-https endpoint -> fail-closed with TfrUnsafeEndpoint.
testLlmNonHttpsEndpoint :: Test
testLlmNonHttpsEndpoint = TestCase $ do
  let result = validateEndpointUrl "http://api.mistral.ai/v1/chat/completions" Nothing
  assertEqual "non-https endpoint must be rejected"
    (Left TfrUnsafeEndpoint) result

-- | 21. Userinfo trick must not make an evil host look allowlisted.
testLlmRejectsUserinfoHostSpoof :: Test
testLlmRejectsUserinfoHostSpoof = TestCase $ do
  let result = validateEndpointUrl "https://api.mistral.ai:443@evil.com/v1/chat/completions" Nothing
  assertEqual "userinfo host spoofing must be rejected before bearer token use"
    (Left TfrUnsafeEndpoint) result

-- | 22. Degraded runtime labels are not dev/test override context.
testLlmRejectsDegradedOverrideContext :: Test
testLlmRejectsDegradedOverrideContext = TestCase $ do
  let result = validateEndpointUrlWithContext "https://evil.com/api" (Just "1") (Just "degraded") Nothing
  assertEqual "degraded runtime mode must not satisfy untrusted-host override"
    (Left TfrUntrustedOverrideRejected) result

-- | 23. Empty endpoint -> fail-closed with TfrUnsafeEndpoint.
testLlmEmptyEndpoint :: Test
testLlmEmptyEndpoint = TestCase $ do
  let result = validateEndpointUrl "" Nothing
  assertEqual "empty endpoint must be rejected"
    (Left TfrUnsafeEndpoint) result

-- | 24. Env-based untrusted override must not revalidate into mock fallback.
testLlmEnvOverrideBuildsRealTransport :: Test
testLlmEnvOverrideBuildsRealTransport = TestCase $ do
  manager <- newManager defaultManagerSettings
  transport <-
    withEnvVar "QXFX0_LLM_TRANSPORT" (Just "fireworks") $
      withEnvVar "QXFX0_FIREWORKS_API_KEY" (Just "test-key") $
        withEnvVar "QXFX0_FIREWORKS_ENDPOINT" (Just "https://example.test/inference/v1/chat/completions") $
          withEnvVar "QXFX0_LLM_ALLOW_UNTRUSTED_HOST" (Just "1") $
            withEnvVar "QXFX0_LLM_ALLOW_UNTRUSTED_HOST_CONFIRM" (Just "1") $
              withEnvVar "QXFX0_TEST_MODE" (Just "1") $
              buildTransportFromEnvWithManager manager
  case transport of
    FireworksTransport _ _ -> pure ()
    other -> assertFailure ("expected FireworksTransport for confirmed untrusted override, got: " ++ show other)

-- | 25. Allowlist is non-empty and contains expected hosts.
testLlmAllowlistContents :: Test
testLlmAllowlistContents = TestCase $ do
  assertBool "allowlist must contain api.mistral.ai"
    ("api.mistral.ai" `elem` llmEndpointAllowlist)
  assertBool "allowlist must contain api.fireworks.ai"
    ("api.fireworks.ai" `elem` llmEndpointAllowlist)

-- | 26. Oversized LLM response bodies are rejected before decoding.
testLlmOversizeBodyRejected :: Test
testLlmOversizeBodyRejected = TestCase $ do
  let result = decodeLlmBodyLimited 8 (BS.replicate 9 97)
  case result of
    Left (EqeInvalidResponse msg) -> do
      assertBool "oversize response must use structured reason" ("response_too_large" `T.isInfixOf` msg)
      assertBool "oversize response must report max_bytes" ("max_bytes=8" `T.isInfixOf` msg)
    other -> assertFailure ("expected EqeInvalidResponse for oversize body, got: " ++ show other)

-- | 27. Oversized 429 responses preserve rate-limit classification.
testLlmOversizeRateLimitClassified :: Test
testLlmOversizeRateLimitClassified = TestCase $ do
  let result = classifyBodyReadFailure 429 (EqeInvalidResponse "response_too_large:max_bytes=8:actual_bytes=9")
  case result of
    EqeRateLimited msg -> do
      assertBool "oversize 429 must keep rate-limit status" ("upstream_status=429" `T.isInfixOf` msg)
      assertBool "oversize 429 diagnostic must stay redacted" ("body_redacted" `T.isInfixOf` msg)
      assertBool "oversize 429 diagnostic must include oversize tag" ("response_too_large" `T.isInfixOf` msg)
    other -> assertFailure ("expected EqeRateLimited for oversized 429 body, got: " ++ show other)

-- | 28. Upstream error bodies are redacted from diagnostics.
testLlmUpstreamErrorRedacted :: Test
testLlmUpstreamErrorRedacted = TestCase $ do
  let raw = "token=secret-password payload should not escape"
      diag = redactUpstreamError 401 raw
  assertBool "redacted diagnostic must include upstream status" ("upstream_status=401" `T.isInfixOf` diag)
  assertBool "redacted diagnostic must not include raw secret" (not ("secret-password" `T.isInfixOf` diag))
  assertBool "redacted diagnostic must report body length only" ("body_redacted" `T.isInfixOf` diag)

-- | 29. HTTP response timeout is typed as EqeTimeout.
testLlmTimeoutClassified :: Test
testLlmTimeoutClassified = TestCase $ do
  req <- parseRequest "https://api.mistral.ai/v1/chat/completions"
  let result = classifyHttpException (HttpExceptionRequest req ResponseTimeout)
  assertEqual "response timeout must be a typed timeout" (EqeTimeout "response_timeout") result

-- | 30. extractStructured unwraps chat-completion envelope.
testExtractStructuredUnwrapsContent :: Test
testExtractStructuredUnwrapsContent = TestCase $ do
  let envelope = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"word\\\":\\\"свобода\\\"}\"}}]}"
      result = extractStructured envelope
  assertEqual "typed decoder must unwrap content from envelope"
    "{\"word\":\"свобода\"}" result

-- | 31. extractStructured returns raw body on empty choices.
testExtractStructuredEmptyChoices :: Test
testExtractStructuredEmptyChoices = TestCase $ do
  let envelope = "{\"choices\":[]}"
      result = extractStructured envelope
  assertEqual "empty choices must return raw body" envelope result

-- | 32. extractStructured returns raw body on invalid JSON.
testExtractStructuredInvalidJson :: Test
testExtractStructuredInvalidJson = TestCase $ do
  let garbage = "this is not json"
      result = extractStructured garbage
  assertEqual "invalid json must return raw body" garbage result

-- | 33. extractStructured returns raw body when content is missing.
testExtractStructuredMissingContent :: Test
testExtractStructuredMissingContent = TestCase $ do
  let envelope = "{\"choices\":[{\"message\":{\"role\":\"assistant\"}}]}"
      result = extractStructured envelope
  assertEqual "missing content must return raw body" envelope result

-- | 34. extractStructured returns raw body for plain payload (backward compat).
testExtractStructuredPlainPayload :: Test
testExtractStructuredPlainPayload = TestCase $ do
  let payload = "{\"word\":\"свобода\"}"
      result = extractStructured payload
  assertEqual "plain payload must pass through" payload result

reliabilityHardeningTests :: [Test]
reliabilityHardeningTests =
  [ TestLabel "select-tool-empty-pool"             testSelectToolEmptyPool
  , TestLabel "select-tool-no-matching-domain"     testSelectToolNoMatchingDomain
  , TestLabel "calibration-version-empty-log"      testCalibrationVersionEmptyLog
  , TestLabel "calibration-version-no-accepted"   testCalibrationVersionNoAccepted
  , TestLabel "lp-valid-uniform-matrix"            testLPValidUniformMatrix
  , TestLabel "lp-jagged-rows"                    testLPJaggedRows
  , TestLabel "lp-empty-matrix"                   testLPEmptyMatrix
  , TestLabel "gfmap-unknown-topic-fallback"      testGfMapUnknownTopicFallback
  , TestLabel "gfmap-lookup-unknown-fun"           testGfMapLookupUnknownFun
  , TestLabel "gfmap-missing-resource"           testGfMapMissingResource
  , TestLabel "gfmap-empty-content"              testGfMapEmptyContent
  , TestLabel "gfmap-valid-content"              testGfMapValidContent
  , TestLabel "gfmap-runtime-load-healthy"       testGfMapRuntimeLoadHealthy
  , TestLabel "llm-allowlist-mistral"            testLlmAllowlistMistral
  , TestLabel "llm-allowlist-fireworks"          testLlmAllowlistFireworks
  , TestLabel "llm-blocked-host-no-override"   testLlmBlockedHostNoOverride
  , TestLabel "llm-blocked-host-with-override" testLlmBlockedHostWithOverride
  , TestLabel "llm-blocked-host-dev-override" testLlmBlockedHostWithDevOverride
  , TestLabel "llm-blocked-host-double-confirm" testLlmBlockedHostWithDoubleConfirm
  , TestLabel "llm-blocked-host-dev-and-double-confirm" testLlmBlockedHostWithDevAndDoubleConfirm
  , TestLabel "llm-non-https-endpoint"          testLlmNonHttpsEndpoint
  , TestLabel "llm-rejects-userinfo-host-spoof" testLlmRejectsUserinfoHostSpoof
  , TestLabel "llm-rejects-degraded-override" testLlmRejectsDegradedOverrideContext
  , TestLabel "llm-empty-endpoint"             testLlmEmptyEndpoint
  , TestLabel "llm-env-override-builds-real-transport" testLlmEnvOverrideBuildsRealTransport
  , TestLabel "llm-allowlist-contents"          testLlmAllowlistContents
  , TestLabel "llm-oversize-body-rejected"     testLlmOversizeBodyRejected
  , TestLabel "llm-oversize-rate-limit-classified" testLlmOversizeRateLimitClassified
  , TestLabel "llm-upstream-error-redacted"    testLlmUpstreamErrorRedacted
  , TestLabel "llm-timeout-classified"         testLlmTimeoutClassified
  , TestLabel "extract-structured-unwraps"     testExtractStructuredUnwrapsContent
  , TestLabel "extract-structured-empty-choices" testExtractStructuredEmptyChoices
  , TestLabel "extract-structured-invalid-json" testExtractStructuredInvalidJson
  , TestLabel "extract-structured-missing-content" testExtractStructuredMissingContent
  , TestLabel "extract-structured-plain-payload" testExtractStructuredPlainPayload
  ]
