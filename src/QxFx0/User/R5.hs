{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.User.R5
Description : observer — deterministic v1 linear encoder of the user utterance into UserR5State (concept v3 §4/§11).

The encoder decodes the system-human's state from its textual
signal: @encodeR5 input lastTopic@ maps one utterance plus the
topic-continuity bit onto 'UserR5State'.  It is the practical step 2 of
concept v3 §11: a /linear, interpretable/ model over features the
existing stack already extracts (lexical markers, question form,
topic continuity), not a perceptual network.

== Frozen v1 discipline

All constants below (bases, increments, marker lists) are hand-set
v1 and frozen at release — the deterministic-runtime contract.  The
concept's calibration loop (label 30–50 utterances, fit a linear
regression, audit residuals, refit) replaces these constants /offline/
and lands as a versioned model through the math-change protocol
(@currentMathVersion@ bump), never as a runtime weight update.  The
labelled set does not exist yet, so v1 is honest about being
heuristic; every axis is a documented linear feature sum.

== Negation handling

Russian negation traps (\"не хочу\" contains \"хочу\") are handled
by the replace-then-count trick: all negative phrases are counted
and blanked out of the text /before/ positive markers are counted,
so a negated positive can never leak into the positive count.

== Axis definitions (v1)

* Atmosphere (tension/pressure): distress lexicon hits, exclamation
  marks, shouting-case words over a calm 0.25 base.
* Confidence: agency-positive vs agency-negative phrases over a 0.5
  base.
* Resonance: question form, direct address to the system, topic
  continuity, over a 0.5 base.
* Consolidation: causal/connective discourse markers and topic
  continuity over a 0.5 base.
* Counterfactual: alternative markers and question form over a 0.4
  base.
-}
module QxFx0.User.R5
  ( r5EncoderVersion
  , encodeR5
    -- * Marker lexicons (exported for tests and audit)
  , r5DistressMarkers
  , r5AgencyNegativeMarkers
  , r5AgencyPositiveMarkers
  , r5ResonanceAddressMarkers
  , r5ConsolidationMarkers
  , r5CounterfactualMarkers
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.User.R5

-- | Version of the frozen encoder model.  Bump together with
-- @currentMathVersion@ when the offline fit replaces the hand-set
-- constants.
r5EncoderVersion :: Int
r5EncoderVersion = 1

r5DistressMarkers :: [Text]
r5DistressMarkers =
  [ "грустно", "тоскливо", "страшно", "тревожно", "плохо", "одиноко"
  , "устал", "устала", "больно", "тяжело", "бесит", "раздражает"
  , "не могу", "нет сил", "надоело", "выгорел", "выгорела"
  , "опустош", "отчаян", "безнадеж", "безнадёж", "бессмыслен"
  , "не выдерживаю", "не получается", "пусто", "давит"
  ]

r5AgencyNegativeMarkers :: [Text]
r5AgencyNegativeMarkers =
  [ "не хочу", "не буду", "не могу", "не смогу", "не получается"
  , "бесполезно", "безнадежно", "безнадёжно", "никогда не получится"
  , "надоело", "сдаюсь", "бросаю", "всё равно", "все равно"
  , "ничего не хочется", "не знаю зачем", "не выдерживаю", "нет сил"
  ]

r5AgencyPositiveMarkers :: [Text]
r5AgencyPositiveMarkers =
  [ "хочу", "могу", "смогу", "буду", "сделаю", "попробую", "выберу"
  , "стремлюсь", "ищу", "мечтаю", "намерен", "планирую", "решаю"
  ]

r5ResonanceAddressMarkers :: [Text]
r5ResonanceAddressMarkers =
  [ "ты можешь", "как ты", "а ты", "скажи", "ответь", "ты считаешь"
  , "ты думаешь", "по-твоему", "помоги мне понять"
  ]

r5ConsolidationMarkers :: [Text]
r5ConsolidationMarkers =
  [ "потому что", "значит", "следовательно", "итак", "поэтому"
  , "связано", "исходя из", "отсюда", "таким образом"
  ]

r5CounterfactualMarkers :: [Text]
r5CounterfactualMarkers =
  [ "или", "может быть", "а если", "что если", "другой", "другие"
  , "иначе", "вариант", "предположим", "альтернатива", "с другой стороны"
  ]

-- | Encode one utterance into an 'UserR5State'.  Total and
-- deterministic: a pure function of the input text and the topic
-- word.  Empty input decodes to 'neutralUserR5State'.
encodeR5 :: Text -> Text -> UserR5State
encodeR5 rawInput lastTopic =
  let norm = normalizeText rawInput
      topicHit =
        not (T.null lastTopic)
          && T.length lastTopic >= 3
          && lastTopic `T.isInfixOf` norm
      hasQuestion = T.isInfixOf "?" rawInput
      exclamations = fromIntegral (T.count "!" rawInput) :: Double
      shoutyWords = fromIntegral (length (filter isShouty (T.words rawInput))) :: Double
      distressHits = fromIntegral (countAny norm r5DistressMarkers) :: Double
      -- Negation-safe agency: blank negative phrases first, then
      -- count positives on the remainder.
      agencyNegHits = fromIntegral (countAny norm r5AgencyNegativeMarkers) :: Double
      cleaned = blankAll norm r5AgencyNegativeMarkers
      agencyPosHits = fromIntegral (countAny cleaned r5AgencyPositiveMarkers) :: Double
      addressHits = fromIntegral (countAny norm r5ResonanceAddressMarkers) :: Double
      connectiveHits = fromIntegral (countAny norm r5ConsolidationMarkers) :: Double
      alternativeHits = fromIntegral (countAny norm r5CounterfactualMarkers) :: Double
      topicBit = if topicHit then 1.0 else 0.0
      questionBit = if hasQuestion then 1.0 else 0.0
  in mkUserR5State
       -- Resonance: engagement with the dialogue and shared topic.
       (0.5 + 0.20 * questionBit + 0.15 * min 1.0 addressHits + 0.20 * topicBit)
       -- Atmosphere: tension from distress lexicon, exclamations,
       -- shouting case.
       (0.25 + 0.14 * distressHits + 0.06 * exclamations + 0.05 * shoutyWords)
       -- Confidence: agency balance.
       (0.5 + 0.12 * agencyPosHits - 0.14 * agencyNegHits)
       -- Consolidation: connected discourse and topic continuity.
       (0.5 + 0.10 * connectiveHits + 0.20 * topicBit)
       -- Counterfactual: visible alternatives.
       (0.4 + 0.12 * alternativeHits + 0.08 * questionBit)
  where
    normalizeText =
      T.intercalate " " . T.words . T.replace "ё" "е" . T.toLower
    isShouty w =
      T.length w >= 3
        && T.all (\c -> c >= 'А' && c <= 'Я') w
    countAny text markers =
      length (filter (`T.isInfixOf` text) markers)
    blankAll text markers =
      foldr (\m acc -> T.replace m " § " acc) text markers
