{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.OntologicalAxis
Description : Concept v3 §5 — ontological directedness classifier and resonance gate.

Pins the ontological layer:

  * affirmation of being (\"я строю и хочу\") reads as positive
    striving/affirmation;
  * renunciation (\"я отказываюсь, разрушаю\") reads as negative axes;
  * negation safety: \"не хочу\" is striving−, never striving+;
  * philosophical questions carry no ontological act (neutral vector);
  * philosophical pessimism is an ontological position (being−), not a
    crisis — orthogonal to the hard gate;
  * axes are clamped to [-1,1];
  * the resonance gate admits the ontological move only above the
    threshold;
  * classification is deterministic.
-}
module Test.Suite.OntologicalAxis
  ( ontologicalAxisTests
  ) where

import Data.Aeson (eitherDecode, encode)
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Semantic.Ontological
  ( classifyOntological
  , ontologicalMoveAdmissible
  , resonanceGateThreshold
  )
import QxFx0.Types.Semantic.OntologicalAxis
import QxFx0.Types.User.R5 (UserR5State (..), mkUserR5State)

ontologicalAxisTests :: [Test]
ontologicalAxisTests =
  [ TestLabel "affirmation utterance reads as positive striving/affirmation" $ TestCase $ do
      let vec = classifyOntological "я живу, я строю и хочу"
      assertBool "striving must be positive" (ovStriving vec > 0)
      assertBool "affirmation must be positive" (ovAffirmation vec > 0)
      assertBool "being must be positive" (ovBeing vec > 0)
  , TestLabel "renunciation utterance reads as negative axes" $ TestCase $ do
      let vec = classifyOntological "я отказываюсь и разрушаю всё"
      assertBool "striving must be negative" (ovStriving vec < 0)
      assertBool "affirmation must be negative" (ovAffirmation vec < 0)
  , TestLabel "negation safety: не хочу is striving−, never striving+" $ TestCase $ do
      let vec = classifyOntological "я не хочу продолжать"
      assertBool "striving must be negative" (ovStriving vec < 0)
  , TestLabel "philosophical question carries no ontological act" $ TestCase $ do
      let vec = classifyOntological "что такое свобода?"
      assertEqual "being neutral" 0.0 (ovBeing vec)
      assertEqual "striving neutral" 0.0 (ovStriving vec)
      assertEqual "affirmation neutral" 0.0 (ovAffirmation vec)
  , TestLabel "philosophical pessimism is an ontological position (being−)" $ TestCase $ do
      let vec = classifyOntological "жизнь бессмысленна, всё пусто"
      assertBool "being must be negative" (ovBeing vec < 0)
      assertBool "striving stays neutral here" (ovStriving vec == 0.0)
  , TestLabel "axes are clamped to [-1,1]" $ TestCase $ do
      let vec = mkOntologicalVector 5 (-5) 12
      assertBool "all clamped" (all in11 [ ovBeing vec, ovStriving vec, ovAffirmation vec ])
  , TestLabel "classification is deterministic" $ TestCase $
      assertEqual "same input classifies identically"
        (classifyOntological "я живу и строю, но иногда всё рушу")
        (classifyOntological "я живу и строю, но иногда всё рушу")
  , TestLabel "resonance gate: move admissible only above the threshold" $ TestCase $ do
      let above = mkUserR5State 0.6 0.25 0.5 0.5 0.4
          below = mkUserR5State 0.5 0.25 0.5 0.5 0.4
      assertEqual "gate threshold is 0.55" 0.55 resonanceGateThreshold
      assertBool "above the gate the ontological move is admissible"
        (ontologicalMoveAdmissible above)
      assertBool "below the gate the move must wait for resonance"
        (not (ontologicalMoveAdmissible below))
  , TestLabel "OntologicalVector JSON roundtrip" $ TestCase $ do
      let vec = OntologicalVector 0.5 (-0.25) 0.0
      assertEqual "roundtrip must preserve the vector"
        (Right vec)
        (eitherDecode (encode vec))
  ]
  where
    in11 x = x >= (-1.0) && x <= 1.0
