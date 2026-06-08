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
  , TestCase $ assertRoundTrip "StrategyIdentityReinforcement" StrategyIdentityReinforcement
  , TestCase $ assertRoundTrip "StrategyTemporalDeepening" StrategyTemporalDeepening
  , TestCase $ assertRoundTrip "StrategyRequestCalibration" StrategyRequestCalibration
  , TestCase $ assertRoundTrip "StrategyRequestRule" StrategyRequestRule
  , TestCase $ assertRoundTrip "StrategyRequestConcept" StrategyRequestConcept
  , TestCase $ assertRoundTrip "StrategyExternalDialogue" StrategyExternalDialogue
  ]

testLocalRecoveryPolicyRT :: Test
testLocalRecoveryPolicyRT = TestList
  [ TestCase $ assertRoundTrip "LocalRecoveryEnabled" LocalRecoveryEnabled
  , TestCase $ assertRoundTrip "LocalRecoveryDisabled" LocalRecoveryDisabled
  ]

-- PreActorFailureKind — audit D: was ToJSON-only, needs FromJSON
testPreActorFailureKindRT :: Test
testPreActorFailureKindRT = TestList
  [ TestCase $ assertRoundTrip "PreActorTransportFailure" PreActorTransportFailure
  , TestCase $ assertRoundTrip "PreActorFallbackNonAuthoritative" PreActorFallbackNonAuthoritative
  , TestCase $ assertRoundTrip "PreActorNoExecutableTool" PreActorNoExecutableTool
  ]

testPreActorFailureEventRT :: Test
testPreActorFailureEventRT = TestList
  [ TestCase $ assertRoundTrip "basic failure event" PreActorFailureEvent
    { pafeKind = PreActorTransportFailure
    , pafeActionKind = "http_request"
    , pafeReason = "connection_timeout"
    }
  , TestCase $ assertRoundTrip "failure event with unicode" PreActorFailureEvent
    { pafeKind = PreActorFallbackNonAuthoritative
    , pafeActionKind = "fallback_path"
    , pafeReason = "не удалось восстановить контекст"
    }
  ]

testEffectSnapshotRT :: Test
testEffectSnapshotRT = TestList
  [ TestCase $ assertRoundTrip "api healthy" EffectSnapshot { esApiHealthy = True }
  , TestCase $ assertRoundTrip "api unhealthy" EffectSnapshot { esApiHealthy = False }
  ]

testTurnFamilyDerivationStepRT :: Test
testTurnFamilyDerivationStepRT = TestList
  [ TestCase $ assertRoundTrip "contact step" TurnFamilyDerivationStep
    { tfdsLabel = "routing_contact"
    , tfdsFamily = CMContact
    }
  , TestCase $ assertRoundTrip "clarify step" TurnFamilyDerivationStep
    { tfdsLabel = "shadow_clarify"
    , tfdsFamily = CMClarify
    }
  ]

testGenerationAttemptRT :: Test
testGenerationAttemptRT = TestList
  [ TestCase $ assertRoundTrip "successful generation" GenerationAttempt
    { gaPath = "pgf_linearization"
    , gaOutcome = "success"
    }
  , TestCase $ assertRoundTrip "fallback generation" GenerationAttempt
    { gaPath = "haskell_fallback"
    , gaOutcome = "degraded_output"
    }
  ]

testCanonicalMoveFamilyRT :: Test
testCanonicalMoveFamilyRT = TestList
  [ TestCase $ assertRoundTrip "CMGround" CMGround
  , TestCase $ assertRoundTrip "CMDefine" CMDefine
  , TestCase $ assertRoundTrip "CMContact" CMContact
  , TestCase $ assertRoundTrip "CMClarify" CMClarify
  , TestCase $ assertRoundTrip "CMConfront" CMConfront
  ]

testIllocutionaryForceRT :: Test
testIllocutionaryForceRT = TestList
  [ TestCase $ assertRoundTrip "IFAsk" IFAsk
  , TestCase $ assertRoundTrip "IFAssert" IFAssert
  , TestCase $ assertRoundTrip "IFOffer" IFOffer
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
  ]

testShadowDivergenceSeverityRT :: Test
testShadowDivergenceSeverityRT = TestList
  [ TestCase $ assertRoundTrip "ShadowSeverityClean" ShadowSeverityClean
  , TestCase $ assertRoundTrip "ShadowSeverityAdvisory" ShadowSeverityAdvisory
  , TestCase $ assertRoundTrip "ShadowSeveritySafety" ShadowSeveritySafety
  ]

testShadowSnapshotIdRT :: Test
testShadowSnapshotIdRT = TestList
  [ TestCase $ assertRoundTrip "snapshot id" (ShadowSnapshotId "snap-001")
  ]

testFmarModeRT :: Test
testFmarModeRT = TestList
  [ TestCase $ assertRoundTrip "FmarShadow" FmarShadow
  , TestCase $ assertRoundTrip "FmarLive" FmarLive
  ]
