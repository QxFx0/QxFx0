{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.RoundTrip
Description : Round-trip serialization tests for persisted types.

Tests that @decode . encode == Just x@ for all types that are persisted
to SQLite or transmitted across process boundaries. This catches the
Class-II serialization asymmetry defects found in audits (C, D).
-}
module Test.Suite.RoundTrip (roundTripTests) where

import Test.HUnit
import Data.Aeson (encode, decode, eitherDecode, Value, object, (.=), FromJSON(..), ToJSON(..))
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy.Char8 as BSL
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import QxFx0.Types.Recovery
  ( LocalRecoveryCause(..)
  , LocalRecoveryStrategy(..)
  , LocalRecoveryPolicy(..)
  )
import QxFx0.Types.TurnProjection
  ( PreActorFailureKind(..)
  , PreActorFailureEvent(..)
  , EffectSnapshot(..)
  , TurnFamilyDerivationStep(..)
  , GenerationAttempt(..)
  )
import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..))
import QxFx0.Types.Decision (DecisionDisposition(..), LegitimacyReason(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , ShadowSnapshotId(..)
  )
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Observability.Metrics (MetricType(..), Metric(..))
import QxFx0.Observability.Logging (LogLevel(..), LogEntry(..))
import QxFx0.Semantic.Network.Substrate (SubstrateEdgeInfo(..))

-- | Helper: round-trip a value through JSON and verify equality
assertRoundTrip :: (Eq a, Show a, A.ToJSON a, A.FromJSON a) => String -> a -> Assertion
assertRoundTrip label original =
  case A.eitherDecode (encode original) of
    Left err -> assertFailure $ label ++ " decode failed: " ++ err
    Right decoded -> assertEqual label original decoded

roundTripTests :: Test
roundTripTests = TestList
  [ TestLabel "LocalRecoveryCause" testLocalRecoveryCauseRT
  , TestLabel "LocalRecoveryStrategy" testLocalRecoveryStrategyRT
  , TestLabel "LocalRecoveryPolicy" testLocalRecoveryPolicyRT
  , TestLabel "PreActorFailureKind" testPreActorFailureKindRT
  , TestLabel "PreActorFailureEvent" testPreActorFailureEventRT
  , TestLabel "EffectSnapshot" testEffectSnapshotRT
  , TestLabel "TurnFamilyDerivationStep" testTurnFamilyDerivationStepRT
  , TestLabel "GenerationAttempt" testGenerationAttemptRT
  , TestLabel "CanonicalMoveFamily" testCanonicalMoveFamilyRT
  , TestLabel "IllocutionaryForce" testIllocutionaryForceRT
  , TestLabel "DecisionDisposition" testDecisionDispositionRT
  , TestLabel "LegitimacyReason" testLegitimacyReasonRT
  , TestLabel "ShadowDivergenceKind" testShadowDivergenceKindRT
  , TestLabel "ShadowDivergenceSeverity" testShadowDivergenceSeverityRT
  , TestLabel "ShadowSnapshotId" testShadowSnapshotIdRT
  , TestLabel "FmarMode" testFmarModeRT
  , TestLabel "MetricType" testMetricTypeRT
  , TestLabel "Metric" testMetricRT
  , TestLabel "LogLevel" testLogLevelRT
  , TestLabel "LogEntry" testLogEntryRT
  , TestLabel "SubstrateEdgeInfo" testSubstrateEdgeInfoRT
  ]

-- LocalRecoveryCause — audit C: had broken round-trip (ToJSON snake_case, FromJSON generic)
-- Fixed: hand-written FromJSON that parses rendered snake_case
testLocalRecoveryCauseRT :: Test
testLocalRecoveryCauseRT = TestList
  [ TestCase $ assertRoundTrip "RecoveryLowLegitimacy" RecoveryLowLegitimacy
  , TestCase $ assertRoundTrip "RecoveryParserLowConfidence" RecoveryParserLowConfidence
  , TestCase $ assertRoundTrip "RecoveryShadowUnavailable" RecoveryShadowUnavailable
  , TestCase $ assertRoundTrip "RecoveryShadowDivergence" RecoveryShadowDivergence
  , TestCase $ assertRoundTrip "RecoveryRenderBlocked" RecoveryRenderBlocked
  , TestCase $ assertRoundTrip "RecoveryUnknownTopic" RecoveryUnknownTopic
  , TestCase $ assertRoundTrip "RecoveryRuntimeDegraded" RecoveryRuntimeDegraded
  , TestCase $ assertRoundTrip "RecoveryLearningNeed" RecoveryLearningNeed
  , TestCase $ assertRoundTrip "RecoveryConatusGate" RecoveryConatusGate
  ]

-- LocalRecoveryStrategy — audit C: same issue as Cause
testLocalRecoveryStrategyRT :: Test
testLocalRecoveryStrategyRT = TestList
  [ TestCase $ assertRoundTrip "StrategyAskClarification" StrategyAskClarification
  , TestCase $ assertRoundTrip "StrategyNarrowScope" StrategyNarrowScope
  , TestCase $ assertRoundTrip "StrategyDefineKnownTerms" StrategyDefineKnownTerms
  , TestCase $ assertRoundTrip "StrategyDistinguishCandidates" StrategyDistinguishCandidates
  , TestCase $ assertRoundTrip "StrategyExposeUncertainty" StrategyExposeUncertainty
  , TestCase $ assertRoundTrip "StrategySafeRecovery" StrategySafeRecovery
  , TestCase $ assertRoundTrip "StrategyMorphologyExpansion" StrategyMorphologyExpansion
  ]

testLocalRecoveryPolicyRT :: Test
testLocalRecoveryPolicyRT = TestList
  [ TestCase $ assertRoundTrip "LocalRecoveryEnabled" LocalRecoveryEnabled
  , TestCase $ assertRoundTrip "LocalRecoveryDisabled" LocalRecoveryDisabled
  ]

testPreActorFailureKindRT :: Test
testPreActorFailureKindRT = TestList
  [ TestCase $ assertRoundTrip "PreActorTransportFailure" PreActorTransportFailure
  , TestCase $ assertRoundTrip "PreActorFallbackNonAuthoritative" PreActorFallbackNonAuthoritative
  , TestCase $ assertRoundTrip "PreActorNoExecutableTool" PreActorNoExecutableTool
  ]

testPreActorFailureEventRT :: Test
testPreActorFailureEventRT = TestList
  [ TestCase $ assertRoundTrip "simple event" $
      PreActorFailureEvent PreActorTransportFailure "action" "reason"
  ]

testEffectSnapshotRT :: Test
testEffectSnapshotRT = TestList
  [ TestCase $ assertRoundTrip "snapshot" (EffectSnapshot True) ]

testTurnFamilyDerivationStepRT :: Test
testTurnFamilyDerivationStepRT = TestList
  [ TestCase $ assertRoundTrip "step" (TurnFamilyDerivationStep "step-1" CMGround) ]

testGenerationAttemptRT :: Test
testGenerationAttemptRT = TestList
  [ TestCase $ assertRoundTrip "attempt" (GenerationAttempt "path-1" "success") ]

testCanonicalMoveFamilyRT :: Test
testCanonicalMoveFamilyRT = TestList
  [ TestCase $ assertRoundTrip "CMGround" CMGround
  , TestCase $ assertRoundTrip "CMDefine" CMDefine
  , TestCase $ assertRoundTrip "CMDistinguish" CMDistinguish
  , TestCase $ assertRoundTrip "CMReflect" CMReflect
  , TestCase $ assertRoundTrip "CMDescribe" CMDescribe
  , TestCase $ assertRoundTrip "CMPurpose" CMPurpose
  , TestCase $ assertRoundTrip "CMHypothesis" CMHypothesis
  , TestCase $ assertRoundTrip "CMRepair" CMRepair
  , TestCase $ assertRoundTrip "CMContact" CMContact
  , TestCase $ assertRoundTrip "CMAnchor" CMAnchor
  , TestCase $ assertRoundTrip "CMClarify" CMClarify
  , TestCase $ assertRoundTrip "CMDeepen" CMDeepen
  , TestCase $ assertRoundTrip "CMConfront" CMConfront
  , TestCase $ assertRoundTrip "CMNextStep" CMNextStep
  ]

testIllocutionaryForceRT :: Test
testIllocutionaryForceRT = TestList
  [ TestCase $ assertRoundTrip "IFAsk" IFAsk
  , TestCase $ assertRoundTrip "IFAssert" IFAssert
  , TestCase $ assertRoundTrip "IFOffer" IFOffer
  , TestCase $ assertRoundTrip "IFConfront" IFConfront
  , TestCase $ assertRoundTrip "IFContact" IFContact
  ]

testDecisionDispositionRT :: Test
testDecisionDispositionRT = TestList
  [ TestCase $ assertRoundTrip "DispositionPermit" DispositionPermit
  , TestCase $ assertRoundTrip "DispositionRepair" DispositionRepair
  , TestCase $ assertRoundTrip "DispositionDeny" DispositionDeny
  , TestCase $ assertRoundTrip "DispositionAdvisory" DispositionAdvisory
  ]

testLegitimacyReasonRT :: Test
testLegitimacyReasonRT = TestList
  [ TestCase $ assertRoundTrip "ReasonOk" ReasonOk
  , TestCase $ assertRoundTrip "ReasonShadowDivergence" ReasonShadowDivergence
  , TestCase $ assertRoundTrip "ReasonShadowUnavailable" ReasonShadowUnavailable
  , TestCase $ assertRoundTrip "ReasonLowParserConfidence" ReasonLowParserConfidence
  ]

testShadowDivergenceKindRT :: Test
testShadowDivergenceKindRT = TestList
  [ TestCase $ assertRoundTrip "ShadowNoDivergence" ShadowNoDivergence
  , TestCase $ assertRoundTrip "ShadowVerdictMismatch" ShadowVerdictMismatch
  , TestCase $ assertRoundTrip "ShadowUnavailableDivergence" ShadowUnavailableDivergence
  , TestCase $ assertRoundTrip "ShadowBridgeSkew" ShadowBridgeSkew
  , TestCase $ assertRoundTrip "ShadowExecutionError" ShadowExecutionError
  ]

testShadowDivergenceSeverityRT :: Test
testShadowDivergenceSeverityRT = TestList
  [ TestCase $ assertRoundTrip "ShadowSeverityClean" ShadowSeverityClean
  , TestCase $ assertRoundTrip "ShadowSeverityAdvisory" ShadowSeverityAdvisory
  , TestCase $ assertRoundTrip "ShadowSeveritySafety" ShadowSeveritySafety
  , TestCase $ assertRoundTrip "ShadowSeverityContract" ShadowSeverityContract
  , TestCase $ assertRoundTrip "ShadowSeverityUnavailable" ShadowSeverityUnavailable
  ]

testShadowSnapshotIdRT :: Test
testShadowSnapshotIdRT = TestList
  [ TestCase $ assertRoundTrip "snapshot id" (ShadowSnapshotId "snap-001") ]

testFmarModeRT :: Test
testFmarModeRT = TestList
  [ TestCase $ assertRoundTrip "FmarShadow" FmarShadow
  , TestCase $ assertRoundTrip "FmarLive" FmarLive
  ]

-- ── New round-trip tests for formerly write-only types ──────────────

testMetricTypeRT :: Test
testMetricTypeRT = TestList
  [ TestCase $ assertRoundTrip "Counter" Counter
  , TestCase $ assertRoundTrip "Gauge" Gauge
  , TestCase $ assertRoundTrip "Histogram" Histogram
  , TestCase $ assertRoundTrip "Timing" Timing
  ]

testMetricRT :: Test
testMetricRT = TestList
  [ TestCase $ assertRoundTrip "counter metric" $
      Metric "test.counter" Counter 42.0 (read "2024-01-01 00:00:00 UTC") Map.empty
  , TestCase $ assertRoundTrip "gauge metric with tags" $
      Metric "test.gauge" Gauge 3.14 (read "2024-01-01 00:00:00 UTC") (Map.fromList [("host","localhost")])
  ]

testLogLevelRT :: Test
testLogLevelRT = TestList
  [ TestCase $ assertRoundTrip "LogDebug" LogDebug
  , TestCase $ assertRoundTrip "LogInfo" LogInfo
  , TestCase $ assertRoundTrip "LogWarn" LogWarn
  , TestCase $ assertRoundTrip "LogError" LogError
  ]

testLogEntryRT :: Test
testLogEntryRT = TestList
  [ TestCase $ assertRoundTrip "simple log entry" $
      LogEntry (read "2024-01-01 00:00:00 UTC") LogInfo "test message" Map.empty Nothing
  , TestCase $ assertRoundTrip "log entry with context and error" $
      LogEntry (read "2024-01-01 00:00:00 UTC") LogError "failed" (Map.fromList [("module","engine")]) (Just "E001")
  ]

testSubstrateEdgeInfoRT :: Test
testSubstrateEdgeInfoRT = TestList
  [ TestCase $ assertRoundTrip "edge" (SubstrateEdgeInfo "topicA" "topicB" 0.5 3)
  ]
