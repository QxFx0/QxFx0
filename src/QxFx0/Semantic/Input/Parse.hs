{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Local deterministic syntactic parser for Russian input.

The production parser path is rule-based and checkout-independent. It performs
whitespace tokenisation, simple POS guessing, and naive dependency attachment
so downstream semantic slots remain deterministic and available without Python.
-}
module QxFx0.Semantic.Input.Parse
  ( ParsedInput(..)
  , ParsedToken(..)
  , parseInput
  , emptyParsedInput
  , ruleBasedParse
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..))
import Data.Char (isPunctuation)
import Data.List (findIndex)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.SemanticConfig (SemanticConfig(..))

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data ParsedToken = ParsedToken
  { ptIdx     :: !Int
  , ptWord    :: !Text
  , ptLemma   :: !Text
  , ptPos     :: !Text          -- ^ NOUN, VERB, ADJ, ADP, ADV, PART, PRON...
  , ptDep     :: !Text          -- ^ nsubj, obj, advmod, neg, ROOT, case, nmod...
  , ptHeadIdx :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON)

data ParsedInput = ParsedInput
  { piTokens  :: ![ParsedToken]
  , piRootIdx :: !Int
  , piRaw     :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON)

--------------------------------------------------------------------------------
-- IO entry point
--------------------------------------------------------------------------------

parseInput :: SemanticConfig -> Text -> IO ParsedInput
parseInput cfg raw = pure (ruleBasedParse cfg raw)

emptyParsedInput :: Text -> ParsedInput
emptyParsedInput raw = ParsedInput [] 0 raw

--------------------------------------------------------------------------------
-- Rule-based fallback parser
--------------------------------------------------------------------------------

{-| Fast, deterministic rule-based parser for Russian text. Keeps downstream
   semantic slots (subject, object, negation, verb, agreement) functional in
   the supported local-only production parser contour. -}
ruleBasedParse :: SemanticConfig -> Text -> ParsedInput
ruleBasedParse cfg raw =
  let tokens = tokenizeRussian raw
      indexed = zip [0..] tokens
  in case indexed of
       [] -> emptyParsedInput raw
       _ ->
         let rootIdx = fromMaybe 0 (findIndex (isVerbLike cfg . T.toLower . snd) indexed)
             hasVerbRoot = any (isVerbLike cfg . T.toLower . snd) indexed
             negWords = scParseParticles cfg
             standaloneParticles = ["да", "нет", "ок", "угу", "ага"]
             mkToken (idx, word) =
               let lemma = T.toLower word
                   pos   = if not hasVerbRoot && (lemma `elem` negWords || lemma `elem` standaloneParticles)
                             then "PART"
                             else guessPos cfg lemma
                   (dep, headIdx)
                     | idx == rootIdx && hasVerbRoot = ("ROOT", idx)
                     | idx == rootIdx = ("dep", idx)
                     | lemma `elem` negWords = ("advmod", rootIdx)
                     | isPronoun cfg lemma = ("nsubj", rootIdx)
                     | pos == "NOUN" = ("obj", rootIdx)
                     | pos == "ADJ" = ("amod", rootIdx)
                     | otherwise = ("dep", rootIdx)
               in ParsedToken idx word lemma pos dep headIdx
         in ParsedInput (map mkToken indexed) rootIdx raw

tokenizeRussian :: Text -> [Text]
tokenizeRussian raw =
  let words = T.words raw
      stripEdge t = T.dropWhile isPunctEdge (T.dropWhileEnd isPunctEdge t)
      isPunctEdge c = isPunctuation c || c `elem` ("«»—…–“”" :: String)
  in filter (not . T.null) (map stripEdge words)

-- | Heuristic: word ends with a typical Russian verb suffix.
isVerbLike :: SemanticConfig -> Text -> Bool
isVerbLike cfg w =
  let endings = scParseVerbEndings cfg
  in any (`T.isSuffixOf` w) endings

isPronoun :: SemanticConfig -> Text -> Bool
isPronoun cfg w = w `elem` scParsePronouns cfg

isAdjective :: SemanticConfig -> Text -> Bool
isAdjective cfg w =
  let endings = scParseAdjEndings cfg
  in any (`T.isSuffixOf` w) endings

guessPos :: SemanticConfig -> Text -> Text
guessPos cfg w
  | isPronoun cfg w          = "PRON"
  | w `elem` scParsePrepositions cfg = "ADP"
  | w `elem` scParseParticles cfg    = "PART"
  | w `elem` scParseAdverbs cfg      = "ADV"
  | w `elem` scParseConjunctions cfg = "CCONJ"
  | isAdjective cfg w        = "ADJ"
  | isVerbLike cfg w         = "VERB"
  | otherwise                = "NOUN"
