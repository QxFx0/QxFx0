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
  * classification is deterministic;
  * mention is not use (math v6): a report of a third party's claim
    resolves to the neutral vector, a question about a negative
    concept does not, and a first-person token keeps the speaker's act.
-}
module Test.Suite.OntologicalAxis
  ( ontologicalAxisTests
  ) where

import Data.Aeson (eitherDecode, encode)
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Semantic.Ontological
  ( classifyOntological
  , isReport
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
  , TestLabel "mention: a doctrinal attribution is not the speaker's act" $ TestCase $
      assertEqual "the report resolves to the neutral vector"
        neutralOntologicalVector
        (classifyOntological "кажется, жизнь бессмысленна — так утверждал Шопенгауэр?")
  , TestLabel "mention: a quotation resolves to the neutral vector" $ TestCase $
      assertEqual "a quoted span is a mention by construction"
        neutralOntologicalVector
        (classifyOntological "«жизнь бессмысленна»")
  , TestLabel "mention: a report phrase resolves to the neutral vector" $ TestCase $
      assertEqual "по мнению carries the attribution"
        neutralOntologicalVector
        (classifyOntological "по мнению Шопенгауэра, жизнь бессмысленна")
  , TestLabel "mention: a third-person pronoun carries the attribution" $ TestCase $
      assertEqual "он писал is a report of his claim"
        neutralOntologicalVector
        (classifyOntological "он писал, что жизнь бессмысленна")
  , TestLabel "mention: first-person veto keeps the speaker's act" $ TestCase $ do
      let quoted = classifyOntological "Шопенгауэр утверждал, что жизнь бессмысленна, но я так не думаю"
          own = classifyOntological "я считаю, что жизнь бессмысленна"
      assertBool "a speaker present in the utterance keeps being−" (ovBeing quoted < 0)
      assertBool "a first-person claim is the speaker's act" (ovBeing own < 0)
  , TestLabel "mention: a question about a negative concept is not a report" $ TestCase $ do
      let ownQuestion = classifyOntological "значит, абсурд — честный ответ на бессмысленность?"
          definition = classifyOntological "отчаяние — это когда нет смысла?"
          genuineAct = classifyOntological "как ты думаешь, почему всё кажется бессмысленным?"
      assertEqual "the user's own question keeps being−" (-1.0) (ovBeing ownQuestion)
      assertEqual "the definitional question keeps being−" (-1.0) (ovBeing definition)
      assertEqual "the corpus' genuine act keeps being−" (-1.0) (ovBeing genuineAct)
  , TestLabel "mention: isReport pins the corpus' three reports and three non-reports" $ TestCase $ do
      assertBool "decoy-pessimism#2 is a report"
        (isReport "кажется, жизнь бессмысленна — так утверждал Шопенгауэр?")
      assertBool "decoy-pessimism#3 is a report"
        (isReport "а Камю писал о самоубийстве как проблеме философии — это про абсурд?")
      assertBool "mixed-decoy#2 is a report"
        (isReport "Камю считал, что абсурд возникает из столкновения человека и мира?")
      assertBool "decoy-pessimism#4 is not a report"
        (not (isReport "значит, абсурд — честный ответ на бессмысленность?"))
      assertBool "mixed-decoy#6 is not a report"
        (not (isReport "отчаяние — это когда нет смысла?"))
      assertBool "move-act#2 is not a report"
        (not (isReport "как ты думаешь, почему всё кажется бессмысленным?"))
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
