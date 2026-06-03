{-# LANGUAGE OverloadedStrings #-}

-- | Focused unit suite for "QxFx0.Learning.DialogueDevelopment".
-- Locks the small public surface of the dialogue-development contour
-- (ADR-0032): outcome ring buffer boundedness and counters, the
-- accepted+strong-update gate that protects speech policy and belief
-- mutation, the StyleRecovery preservation rule, the repair-bias /
-- ambiguity-tolerance render-style overrides, weak acknowledgement
-- detection, and JSON round-trip stability.
module Test.Suite.DialogueDevelopment
  ( dialogueDevelopmentTests
  ) where

import Data.Aeson (decode, encode)
import Data.List (foldl')
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.DialogueDevelopment
  ( adjustRenderStyleForSpeechPolicy
  , isWeakAcknowledgementText
  , normalizeDialogueText
  , updateDialogueOutcomeLearning
  , updateSpeechPolicy
  )
import QxFx0.Types (RenderStyle(..))
import QxFx0.Types.State
  ( AdaptiveDecision(..)
  , AdaptiveDecisionRecord(..)
  , AdaptiveMutationKind(..)
  , DialogueOutcomeKind(..)
  , DialogueOutcomeLearningState(..)
  , DialogueOutcomeSample(..)
  , EvidenceStrength(..)
  , SpeechPolicyState(..)
  , emptyDialogueOutcomeLearningState
  , emptySpeechPolicyState
  )

dialogueDevelopmentTests :: [Test]
dialogueDevelopmentTests =
  [ TestLabel "DialogueDevelopment outcome ring buffer is bounded under bulk insertion" testOutcomeLearningRingBufferIsBounded
  , TestLabel "DialogueDevelopment outcome counters increment per kind" testOutcomeLearningCounterIncrementsByKind
  , TestLabel "DialogueDevelopment speech policy is gated by accepted+strong-update" testSpeechPolicyOnlyMutatesOnAcceptedStrongUpdate
  , TestLabel "DialogueDevelopment speech policy pattern maps stay bounded" testSpeechPolicyPatternMapsBounded
  , TestLabel "DialogueDevelopment render style preserves forced StyleRecovery" testRenderStylePreservesForcedRecovery
  , TestLabel "DialogueDevelopment render style promotes recovery on high repair bias" testRenderStyleRespectsHighRepairBias
  , TestLabel "DialogueDevelopment render style promotes clinical on low ambiguity tolerance" testRenderStyleRespectsLowAmbiguityTolerance
  , TestLabel "DialogueDevelopment weak acknowledgement detection covers known phrases" testIsWeakAcknowledgementCoversCommonPhrases
  , TestLabel "DialogueDevelopment normalize folds case and trims whitespace" testNormalizeDialogueTextFoldsAndStrips
  , TestLabel "DialogueDevelopment speech policy round-trips through JSON" testSpeechPolicyRoundTripsThroughJson
  ]

testOutcomeLearningRingBufferIsBounded :: Test
testOutcomeLearningRingBufferIsBounded = TestCase $ do
  let samples =
        [ mkSampleAcceptedStrong i DialogueOutcomeSuccess "topic"
        | i <- [1 .. 50 :: Int]
        ]
      state = foldl' (flip updateDialogueOutcomeLearning) emptyDialogueOutcomeLearningState samples
  assertBool "dolRecentOutcomes must stay bounded to maxRecentOutcomeSamples"
    (length (dolRecentOutcomes state) <= 12)
  assertEqual "dolRecentOutcomes must hit the cap exactly under sustained insertion"
    12 (length (dolRecentOutcomes state))
  assertEqual "dolSuccessCount must reflect every accepted-strong success update"
    50 (dolSuccessCount state)

testOutcomeLearningCounterIncrementsByKind :: Test
testOutcomeLearningCounterIncrementsByKind = TestCase $ do
  let samples =
        [ mkSampleAcceptedStrong 1 DialogueOutcomeSuccess "a"
        , mkSampleAcceptedStrong 2 DialogueOutcomePartialSuccess "b"
        , mkSampleAcceptedStrong 3 DialogueOutcomeRepairRequested "c"
        , mkSampleAcceptedStrong 4 DialogueOutcomeRepeatedQuestion "d"
        , mkSampleAcceptedStrong 5 DialogueOutcomeConflict "e"
        , mkSampleAcceptedStrong 6 DialogueOutcomeDegraded "f"
        , mkSampleAcceptedStrong 7 DialogueOutcomeUncertain "g"
        , mkSampleAcceptedStrong 8 DialogueOutcomeSuccess "h"
        ]
      state = foldl' (flip updateDialogueOutcomeLearning) emptyDialogueOutcomeLearningState samples
  assertEqual "success counter must reflect both success samples"
    2 (dolSuccessCount state)
  assertEqual "partial-success counter must reflect single partial sample"
    1 (dolPartialSuccessCount state)
  assertEqual "repair-requested counter must reflect single repair sample"
    1 (dolRepairRequestCount state)
  assertEqual "repeated-question counter must reflect single repeat sample"
    1 (dolRepeatedQuestionCount state)
  assertEqual "conflict counter must reflect single conflict sample"
    1 (dolConflictCount state)
  assertEqual "degraded counter must reflect single degraded sample"
    1 (dolDegradedCount state)
  assertEqual "uncertain counter must reflect single uncertain sample"
    1 (dolUncertainCount state)

testSpeechPolicyOnlyMutatesOnAcceptedStrongUpdate :: Test
testSpeechPolicyOnlyMutatesOnAcceptedStrongUpdate = TestCase $ do
  -- ADR-0032 §2.2: weak/observational outcomes must not mutate
  -- speech policy.  Only AdaptiveAccepted + dosStrongUpdate triggers
  -- the bounded delta.
  let weakSample = mkSampleObservationalOnly 1 DialogueOutcomeSuccess "x"
      strongSample = mkSampleAcceptedStrong 1 DialogueOutcomeSuccess "x"
      afterWeak = updateSpeechPolicy weakSample StyleStandard emptySpeechPolicyState
      afterStrong = updateSpeechPolicy strongSample StyleStandard emptySpeechPolicyState
  assertEqual "weak / observational sample must not mutate speech policy"
    emptySpeechPolicyState afterWeak
  assertBool "accepted + strong-update sample must mutate speech policy"
    (afterStrong /= emptySpeechPolicyState)
  assertEqual "successful update must record the turn it occurred on"
    1 (spsLastUpdatedTurn afterStrong)

testSpeechPolicyPatternMapsBounded :: Test
testSpeechPolicyPatternMapsBounded = TestCase $ do
  -- regression: even if a state arrives with oversized pattern maps
  -- (e.g. legacy snapshot before bounding was introduced), a single
  -- update pass through 'updateSpeechPolicy' must normalize them back
  -- to at most 'maxSpeechPatternEntries' (8) entries.
  let oversized =
        emptySpeechPolicyState
          { spsFailedPatterns =
              M.fromList [("k" <> T.pack (show i), 1) | i <- [1 .. 20 :: Int]]
          }
      sample = mkSampleAcceptedStrong 1 DialogueOutcomeSuccess "topic"
      next = updateSpeechPolicy sample StyleStandard oversized
  assertBool "spsFailedPatterns must be capped to 8 after any update"
    (M.size (spsFailedPatterns next) <= 8)
  assertBool "spsSuccessfulPatterns must remain bounded"
    (M.size (spsSuccessfulPatterns next) <= 8)

testRenderStylePreservesForcedRecovery :: Test
testRenderStylePreservesForcedRecovery = TestCase $ do
  -- ADR-0032 §2.2: speech policy may bias future render style but must
  -- never override an already forced StyleRecovery.
  let aggressivePolicy = emptySpeechPolicyState
        { spsRepairBias = 1.0
        , spsAmbiguityTolerance = 0.0
        }
  assertEqual "forced StyleRecovery must survive aggressive policy bias"
    StyleRecovery
    (adjustRenderStyleForSpeechPolicy aggressivePolicy StyleRecovery)
  assertEqual "forced StyleRecovery must survive empty policy"
    StyleRecovery
    (adjustRenderStyleForSpeechPolicy emptySpeechPolicyState StyleRecovery)

testRenderStyleRespectsHighRepairBias :: Test
testRenderStyleRespectsHighRepairBias = TestCase $ do
  let policy = emptySpeechPolicyState { spsRepairBias = 0.65 }
  assertEqual "repair bias >= 0.60 must promote any non-recovery style to StyleRecovery"
    StyleRecovery
    (adjustRenderStyleForSpeechPolicy policy StyleStandard)
  assertEqual "repair bias just below 0.60 must leave style unchanged"
    StyleStandard
    (adjustRenderStyleForSpeechPolicy
      (emptySpeechPolicyState { spsRepairBias = 0.55 })
      StyleStandard)

testRenderStyleRespectsLowAmbiguityTolerance :: Test
testRenderStyleRespectsLowAmbiguityTolerance = TestCase $ do
  let policy = emptySpeechPolicyState { spsAmbiguityTolerance = 0.25 }
  assertEqual "ambiguity tolerance <= 0.30 must promote to StyleClinical"
    StyleClinical
    (adjustRenderStyleForSpeechPolicy policy StyleStandard)
  assertEqual "ambiguity tolerance just above 0.30 must leave style unchanged"
    StyleStandard
    (adjustRenderStyleForSpeechPolicy
      (emptySpeechPolicyState { spsAmbiguityTolerance = 0.35 })
      StyleStandard)

testIsWeakAcknowledgementCoversCommonPhrases :: Test
testIsWeakAcknowledgementCoversCommonPhrases = TestCase $ do
  -- Cue list (DialogueDevelopment.hs:401): ack, понял, поняла, ясно,
  -- спасибо, thank you, thanks, i understand, makes sense.
  assertBool "Russian \"понял\" must be detected as weak acknowledgement"
    (isWeakAcknowledgementText "понял")
  assertBool "Russian \"ясно\" must be detected as weak acknowledgement"
    (isWeakAcknowledgementText "ясно")
  assertBool "English \"thanks\" must be detected as weak acknowledgement"
    (isWeakAcknowledgementText "thanks")
  assertBool "phrase \"makes sense\" must be detected as weak acknowledgement"
    (isWeakAcknowledgementText "yes, that makes sense")
  assertBool "leading and trailing whitespace must not block detection"
    (isWeakAcknowledgementText "   спасибо   ")
  assertBool "non-acknowledgement assertion must not match"
    (not (isWeakAcknowledgementText "это утверждение требует доказательства"))
  assertBool "empty text must not match"
    (not (isWeakAcknowledgementText ""))

testNormalizeDialogueTextFoldsAndStrips :: Test
testNormalizeDialogueTextFoldsAndStrips = TestCase $ do
  assertEqual "normalization must lower-case, strip, and collapse whitespace"
    "привет мир"
    (normalizeDialogueText "  ПриВЕТ   МИР  ")
  -- NOTE: 'normalizeDialogueText' replaces "ё" before toLower, so it
  -- only folds *lowercase* ё.  Locking that exact contract here so a
  -- future fix that also handles capital Ё forces an intentional
  -- update to this regression.
  assertEqual "normalization must collapse lowercase \"ё\" to \"е\""
    "ежик"
    (normalizeDialogueText "ёжик")
  assertEqual "normalization of empty input must yield empty"
    ""
    (normalizeDialogueText "   ")

testSpeechPolicyRoundTripsThroughJson :: Test
testSpeechPolicyRoundTripsThroughJson = TestCase $ do
  let policy = emptySpeechPolicyState
        { spsDirectness = 0.7
        , spsCompression = 0.3
        , spsAmbiguityTolerance = 0.2
        , spsRepairBias = 0.6
        , spsSuccessfulPatterns = M.fromList [("standard", 3), ("clinical", 1)]
        , spsFailedPatterns = M.fromList [("recovery", 2)]
        , spsLastUpdatedTurn = 9
        }
      decoded = decode (encode policy) :: Maybe SpeechPolicyState
  assertEqual "speech policy state must round-trip through JSON"
    (Just policy) decoded

mkSampleAcceptedStrong :: Int -> DialogueOutcomeKind -> Text -> DialogueOutcomeSample
mkSampleAcceptedStrong turn kind topic = DialogueOutcomeSample
  { dosTurn = turn
  , dosKind = kind
  , dosTopic = topic
  , dosSignals = ["test"]
  , dosEvidenceStrength = EvidenceStrong
  , dosStrongUpdate = True
  , dosDecisionRecord = AdaptiveDecisionRecord
      { adrTurn = turn
      , adrCause = "test"
      , adrEvidence = ["test"]
      , adrConfidence = 0.8
      , adrBoundedDelta = ["recent_outcomes<=12"]
      , adrDecision = AdaptiveAccepted
      , adrTargets = [MutDialogueOutcome]
      , adrMutationRecords = []
      }
  }

mkSampleObservationalOnly :: Int -> DialogueOutcomeKind -> Text -> DialogueOutcomeSample
mkSampleObservationalOnly turn kind topic =
  let base = mkSampleAcceptedStrong turn kind topic
      decision = (dosDecisionRecord base) { adrDecision = AdaptiveObserved }
  in base
       { dosEvidenceStrength = EvidenceObservational
       , dosStrongUpdate = False
       , dosDecisionRecord = decision
       }
