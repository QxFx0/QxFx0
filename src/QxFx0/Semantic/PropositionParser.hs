{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.PropositionParser
Description : Extract structured proposition from user input.

Works AFTER IntentClassifier (which determines move type) and BEFORE
GraphEngagement (which finds the system's relationship to the proposition).

Extracts:
  - Subject: the main topic being discussed
  - Claim: what is being asserted about the subject
  - Relation: connecting verb ("связана со", "противоречит")
  - Object: second topic in relational statements
  - Mode: Define | Assert | Challenge | Connect | Reflect

Pure, total, deterministic. Same input → same output.
-}
module QxFx0.Semantic.PropositionParser
  ( ParsedProposition(..)
  , PropositionMode(..)
  , parseProposition
  , extractSubject
  , extractClaim
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (isInfixOf, find)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore (allTopics, allAtomIds, AtomId(..), atomStore, Atom(..), AtomCategory(..))
import qualified Data.Map.Strict as M

-- | Mode of the proposition — what the user is doing.
data PropositionMode
  = ModeDefine    -- "Что такое X?" — asking for definition
  | ModeAssert    -- "X — это Y" / "X не более чем Y" — asserting a claim
  | ModeChallenge -- "Но разве X не Y?" / "Я не согласен" — challenging
  | ModeConnect   -- "Как X связан с Y?" / "Связь между X и Y" — asking for connection
  | ModeReflect   -- "Что думаешь о X?" / "А если посмотреть иначе" — reflective
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Parsed proposition extracted from user input.
data ParsedProposition = ParsedProposition
  { ppSubject :: !Text               -- main topic ("свобода")
  , ppClaim   :: !(Maybe Text)       -- assertion ("отсутствие ограничений")
  , ppRelation :: !(Maybe Text)      -- connecting verb ("связана со")
  , ppObject  :: !(Maybe Text)       -- second topic ("справедливостью")
  , ppMode    :: !PropositionMode
  , ppRawText :: !Text               -- original input for trace
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Parse a proposition from raw user input.
-- Uses topic matching against AtomStore to find subjects and objects.
-- Deterministic: same input → same output.
parseProposition :: Text -> ParsedProposition
parseProposition raw =
  let lower = T.toLower (T.strip raw)
      mode = classifyMode lower
      subject = extractSubject lower
      object = extractObject lower subject
      relation = extractRelation lower
      claim = extractClaim lower mode subject
  in ParsedProposition
       { ppSubject = subject
       , ppClaim = claim
       , ppRelation = relation
       , ppObject = object
       , ppMode = mode
       , ppRawText = raw
       }

-- | Classify the mode of the proposition from text patterns.
classifyMode :: Text -> PropositionMode
classifyMode lower =
  let isQuestion = "?" `T.isSuffixOf` T.strip lower
                     || any (`T.isPrefixOf` lower) ["что такое", "разница между", "в чём", "как "]
      isChallenge = any (`T.isInfixOf` lower)
        [ "но разве", "не соглас", "спорю", "возраж", "ошибаешь"
        , "не прав", "сомневаюсь", "это просто", "не более чем"
        , "сводится к", "это всего лишь", "я считаю что"
        , "по-моему", "на мой взгляд", "разве не" ]
      isConnect = any (`T.isInfixOf` lower)
        [ "связь между", "как связано", "отношение между"
        , "связана со", "связан с", "связь с"
        , "чем отличается", "разница между", "сравни" ]
      isReflect = any (`T.isInfixOf` lower)
        [ "что думаешь", "какая мысль", "поразмышляй"
        , "а если посмотреть", "с другой стороны" ]
      isAssert = any (`T.isInfixOf` lower)
        [ " — это ", "— это", " это ", "является", "значит"
        , "представляет собой", "заключается в" ]
  in if isChallenge
       then ModeChallenge
       else if isConnect
         then ModeConnect
         else if isReflect
           then ModeReflect
           else if isAssert && not isQuestion
             then ModeAssert
             else ModeDefine

-- | Extract the main subject topic from input.
-- Matches against all known topics (L1 + domain + discovered).
extractSubject :: Text -> Text
extractSubject lower =
  let topics = allTopics
      -- Also check domain atoms
      domainTopics = [ atomSurface a | a <- M.elems atomStore
                    , atomCategory a == CatDomain ]
      allKnown = topics ++ domainTopics
      -- Find first topic that appears as substring in input
      matched = find (\t -> t `T.isInfixOf` lower) allKnown
  in fromMaybe "неизвестный" matched

-- | Extract a second topic (object) from relational statements.
extractObject :: Text -> Text -> Maybe Text
extractObject lower subject =
  let topics = allTopics
      domainTopics = [ atomSurface a | a <- M.elems atomStore
                    , atomCategory a == CatDomain ]
      allKnown = filter (/= subject) (topics ++ domainTopics)
      -- Look for second topic after the subject
      afterSubject = case T.breakOn subject lower of
        (_, rest) | not (T.null rest) -> T.drop (T.length subject) rest
        _ -> lower
      matched = find (\t -> t `T.isInfixOf` afterSubject) allKnown
  in matched

-- | Extract the connecting relation from relational statements.
extractRelation :: Text -> Maybe Text
extractRelation lower =
  let relations =
        [ ("связана со", "связана со")
        , ("связан с", "связан с")
        , ("связь между", "связь между")
        , ("отношение между", "отношение между")
        , ("отличается от", "отличается от")
        , ("противоречит", "противоречит")
        , ("ведёт к", "ведёт к")
        , ("ведет к", "ведет к")
        , ("приводит к", "приводит к")
        , ("следует из", "следует из")
        , ("зависит от", "зависит от")
        , ("ограничивает", "ограничивает")
        , ("требует", "требует")
        , ("включает", "включает")
        , ("исключает", "исключает")
        ]
  in fmap snd (find (\(pat, _) -> pat `T.isInfixOf` lower) relations)

-- | Extract the claim text from assertive statements.
-- For "X — это Y" → claim is "Y".
-- For "X — это просто Y" → claim is "просто Y".
-- For challenge mode → claim is what's being challenged.
extractClaim :: Text -> PropositionMode -> Text -> Maybe Text
extractClaim lower mode subject =
  case mode of
    ModeAssert ->
      -- "свобода — это отсутствие ограничений" → "отсутствие ограничений"
      let patterns = [" — это ", "— это ", " это ", "является ", "значит "
                     , "представляет собой ", "заключается в "]
          afterPattern = listToMaybe
            [ let (_, r) = T.breakOn pat lower in T.strip (T.drop (T.length pat) r)
            | pat <- patterns
            , pat `T.isInfixOf` lower
            ]
      in afterPattern >>= \t -> if T.null t then Nothing else Just t
    ModeChallenge ->
      -- "разве свобода не означает делать всё что угодно" → "делать всё что угодно"
      let challengeMarkers = ["разве ", "не ", "просто ", "не более чем "]
          cleaned = foldl (\acc m -> T.replace m "" acc) lower challengeMarkers
          afterSubject = case T.breakOn subject cleaned of
            (_, rest) | not (T.null rest) -> T.strip (T.drop (T.length subject) rest)
            _ -> ""
      in if T.null afterSubject then Nothing else Just afterSubject
    _ -> Nothing

-- Internal helper: break-on then drop prefix
-- (T.breakOn already does this, but we need the snd part)
