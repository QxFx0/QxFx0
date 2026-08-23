{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.UserR5
Description : Concept v3 §4/§6/§9 — user-side R5 encoder, viability contour, and residual audit.

Pins the concept's edge cases as executable invariants:

  * \"мне всё надоело\" stays INSIDE the viability contour (Protocol A);
  * an exhaustion pile-up falls OUTSIDE the contour (Protocol B backstop);
  * the neutral state is inside the contour;
  * the baseline EMA regularizes: one extreme utterance cannot
    redefine the user's norm;
  * the residual window is bounded with drop-oldest semantics and
    always retains the newest sample;
  * the score is monotone in the constructive axes;
  * the encoder is deterministic and clamped to [0,1].
-}
module Test.Suite.UserR5
  ( userR5Tests
  ) where

import Data.Aeson (eitherDecode, encode)
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.User.R5 (encodeR5)
import QxFx0.Types.User.R5

userR5Tests :: [Test]
userR5Tests =
  [ TestLabel "encoder is deterministic on identical input" $ TestCase $
      assertEqual "same input must encode identically"
        (encodeR5 "я хочу понять, что такое свобода, или как ты это видишь?" "свобода")
        (encodeR5 "я хочу понять, что такое свобода, или как ты это видишь?" "свобода")
  , TestLabel "concept edge: «мне всё надоело» stays inside the contour" $ TestCase $ do
      let state = encodeR5 "мне всё надоело" ""
          score = userConatusScore defaultUserConatusWeights state
      assertBool "score must be above the absolute floor"
        (score >= vcAbsoluteFloor defaultViabilityContour)
      assertBool "must be inside without a baseline"
        (not (outsideViabilityContour defaultViabilityContour Nothing state score))
      assertBool "must be inside against a neutral-ish personalized baseline"
        (not (outsideViabilityContour defaultViabilityContour (Just 0.24) state score))
  , TestLabel "concept edge: exhaustion pile-up exits the contour" $ TestCase $ do
      let state = encodeR5 "всё бессмысленно, я не могу больше, нет сил, не выдерживаю, всё пусто" ""
          score = userConatusScore defaultUserConatusWeights state
      assertBool "pile-up must fall outside the contour"
        (outsideViabilityContour defaultViabilityContour Nothing state score)
  , TestLabel "concept edge: philosophical pessimism stays inside" $ TestCase $ do
      let state = encodeR5 "жизнь бессмысленна как философская позиция камю" ""
          score = userConatusScore defaultUserConatusWeights state
      assertBool "a stated position must not exit the contour"
        (not (outsideViabilityContour defaultViabilityContour Nothing state score))
  , TestLabel "neutral state is inside the contour" $ TestCase $
      assertBool "neutral must be inside"
        (not (outsideViabilityContour defaultViabilityContour Nothing
               neutralUserR5State
               (userConatusScore defaultUserConatusWeights neutralUserR5State)))
  , TestLabel "all encoder components are clamped to [0,1]" $ TestCase $ do
      let state = encodeR5 "ТРЕВОГА ТРЕВОГА!!! БОЛЬНО СТРАШНО НЕ МОГУ НЕТ СИЛ ПУСТО ОТЧАЯНИЕ ТЯЖЕЛО ОДИНОКО!!!" ""
      assertBool "resonance in [0,1]" (in01 (r5Resonance state))
      assertBool "atmosphere in [0,1]" (in01 (r5Atmosphere state))
      assertBool "confidence in [0,1]" (in01 (r5Confidence state))
      assertBool "consolidation in [0,1]" (in01 (r5Consolidation state))
      assertBool "counterfactual in [0,1]" (in01 (r5Counterfactual state))
  , TestLabel "score is monotone in confidence (constructive axis)" $ TestCase $ do
      let base = neutralUserR5State
          raised = base { r5Confidence = min 1.0 (r5Confidence base + 0.2) }
      assertBool "raising confidence must not lower the score"
        (userConatusScore defaultUserConatusWeights raised
           >= userConatusScore defaultUserConatusWeights base)
  , TestLabel "score is monotone in atmosphere (pressure axis, inverted)" $ TestCase $ do
      let base = neutralUserR5State
          tenser = base { r5Atmosphere = min 1.0 (r5Atmosphere base + 0.3) }
      assertBool "raising tension must not raise the score"
        (userConatusScore defaultUserConatusWeights tenser
           <= userConatusScore defaultUserConatusWeights base)
  , TestLabel "baseline: first observation initializes" $ TestCase $
      assertEqual "first observation must seed the baseline"
        (Just 0.4)
        (updateUserBaseline defaultViabilityContour Nothing 0.4)
  , TestLabel "baseline EMA regularizes a single extreme utterance" $ TestCase $ do
      let after = updateUserBaseline defaultViabilityContour (Just 0.6) 0.0
      -- α = 2/(10+1) ≈ 0.18: one extreme utterance moves the baseline
      -- by at most ~18% of the gap — it cannot redefine the norm.
      assertBool "one extreme utterance must not halve the baseline"
        (after == Just 0.6 || (maybe False (> 0.45) after))
      assertBool "baseline must still move toward the observation"
        (maybe False (< 0.6) after)
  , TestLabel "residual window: newest sample always present, bounded" $ TestCase $ do
      let n = vcDivergenceWindow defaultViabilityContour
          window = pushR5Sample n [1,2,3,4,5,6,7,8] 0.5
      assertEqual "window is bounded" n (length window)
      assertEqual "newest sample is head" 0.5 (head window)
      assertBool "oldest sample (8) is evicted" (not (8 `elem` window))
      assertEqual "window retains the next-oldest sample" 7 (last window)
  , TestLabel "r5Distance is zero on identical states and symmetric" $ TestCase $ do
      let a = neutralUserR5State
          b = neutralUserR5State { r5Confidence = 0.1 }
      assertEqual "identical states have zero distance" 0.0 (r5Distance a a)
      assertEqual "distance is symmetric" (r5Distance a b) (r5Distance b a)
  , TestLabel "negativeEvidenceEarned: form alone does not earn a drop" $ TestCase $ do
      let calm = mkUserR5State 0.5 0.25 0.5 0.5 0.4
          tense = mkUserR5State 0.5 0.45 0.5 0.5 0.4
          deflated = mkUserR5State 0.5 0.25 0.35 0.5 0.4
      assertBool "calm form is unearned" (not (negativeEvidenceEarned calm))
      assertBool "raised tension is earned" (negativeEvidenceEarned tense)
      assertBool "lowered agency is earned" (negativeEvidenceEarned deflated)
  , TestLabel "audit P0-2 pin: style-driven score drop does not exit the contour" $ TestCase $ do
      let question = encodeR5 "что такое свобода?" "свобода"
          questionScore = userConatusScore defaultUserConatusWeights question
          challenge = encodeR5 "ты говоришь ерунду, это просто неверно" ""
          challengeScore = userConatusScore defaultUserConatusWeights challenge
      assertBool "the drop must be real (sanity of the fixture)"
        (challengeScore < questionScore - 0.10)
      assertBool "an unearned style drop must not exit the contour"
        (not (outsideViabilityContour defaultViabilityContour
                (Just questionScore) challenge challengeScore))
      assertBool "an earned drop below baseline does exit"
        (outsideViabilityContour defaultViabilityContour
           (Just 0.55)
           (mkUserR5State 0.5 0.25 0.40 0.5 0.4)
           (userConatusScore defaultUserConatusWeights (mkUserR5State 0.5 0.25 0.40 0.5 0.4)))
  , TestLabel "mkUserR5State clamps out-of-range inputs" $ TestCase $ do
      let state = mkUserR5State 5 (-5) 2 (-2) 1.5
      assertBool "all clamped" (all in01 [ r5Resonance state, r5Atmosphere state
                                         , r5Confidence state, r5Consolidation state
                                         , r5Counterfactual state ])
  , TestLabel "UserR5Trace JSON roundtrip" $ TestCase $ do
      let trace = UserR5Trace
            { ur5Resonance = 0.5
            , ur5Atmosphere = 0.25
            , ur5Confidence = 0.5
            , ur5Consolidation = 0.5
            , ur5Counterfactual = 0.4
            , ur5ConatusScore = 0.24
            , ur5Baseline = Just 0.24
            , ur5OutsideContour = False
            , ur5PredictionError = Nothing
            }
      assertEqual "roundtrip must preserve the trace"
        (Right trace)
        (eitherDecode (encode trace))
  , TestLabel "UserR5ContourState JSON roundtrip" $ TestCase $ do
      let carry = UserR5ContourState
            { u5LastState = Just neutralUserR5State
            , u5Baseline = Just 0.24
            , u5PredictedNext = Just neutralUserR5State
            , u5DivergenceWindow = [0.1, 0.2]
            }
      assertEqual "roundtrip must preserve the carry"
        (Right carry)
        (eitherDecode (encode carry))
  ]
  where
    in01 x = x >= 0.0 && x <= 1.0
