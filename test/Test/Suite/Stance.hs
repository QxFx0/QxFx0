{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Stance (stanceTests) where

import Test.HUnit
import qualified Data.Set as S
import qualified Data.Map.Strict as M

import QxFx0.Types.State.Stance
import QxFx0.Semantic.Stance
import QxFx0.Semantic.Intent.Features (SemanticFeatures(..))
import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))

stanceTests :: [Test]
stanceTests =
  [ TestLabel "evidenceWeight" $ TestList
      [ TestCase $ do
          let sd = emptyStanceDefense { sdEvidenceSeen = S.fromList ["a", "b"] }
              challenge = S.fromList ["c", "d", "e", "f", "g"]
              weight = evidenceWeight sd challenge
          assertBool "novel atoms with high size relevance should give high weight" (weight > 0.5)

      , TestCase $ do
          let sd = emptyStanceDefense { sdEvidenceSeen = S.fromList ["a", "b", "c"] }
              challenge = S.fromList ["a", "b", "c"]
              weight = evidenceWeight sd challenge
          assertBool "all seen atoms should give weight = 1.0 (novelty = 0, argumentStrength = 0)" (weight == 1.0)

      , TestCase $ do
          let sd = emptyStanceDefense { sdEvidenceSeen = S.fromList ["a", "b"] }
              challenge = S.fromList ["a", "c", "d", "e", "f"]
              weight = evidenceWeight sd challenge
          assertBool "mixed atoms should give weight between 0.7 and 1.0" (weight > 0.7 && weight < 1.0)
      ]

  , TestLabel "defendOrAdapt" $ TestList
      [ TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceHeld 0.8 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challenge = S.fromList ["a", "b", "c", "d", "e"]
              result = defendOrAdapt sd conatus challenge
          case result of
            Left _ -> assertFailure "should not collapse"
            Right sd' -> assertBool "should remain Held or transition to Doubted"
              (case sdStance sd' of
                StanceHeld _ -> True
                StanceDoubted _ -> True
                _ -> False)

      , TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceDoubted 0.4 }
              conatus = ConatusEnergy 3.0 (ConatusComponents 0.75 0.75 0.75 0.75)
              challenge = S.fromList ["a", "b", "c", "d", "e"]
              result = defendOrAdapt sd conatus challenge
          case result of
            Left CollapseConatusExhausted -> return ()
            _ -> assertFailure "should collapse due to low conatus"

      , TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceDoubted 0.4, sdAttackCount = 5 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challenge = S.fromList ["a", "b", "c", "d", "e", "f"]
              result = defendOrAdapt sd conatus challenge
          case result of
            Left _ -> assertFailure "should not collapse"
            Right sd' -> assertBool "should revise with strong challenge"
              (case sdStance sd' of
                StanceRevised _ -> True
                _ -> False)
      ]

  , TestLabel "recoverStance" $ TestList
      [ TestCase $ do
          let sd = emptyStanceDefense
                { sdStance = StanceDoubted 0.4
                , sdRecoveryCounter = 5
                , sdRecoveryPolicy = RecoveryPolicy 5 0.1
                }
              sd' = recoverStance sd
          case sdStance sd' of
            StanceHeld conf -> assertBool "should recover to Held with boosted confidence" (conf >= 0.4)
            _ -> assertFailure "should transition to Held after recovery window"

      , TestCase $ do
          let sd = emptyStanceDefense
                { sdStance = StanceDoubted 0.4
                , sdRecoveryCounter = 3
                , sdRecoveryPolicy = RecoveryPolicy 5 0.1
                }
              sd' = recoverStance sd
          case sdStance sd' of
            StanceDoubted _ -> return ()
            _ -> assertFailure "should remain Doubted before recovery window"

      , TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceHeld 0.8 }
              sd' = recoverStance sd
          case sdStance sd' of
            StanceHeld _ -> return ()
            _ -> assertFailure "Held should remain Held"
      ]

  , TestLabel "stanceSimilarity" $ TestList
      [ TestCase $ do
          let a = S.fromList ["x", "y", "z"]
              b = S.fromList ["x", "y", "z"]
              sim = stanceSimilarity a b
          assertEqual "identical sets should have similarity 1.0" 1.0 sim

      , TestCase $ do
          let a = S.fromList ["x", "y"]
              b = S.fromList ["z", "w"]
              sim = stanceSimilarity a b
          assertEqual "disjoint sets should have similarity 0.0" 0.0 sim

      , TestCase $ do
          let a = S.fromList ["x", "y", "z"]
              b = S.fromList ["x", "y", "w"]
              sim = stanceSimilarity a b
          assertBool "partial overlap should have similarity between 0 and 1" (sim > 0 && sim < 1)
      ]

  , TestLabel "collapseThreshold" $ TestList
      [ TestCase $ do
          let threshold = collapseThreshold 0.0
          assertEqual "zero confidence should give threshold 2" 2 threshold

      , TestCase $ do
          let threshold = collapseThreshold 1.0
          assertEqual "full confidence should give threshold 6" 6 threshold

      , TestCase $ do
          let threshold = collapseThreshold 0.5
          assertEqual "mid confidence should give threshold 4" 4 threshold
      ]

  , TestLabel "extractUserStance" $ TestList
      [ TestCase $ do
          let features = SemanticFeatures
                { sfIsQuestion = False
                , sfHasNegation = False
                , sfHasContradiction = True
                , sfHasTwoConcepts = False
                , sfHasComparisonMark = False
                , sfHasDefinitionMark = False
                , sfHasChallengeMark = False
                , sfHasRepairMark = False
                , sfHasPurposeMark = False
                , sfHasWorldCauseMark = False
                , sfHasSelfReference = False
                , sfHasContactMark = False
                , sfHasDeepenMark = False
                , sfHasNextStepMark = False
                , sfHasGenerativeMark = False
                , sfHasExploratoryMark = False
                , sfHasAffectiveMark = False
                , sfHasOperationalMark = False
                , sfTopicComplexity = 0.0
                }
              atoms = S.fromList ["a", "b", "c"]
              turnSeq = TurnSeq 5
              stance = extractUserStance features atoms turnSeq
          assertEqual "challenge should have confidence 0.8" 0.8 (usConfidence stance)
          assertEqual "atoms should be preserved" atoms (usCommittedClaims stance)

      , TestCase $ do
          let features = SemanticFeatures
                { sfIsQuestion = True
                , sfHasNegation = False
                , sfHasContradiction = False
                , sfHasTwoConcepts = False
                , sfHasComparisonMark = False
                , sfHasDefinitionMark = False
                , sfHasChallengeMark = False
                , sfHasRepairMark = False
                , sfHasPurposeMark = False
                , sfHasWorldCauseMark = False
                , sfHasSelfReference = False
                , sfHasContactMark = False
                , sfHasDeepenMark = False
                , sfHasNextStepMark = False
                , sfHasGenerativeMark = False
                , sfHasExploratoryMark = False
                , sfHasAffectiveMark = False
                , sfHasOperationalMark = False
                , sfTopicComplexity = 0.0
                }
              atoms = S.fromList ["x", "y"]
              turnSeq = TurnSeq 3
              stance = extractUserStance features atoms turnSeq
          assertEqual "non-challenge should have confidence 0.5" 0.5 (usConfidence stance)
      ]

  , TestLabel "incrementRecoveryCounter" $ TestList
      [ TestCase $ do
          let sd = emptyStanceDefense { sdRecoveryCounter = 0 }
              sd' = incrementRecoveryCounter sd
          assertEqual "counter should increment from 0 to 1" 1 (sdRecoveryCounter sd')

      , TestCase $ do
          let sd = emptyStanceDefense { sdRecoveryCounter = 5 }
              sd' = incrementRecoveryCounter sd
          assertEqual "counter should increment from 5 to 6" 6 (sdRecoveryCounter sd')
      ]

  , TestLabel "reviseStance" $ TestList
      [ TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceHeld 0.8 }
              sd' = reviseStance sd "new position" (TurnSeq 1)
          case sdStance sd' of
            StanceDoubted conf -> do
              assertBool "high confidence (>0.7) should transition to Doubted" True
              assertBool "confidence should be reduced by 20%" (conf > 0.6 && conf < 0.7)
            _ -> assertFailure "should transition to Doubted, not Revised"

      , TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceHeld 0.5 }
              sd' = reviseStance sd "new position" (TurnSeq 1)
          case sdStance sd' of
            StanceRevised text -> do
              assertBool "low confidence (≤0.7) should transition to Revised" True
              assertEqual "should contain new position text" "new position" text
            _ -> assertFailure "should transition to Revised, not Doubted"

      , TestCase $ do
          let sd = emptyStanceDefense { sdStance = StanceHeld 0.7 }
              sd' = reviseStance sd "new position" (TurnSeq 1)
          case sdStance sd' of
            StanceRevised text -> do
              assertBool "exactly 0.7 confidence should transition to Revised" True
              assertEqual "should contain new position text" "new position" text
            _ -> assertFailure "should transition to Revised at threshold 0.7"
      ]
  ]
