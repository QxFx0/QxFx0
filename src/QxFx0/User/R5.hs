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

== Frozen model discipline

All constants below (bases, increments, marker lists) are hand-set
v1 and frozen at release — the deterministic-runtime contract.  The
concept's calibration loop (label 30–50 utterances, fit a linear
regression, audit residuals, refit) replaces these constants /offline/
and lands as a versioned model through the math-change protocol
(@currentMathVersion@ bump), never as a runtime weight update.  The
labelled set does not exist yet, so the model is honest about being
heuristic; every axis is a documented linear feature sum.

Encoder v2 (2026-11-15) changes **one predicate only** — the
topic-continuity bit — and no constant.  See 'topicContinuity'.

== Negation handling

Russian negation traps (\"не хочу\" contains \"хочу\") are handled
by the replace-then-count trick on the agency axis: all negative
phrases are counted and blanked out of the text /before/ positive
markers are counted, so a negated positive can never leak into the
positive count.  Topic continuity has its own, narrower rule: a
topic occurrence immediately preceded by a negation particle is not
continuity ('topicContinuity').

== Axis definitions

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
  ( r5EncoderVersion -- re-exported from QxFx0.Types.User.R5 (canonical)
  , encodeR5
  , topicContinuity
    -- * Marker lexicons (exported for tests and audit)
  , r5DistressMarkers
  , r5AgencyNegativeMarkers
  , r5AgencyPositiveMarkers
  , r5ResonanceAddressMarkers
  , r5ConsolidationMarkers
  , r5CounterfactualMarkers
  ) where

import Data.Char (isLetter)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.User.R5
  ( UserR5State
  , r5EncoderVersion
  , mkUserR5State
  )
import QxFx0.Semantic.Markers
  ( r5DistressMarkers
  , r5AgencyNegativeMarkers
  , r5AgencyPositiveMarkers
  , r5ResonanceAddressMarkers
  , r5ConsolidationMarkers
  , r5CounterfactualMarkers
  )

-- | Encode one utterance into an 'UserR5State'.  Total and
-- deterministic: a pure function of the input text and the topic
-- word.  Empty input decodes to 'neutralUserR5State'.
encodeR5 :: Text -> Text -> UserR5State
encodeR5 rawInput lastTopic =
  let norm = normalizeText rawInput
      topicHit = topicContinuity rawInput lastTopic
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

-- | The topic-continuity bit of 'encodeR5' (encoder v2, 2026-11-15).
--
-- The topic is normalized like the utterance and must appear as a
-- contiguous run of /whole words/; an occurrence whose immediately
-- preceding word is a negation particle is not continuity (an
-- occurrence that is not negated still counts).  The v1 rule was
-- @lastTopic `T.isInfixOf` norm@ on the unnormalized topic, which
-- matched «смысл» inside «бессмысленным», «ответственность» inside
-- «ответственностью», and «хочу» inside «не хочу» — measured in
-- @docs\/closure\/USER_REGIME_PROBE_PREREG_2026-11-14.md@.
--
-- Whole-word matching deliberately gives up inflection: an
-- instrumental-case repeat is no longer continuity.  A
-- morphology-aware match is a calibration-phase change, not part of
-- v2.  The raw-topic length guard (>= 3) is preserved from v1.
topicContinuity :: Text -> Text -> Bool
topicContinuity rawInput lastTopic =
  not (T.null lastTopic)
    && T.length lastTopic >= 3
    && topicPresent
         (wordTokens (normalizeText lastTopic))
         (wordTokens (normalizeText rawInput))

-- | A word is a maximal run of letters: punctuation never joins or
-- splits a token.
wordTokens :: Text -> [Text]
wordTokens = filter (not . T.null) . T.split (not . isLetter)

-- | Whole-word, negation-safe containment of a topic word sequence.
-- An empty topic is never present.
topicPresent :: [Text] -> [Text] -> Bool
topicPresent topic textWords
  | null topic = False
  | otherwise = go Nothing textWords
  where
    width = length topic
    go _ [] = False
    go previous rest@(w : ws)
      | take width rest == topic
      , not (maybe False (`elem` negationParticles) previous) = True
      | otherwise = go (Just w) ws

-- | Negation particles for topic continuity.  Deliberately narrow:
-- the measured defect class is a negated verb («не хочу»), not every
-- syntactic negation.  The window is one word; adverb-separated
-- negation («не очень хочу») is a documented limitation.
negationParticles :: [Text]
negationParticles = ["не", "ни", "нет"]

normalizeText :: Text -> Text
normalizeText =
  T.intercalate " " . T.words . T.replace "ё" "е" . T.toLower

isShouty :: Text -> Bool
isShouty w =
  T.length w >= 3
    && T.all (\c -> c >= 'А' && c <= 'Я') w

countAny :: Text -> [Text] -> Int
countAny text markers =
  length (filter (`T.isInfixOf` text) markers)

blankAll :: Text -> [Text] -> Text
blankAll text markers =
  foldr (\m acc -> T.replace m " § " acc) text markers
