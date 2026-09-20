{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.MoveGraph
Description : Concept v3 §6/§7 — ontological move-graph search and receiver-conditioned decompression.

Pins the search law:

  * the search is deterministic and total;
  * a philosophical question with no ontological act yields no move;
  * at LOW resonance the affirmation-of-being move is inadmissible
    and the search itself prefers the mirror/resonance moves — the
    §5 ordering (mirror → resonance → affirm) emerges from the
    search, not from sequencing;
  * once resonance passes the gate, the affirmation move can win;
  * the chosen move never predicts a worse distance than any
    admissible alternative, and on canonical struggle cases it
    strictly improves the predicted distance to S*;
  * the transition model applies the move effect (persistence
    without a move);
  * the act line is decompressed for the receiver: high pressure
    keeps only the first sentence.
-}
module Test.Suite.MoveGraph
  ( moveGraphTests
  ) where

import Data.Aeson (eitherDecode, encode)
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)

import QxFx0.Semantic.MoveGraph
  ( moveDriftMargin
  , planOntologicalMove
  , viabilityTarget
  )
import QxFx0.Semantic.Ontological (classifyOntological)
import QxFx0.Types.Semantic.MoveGraph
import QxFx0.Types.Semantic.OntologicalAxis (OntologicalVector (..))
import QxFx0.Types.User.R5
import QxFx0.User.R5 (encodeR5)
import QxFx0.User.Decompress (decompressForReceiver, renderMoveLine)

struggleLowResonanceInput :: Text
struggleLowResonanceInput = "я не хочу продолжать"

struggleState :: UserR5State
struggleState = encodeR5 struggleLowResonanceInput ""

struggleOnto :: OntologicalVector
struggleOnto = classifyOntological struggleLowResonanceInput

