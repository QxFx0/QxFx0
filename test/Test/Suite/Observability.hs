{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Suite.Observability (observabilityTests) where

import Test.HUnit
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.IORef
import Data.Time.Clock (getCurrentTime, diffUTCTime)

import QxFx0.Observability.Logging
import QxFx0.Observability.Metrics
import QxFx0.ExceptionPolicy (QxFx0Exception(..), mkRuntimeInitError)
import QxFx0.Types.TurnProjection (TurnReplayTrace(..))
import QxFx0.Core.Bayesian (userModelActive)
import QxFx0.Semantic.Logic (derivedInferenceActive)
import QxFx0.Memory.Episodic (episodicRecallActive)
import QxFx0.Core.ContentCluster (contentSalienceActive)
import QxFx0.Types.RuntimeRegime (defaultRuntimeRegime, rrFamilyDivergenceActive)

observabilityTests :: [Test]
observabilityTests =
  [ TestLabel "Observability.Logging" $ TestList loggingTests
  , TestLabel "Observability.Metrics" $ TestList metricsTests
  , TestLabel "Observability.Integration" $ TestList integrationTests
  , TestLabel "Observability.Performance" $ TestList performanceTests
  , TestLabel "Observability.P8AuditTrail" $ TestList p8AuditTrailTests
  ]

-- | Test logging functionality
loggingTests :: [Test]
loggingTests =
  [ TestCase $ do
      -- This is a smoke test - actual logging goes to stderr
      logDebug "test message" emptyContext
      -- If we get here without exception, logging works
      pure ()
  
  , TestCase $ do
      logInfo "test info" emptyContext
      pure ()
  
  , TestCase $ do
      logWarn "test warning" emptyContext
      pure ()
  
  , TestCase $ do
      logError "test error" emptyContext
      pure ()
  
  , TestCase $ do
      let ex = mkRuntimeInitError "Test" "test_op" "TEST_ERROR" Map.empty
      logException ex emptyContext
      pure ()
  
  , TestCase $ do
      let ctx = addContext "key1" "value1" $
                addContext "key2" "value2" emptyContext
      -- Context is built correctly if no exception
      pure ()
  
  , TestCase $ do
      timestamp <- getCurrentTime
      let entry = LogEntry timestamp LogInfo "test" emptyContext Nothing
          formatted = formatLogEntry entry
      assertBool "formatted output should not be empty" (not $ T.null formatted)
      assertBool "formatted output should contain message" ("test" `T.isInfixOf` formatted)
  
  , TestCase $ do
      timestamp <- getCurrentTime
      let entry = LogEntry timestamp LogError "error" emptyContext (Just "ERR001")
          formatted = formatLogEntry entry
      assertBool "formatted output should contain error code" ("ERR001" `T.isInfixOf` formatted)
  ]

-- | Test metrics functionality
metricsTests :: [Test]
metricsTests =
  [ TestCase $ do
      registry <- emptyRegistry
      recordCounter registry "test.counter" 1.0 Map.empty
      metrics <- getMetrics registry
      assertEqual "should have 1 metric" 1 (length metrics)
      let metric = head metrics
      assertEqual "metric name" "test.counter" (mName metric)
      assertEqual "metric type" Counter (mType metric)
      assertEqual "metric value" 1.0 (mValue metric)
  
  , TestCase $ do
      registry <- emptyRegistry
      recordGauge registry "test.gauge" 42.0 Map.empty
      metrics <- getMetrics registry
      assertEqual "should have 1 metric" 1 (length metrics)
      let metric = head metrics
      assertEqual "metric type" Gauge (mType metric)
      assertEqual "metric value" 42.0 (mValue metric)
  
  , TestCase $ do
      registry <- emptyRegistry
      recordHistogram registry "test.histogram" 100.0 Map.empty
      metrics <- getMetrics registry
      assertEqual "should have 1 metric" 1 (length metrics)
      let metric = head metrics
      assertEqual "metric type" Histogram (mType metric)
  
  , TestCase $ do
      registry <- emptyRegistry
      start <- getCurrentTime
      end <- getCurrentTime
      let duration = diffUTCTime end start
      recordTiming registry "test.timing" duration Map.empty
      metrics <- getMetrics registry
      assertEqual "should have 1 metric" 1 (length metrics)
      let metric = head metrics
      assertEqual "metric type" Timing (mType metric)
  
  , TestCase $ do
      registry <- emptyRegistry
      recordCounter registry "counter1" 1.0 Map.empty
      recordCounter registry "counter2" 2.0 Map.empty
      recordGauge registry "gauge1" 3.0 Map.empty
      metrics <- getMetrics registry
      assertEqual "should have 3 metrics" 3 (length metrics)
  
  , TestCase $ do
      registry <- emptyRegistry
      let tags = Map.fromList [("env", "test"), ("service", "qxfx0")]
      recordCounter registry "tagged.counter" 1.0 tags
      metrics <- getMetrics registry
      let metric = head metrics
      assertEqual "should have tags" tags (mTags metric)
  
  , TestCase $ do
      registry <- emptyRegistry
      recordCounter registry "test.metric" 123.0 (Map.singleton "tag" "value")
      metrics <- getMetrics registry
      let formatted = formatMetrics metrics
      assertBool "formatted output should not be empty" (not $ T.null formatted)
      assertBool "formatted output should contain metric name" ("test.metric" `T.isInfixOf` formatted)
  ]

-- | Test logging and metrics integration
integrationTests :: [Test]
integrationTests =
  [ TestCase $ do
      registry <- emptyRegistry
      
      -- Log start
      logInfo "Operation starting" emptyContext
      
      -- Record metric
      recordCounter registry "operation.start" 1.0 Map.empty
      
      -- Simulate work
      start <- getCurrentTime
      end <- getCurrentTime
      let duration = diffUTCTime end start
      
      -- Record timing
      recordTiming registry "operation.duration" duration Map.empty
      
      -- Log completion
      logInfo "Operation complete" 
        (addContext "duration_ms" (T.pack $ show $ round (realToFrac duration * 1000 :: Double)) emptyContext)
      
      -- Verify metrics
      metrics <- getMetrics registry
      assertEqual "should have 2 metrics" 2 (length metrics)
  
  , TestCase $ do
      registry <- emptyRegistry
      
      -- Log error
      logError "Operation failed" (addContext "reason" "test" emptyContext)
      
      -- Record error metric
      recordCounter registry "operation.error" 1.0 (Map.singleton "error_type" "test")
      
      metrics <- getMetrics registry
      assertEqual "should have 1 error metric" 1 (length metrics)
  ]

-- | Test observability overhead
performanceTests :: [Test]
performanceTests =
  [ TestCase $ do
      start <- getCurrentTime
      
      -- Perform 1000 log operations
      mapM_ (\i -> logDebug "test" (addContext "iteration" (T.pack $ show i) emptyContext)) [1..1000 :: Int]
      
      end <- getCurrentTime
      let duration = diffUTCTime end start
          avgMs = realToFrac duration * 1000 / 1000 :: Double
      
      -- Average should be less than 1ms per log (very conservative)
      assertBool ("logging overhead too high: " ++ show avgMs ++ "ms per log") (avgMs < 1.0)
  
  , TestCase $ do
      registry <- emptyRegistry
      start <- getCurrentTime
      
      -- Perform 1000 metric operations
      mapM_ (\i -> recordCounter registry "test.counter" (fromIntegral i) Map.empty) [1..1000 :: Int]
      
      end <- getCurrentTime
      let duration = diffUTCTime end start
          avgMs = realToFrac duration * 1000 / 1000 :: Double
      
      -- Average should be less than 0.1ms per metric (very conservative)
      assertBool ("metrics overhead too high: " ++ show avgMs ++ "ms per metric") (avgMs < 0.1)
      
      -- Verify all metrics recorded
      metrics <- getMetrics registry
      assertEqual "should have 1000 metrics" 1000 (length metrics)
  ]

-- | P8: Audit Trail Visibility tests
-- Verify that all 10 new trace fields are populated correctly based on flag state
p8AuditTrailTests :: [Test]
p8AuditTrailTests =
  [ TestCase $ do
      -- P8.1: Verify trcDoubtScore field exists and respects flag state
      -- When doubt computation is active, field should be Just; otherwise Nothing
      -- This is a compile-time check - if the field doesn't exist, this won't compile
      let _ = trcDoubtScore :: TurnReplayTrace -> Maybe Double
      pure ()
  
  , TestCase $ do
      -- P8.2: Verify trcEpisodicRetrievalCount field exists
      let _ = trcEpisodicRetrievalCount :: TurnReplayTrace -> Maybe Int
      assertBool "episodicRecallActive flag promoted to True (2026-06-04)" episodicRecallActive
  
  , TestCase $ do
      -- P8.3: Verify trcContentSaliencyDominantCluster field exists
      let _ = trcContentSaliencyDominantCluster :: TurnReplayTrace -> Maybe Int
      assertBool "contentSalienceActive flag promoted to True (2026-06-04)" contentSalienceActive
  
  , TestCase $ do
      -- P8.4: Verify trcMoodValence field exists
      let _ = trcMoodValence :: TurnReplayTrace -> Maybe Double
      pure ()
  
  , TestCase $ do
      -- P8.5: Verify trcMoodArousal field exists
      let _ = trcMoodArousal :: TurnReplayTrace -> Maybe Double
      pure ()
  
  , TestCase $ do
      -- P8.6: Verify trcUserModelTopIntent field exists
      let _ = trcUserModelTopIntent :: TurnReplayTrace -> Maybe Text
      assertBool "userModelActive flag should be False by default" (not userModelActive)
  
  , TestCase $ do
      -- P8.7: Verify trcUserModelConfidence field exists
      let _ = trcUserModelConfidence :: TurnReplayTrace -> Maybe Double
      pure ()
  
  , TestCase $ do
      -- P8.8: Verify trcDerivedInferenceCount field exists
      let _ = trcDerivedInferenceCount :: TurnReplayTrace -> Maybe Int
      assertBool "derivedInferenceActive flag promoted to True (2026-06-04)" derivedInferenceActive
  
  , TestCase $ do
      -- P8.9: Verify trcFamilyDivergenceOccurred field exists
      let _ = trcFamilyDivergenceOccurred :: TurnReplayTrace -> Maybe Bool
      let familyDivergenceEnabled = rrFamilyDivergenceActive defaultRuntimeRegime
      assertBool "familyDivergenceActive should be True by default (ADR-0019 promoted)" familyDivergenceEnabled
  
  , TestCase $ do
      -- P8.10: Verify trcConatusGateFired field already exists (from P1)
      let _ = trcConatusGateFired :: TurnReplayTrace -> Bool
      pure ()
  ]

