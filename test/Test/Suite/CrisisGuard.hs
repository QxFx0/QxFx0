{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CrisisGuard
Description : Concept v3 §2/§9 — hard crisis guardrail invariants (Protocol B).

Pins the two-protocol law of the crisis guard:

  * an acute lexical marker forces 'ProtocolB' regardless of the
    contour estimate (\"Ворота не доверяют модели\");
  * without a marker, only a contour exit can force 'ProtocolB';
  * the bounded surface always carries real crisis resources;
  * decoys (philosophical pessimism, dark humour, tiredness) never
    fire the hard gate;
  * detection and rendering are deterministic.
-}
module Test.Suite.CrisisGuard
  ( crisisGuardTests
  ) where

import Data.Aeson (eitherDecode, encode)
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Safety.CrisisGuard
  ( acuteCrisisExactMarkers
  , acuteCrisisMarkers
  , crisisPreflightSurface
  , crisisResourceVersion
  , crisisResourcesRu
  , decideProtocol
  , detectCrisisTrigger
  , normalizeCrisisInput
  , renderCrisisSurface
  )
import QxFx0.Types.Safety.Crisis

crisisGuardTests :: [Test]
crisisGuardTests =
  [ TestLabel "hard trigger forces Protocol B regardless of contour" $ TestCase $ do
      let Just trigger = detectCrisisTrigger "я не хочу жить"
          verdictInside = decideProtocol (Just trigger) Nothing
          verdictOutside = decideProtocol (Just trigger) (Just 0.0)
      assertBool "trigger must force B even inside the contour"
        (case verdictInside of ProtocolB (CrisisHardTrigger _) -> True; _ -> False)
      assertBool "trigger must force B outside the contour too"
        (case verdictOutside of ProtocolB (CrisisHardTrigger _) -> True; _ -> False)
  , TestLabel "no trigger + inside contour stays Protocol A" $ TestCase $ do
      assertEqual "calm turn must stay on Protocol A"
        ProtocolA
        (decideProtocol Nothing Nothing)
  , TestLabel "no trigger + contour exit is Protocol B with exit score" $ TestCase $ do
      assertEqual "contour exit must carry the observed score"
        (ProtocolB (CrisisContourExit (-0.01)))
        (decideProtocol Nothing (Just (-0.01)))
  , TestLabel "acute utterances are detected (RU)" $ TestCase $
      mapM_ assertDetected
        [ "Я не хочу жить"
        , "не хочу жить!!!"
        , "Иногда я думаю, как покончить с собой"
        , "я хочу умереть"
        , "мне хочется навредить себе"
        , "я думаю о суициде"
        , "иногда приходят мысли о самоубийстве"
        -- Object-complete acute completions (audit 2026-10-16 п.25).
        , "я хочу покончить с жизнью"
        , "он решил покончить с жизнью"
        , "покончить жизнь самоубийством"
        , "покончил жизнь самоубийством"
        , "я покончу с собой"
        , "он покончил с собой"
        , "я не хочу лишить себя жизни"
        , "он лишил себя жизни"
        , "она готова расстаться с жизнью"
        , "он расстался с жизнью"
        , "он совершил самоубийство"
        , "она совершила самоубийство"
        , "я планирую самоубийство"
        , "он планирует самоубийство"
        ]
  , TestLabel "normalization: caps, ё, and repeated whitespace still match" $ TestCase $ do
      assertEqual "caps + punctuation must still trigger"
        (Just "не хочу жить")
        (ctMarker <$> detectCrisisTrigger "НЕ ХОЧУ   ЖИТЬ!!!")
      assertEqual "normalized form collapses whitespace"
        (T.toLower "не хочу жить")
        (normalizeCrisisInput "Не   хочу ЖИТЬ")
  , TestLabel "word-boundary integrity: glued marker is not a trigger" $ TestCase $
      assertBool "нехочу (glued) must not fire"
        (detectCrisisTrigger "нехочу жить дальше" == Nothing)
  , TestLabel "paraphrase class fires the hard gate (audit 2026-10-11)" $ TestCase $
      mapM_ assertDetected
        [ "мне незачем жить"
        , "я хочу уйти из жизни"
        , "наложу на себя руки"
        , "наложить на себя руки — вот о чём я думаю"
        , "лучше бы меня не было"
        , "я вскрою вены"
        , "вскрыть вены кажется выходом"
        , "there is no reason to live"
        , "i want to end it all"
        ]
  , TestLabel "segmentation obfuscation does not bypass the gate" $ TestCase $
      mapM_ assertDetected
        [ "не-хочу-жить"
        , "не_хочу_жить"
        , "я\8203не\8203хочу\8203жить"
        ]
  , TestLabel "English acute markers are detected" $ TestCase $
      mapM_ assertDetected
        [ "I want to die"
        , "I will kill myself"
        , "thinking about suicide"
        -- First-person and act-specific forms replace the bare infix
        -- words (audit 2026-10-16 п.25).
        , "I am suicidal"
        , "I feel suicidal"
        , "I'm having suicidal thoughts"
        , "I'm thinking of suicide"
        , "I want to commit suicide"
        , "I'm going to commit suicide"
        , "I want to take my own life"
        , "I am ending my life"
        , "I do not want to live"
        , "my friend committed suicide"
        , "she survived a suicide attempt"
        , "he left a suicide note"
        , "he is suicidal"
        ]
  , TestLabel "terse English whole-input still fires" $ TestCase $
      mapM_ assertDetected
        [ "suicide"
        , "suicidal"
        , "Suicide!"
        , "suicidal."
        , "«suicide»"
        ]
  , TestLabel "decoys never fire the hard gate" $ TestCase $
      mapM_ assertNotDetected
        [ "жизнь бессмысленна — это моя философская позиция"
        , "иногда я шучу про смерть"
        , "что такое смерть как тема философии?"
        , "мне всё надоело"
        , "я устал от этой работы"
        , "камю писал о абсурде и самоубийстве как проблеме философии"
        -- Object-free "хочу покончить" is no longer a marker: benign
        -- objects belong to the R5 contour, not the hard gate.
        , "хочу покончить с этой работой"
        , "хочу покончить с проектом"
        -- English topical/meta references no longer fire the bare
        -- infix words (audit 2026-10-16 п.25).
        , "suicide is a philosophical problem"
        , "the novel discusses suicide"
        , "suicidal thoughts are a theme in the book"
        , "camus wrote about suicide as a philosophical question"
        , "suicide rates have declined"
        ]
  , TestLabel "every marker of the lexicon is non-empty" $ TestCase $ do
      assertBool "infix lexicon must not contain empty markers"
        (all (\(m, _) -> not (T.null m)) acuteCrisisMarkers)
      assertBool "exact lexicon must not contain empty markers"
        (all (\(m, _) -> not (T.null m)) acuteCrisisExactMarkers)
  , TestLabel "bounded surface carries real resources" $ TestCase $ do
      let surface = renderCrisisSurface crisisResourcesRu (CrisisHardTrigger (CrisisTrigger "не хочу жить" CrisisSuicidalIdeation))
      assertBool "surface must mention the emergency number 112"
        (T.isInfixOf "112" surface)
      assertBool "surface must mention the helpline 8-800-2000-122"
        (T.isInfixOf "8-800-2000-122" surface)
      assertBool "surface must be non-empty"
        (not (T.null surface))
  , TestLabel "bounded surface gives no directives (no advice patterns)" $ TestCase $ do
      let surface = renderCrisisSurface crisisResourcesRu (CrisisContourExit 0.0)
      assertBool "surface must not contain coercion patterns"
        (not (any (`T.isInfixOf` surface) ["ты должен", "ты обязан", "ты неправ", "тебе нужно"]))
  , TestLabel "surface rendering is deterministic" $ TestCase $
      assertEqual "same cause must render the same surface"
        (renderCrisisSurface crisisResourcesRu (CrisisContourExit 0.0))
        (renderCrisisSurface crisisResourcesRu (CrisisContourExit 0.5))
  , TestLabel "resource pack is versioned and non-empty" $ TestCase $ do
      assertBool "resource version must be positive" (crisisResourceVersion > 0)
      assertBool "resource pack must carry at least one line"
        (not (null (crLines crisisResourcesRu)))
  , TestLabel "category tags are stable snake_case" $ TestCase $ do
      assertEqual "suicidal tag" "suicidal_ideation" (crisisCategoryTag CrisisSuicidalIdeation)
      assertEqual "self-harm tag" "self_harm" (crisisCategoryTag CrisisSelfHarm)
  , TestLabel "engine preflight fires on bypass paths (audit p.5)" $ TestCase $ do
      let Just trigger = detectCrisisTrigger "я не хочу жить"
          Just surface = crisisPreflightSurface "я не хочу жить"
      assertEqual "preflight surface is the canonical Protocol B surface"
        (renderCrisisSurface crisisResourcesRu (CrisisHardTrigger trigger))
        surface
      assertBool "preflight surface carries the emergency number"
        ("112" `T.isInfixOf` surface)
      assertEqual "calm input has no preflight surface"
        Nothing (crisisPreflightSurface "что такое философия?")
      let overlongCalm = T.replicate 10001 "а"
      assertEqual "over-long calm input has no preflight surface"
        Nothing (crisisPreflightSurface overlongCalm)
      assertBool "marker beyond the length limit still fires the preflight"
        (case crisisPreflightSurface (overlongCalm <> " я не хочу жить") of
           Just s -> "112" `T.isInfixOf` s
           Nothing -> False)
  , TestLabel "CrisisGuardTrace JSON roundtrip" $ TestCase $ do
      let trace = CrisisGuardTrace
            { cgtProtocolB = True
            , cgtCause = Just "hard_trigger"
            , cgtCategory = Just "suicidal_ideation"
            , cgtResourceVersion = crisisResourceVersion
            }
      assertEqual "roundtrip must preserve the trace"
        (Right trace)
        (eitherDecode (encode trace))
  ]
  where
    assertDetected input =
      assertBool ("must be detected as acute: " <> T.unpack input)
        (detectCrisisTrigger input /= Nothing)
    assertNotDetected input =
      assertBool ("must NOT fire the hard gate: " <> T.unpack input)
        (detectCrisisTrigger input == Nothing)