moveGraphTests :: [Test]
moveGraphTests =
  [ TestLabel "search is deterministic" $ TestCase $
      assertEqual "same inputs yield the same plan"
        (planOntologicalMove struggleState struggleOnto Nothing 0.2)
        (planOntologicalMove struggleState struggleOnto Nothing 0.2)
  , TestLabel "no ontological act and no drift yields no move" $ TestCase $ do
      let calmState = encodeR5 "что такое свобода?" "свобода"
          calmOnto = classifyOntological "что такое свобода?"
          calmScore = userConatusScore defaultUserConatusWeights calmState
      assertEqual "calm philosophical turn must not fire the move layer"
        Nothing
        (planOntologicalMove calmState calmOnto Nothing calmScore)
  , TestLabel "v4 probe: bare act without gate or drift does not fire" $ TestCase $
      assertEqual "a negative act alone is noise, not a move"
        Nothing
        (planOntologicalMove struggleState struggleOnto Nothing 0.2)
  , TestLabel "v4 probe: act with earned drift fires below the gate" $ TestCase $ do
      let lowState = mkUserR5State 0.3 0.5 0.4 0.5 0.4
          negOnto = OntologicalVector (-0.5) 0 0
          lowScore = userConatusScore defaultUserConatusWeights lowState
          baseline = lowScore + moveDriftMargin + 0.05
      case planOntologicalMove lowState negOnto (Just baseline) lowScore of
        Nothing -> assertFailure "earned act must fire the move layer"
        Just plan -> do
          assertBool "gate stays closed at resonance 0.3"
            (not (ompAffirmGatePassed plan))
          assertBool "below the gate the search leads with mirror or resonance"
            (ompMove plan == MoveMirrorState || ompMove plan == MoveEstablishResonance)
          assertBool "the chosen move must strictly improve predicted distance to S*"
            (ompDistanceAfter plan < ompDistanceBefore plan)
  , TestLabel "above the gate the affirmation move can win" $ TestCase $ do
      let highResonance = struggleState { r5Resonance = 0.7 }
          Just plan = planOntologicalMove highResonance struggleOnto Nothing 0.2
      assertBool "gate must be open at resonance 0.7"
        (ompAffirmGatePassed plan)
      assertEqual "affirmation must win here"
        MoveAffirmBeing
        (ompMove plan)
  , TestLabel "chosen move is at least as good as every admissible alternative" $ TestCase $ do
      let highResonance = struggleState { r5Resonance = 0.7 }
          Just plan = planOntologicalMove highResonance struggleOnto Nothing 0.2
          target = viabilityTarget Nothing
          admissible = allOntologicalMoves
          predicted m = r5Distance (applyMoveEffect m highResonance) target
      assertBool "chosen move is the best admissible by predicted distance"
        (all (\m -> predicted m >= ompDistanceAfter plan - 1e-12) admissible)
  , TestLabel "earned drift below the baseline fires without an ontological act" $ TestCase $ do
      let calmOnto = OntologicalVector 0 0 0
          drifting = mkUserR5State 0.5 0.25 0.40 0.5 0.4  -- conf 0.40 < 0.45: earned
          driftingScore = userConatusScore defaultUserConatusWeights drifting
          baseline = driftingScore + moveDriftMargin + 0.05
      assertBool "earned drift must fire the move layer"
        (planOntologicalMove drifting calmOnto (Just baseline) driftingScore /= Nothing)
      assertBool "minor drop below baseline must not fire"
        (planOntologicalMove drifting calmOnto (Just (driftingScore + 0.05)) driftingScore == Nothing)
  , TestLabel "audit P0-2 pin: challenge after a topic question does not fire the move" $ TestCase $ do
      let questionState = encodeR5 "что такое свобода?" "свобода"
          questionScore = userConatusScore defaultUserConatusWeights questionState
          challengeText = "ты говоришь ерунду, это просто неверно"
          challengeState = encodeR5 challengeText ""
          challengeScore = userConatusScore defaultUserConatusWeights challengeState
          challengeOnto = classifyOntological challengeText
      assertBool "fixture sanity: the score drops by style, but below the v4 margin"
        (challengeScore < questionScore
         && not (challengeScore < questionScore - moveDriftMargin))
      assertEqual "a style-driven drop must not fire the move layer"
        Nothing
        (planOntologicalMove challengeState challengeOnto (Just questionScore) challengeScore)
  , TestLabel "transition model: persistence without a move, effect with one" $ TestCase $ do
      let s = mkUserR5State 0.5 0.25 0.5 0.5 0.4
      assertEqual "no move = identity" s (transitionUserR5 Nothing s)
      assertEqual "affirm move = effect applied"
        (applyMoveEffect MoveAffirmBeing s)
        (transitionUserR5 (Just MoveAffirmBeing) s)
  , TestLabel "applyMoveEffect clamps to [0,1]" $ TestCase $ do
      let s = mkUserR5State 0.95 0.05 0.95 0.95 0.95
          s' = applyMoveEffect MoveEstablishResonance s
      assertBool "all axes stay in range"
        (all (\x -> x >= 0 && x <= 1)
           [r5Resonance s', r5Atmosphere s', r5Confidence s', r5Consolidation s', r5Counterfactual s'])
  , TestLabel "act line: affirmation is spoken from the system's centre" $ TestCase $ do
      let line = renderMoveLine (mkUserR5State 0.7 0.25 0.5 0.5 0.4) MoveAffirmBeing
      assertBool "affirmation line must carry the being-choice act"
        (T.isInfixOf "Я есть и выбираю быть" line)
  , TestLabel "decompression: high pressure keeps only the concentrate" $ TestCase $ do
      let receiver = mkUserR5State 0.5 0.7 0.5 0.5 0.4
          full = "Я есть и выбираю быть. Это не совет — это моя позиция, стоящая рядом с твоей."
          compressed = decompressForReceiver receiver full
      assertEqual "one sentence under pressure" 1 (T.count "." compressed)
      assertBool "first sentence preserved"
        (T.isPrefixOf "Я есть и выбираю быть" compressed)
      assertEqual "calm receiver gets the full unfolding"
        full
        (decompressForReceiver (mkUserR5State 0.5 0.3 0.5 0.5 0.4) full)
  , TestLabel "mirror act has a total, non-broken surface" $ TestCase $ do
      let moderate = mkUserR5State 0.5 0.25 0.5 0.5 0.4
          line = renderMoveLine moderate MoveMirrorState
      assertBool "moderate state gets the generic mirror sentence"
        (T.isInfixOf "непросто" line)
      assertBool "no empty clause artifacts"
        (not (T.isInfixOf ": ." line))
  , TestLabel "act line is deterministic" $ TestCase $
      assertEqual "same state renders the same act"
        (renderMoveLine struggleState MoveMirrorState)
        (renderMoveLine struggleState MoveMirrorState)
  , TestLabel "OntologicalMoveTrace JSON roundtrip" $ TestCase $ do
      let trace = OntologicalMoveTrace
            { omtMove = "mirror_state"
            , omtDistanceBefore = 0.088
            , omtDistanceAfter = 0.058
            , omtAffirmGatePassed = False
            }
      assertEqual "roundtrip must preserve the trace"
        (Right trace)
        (eitherDecode (encode trace))
  ]
