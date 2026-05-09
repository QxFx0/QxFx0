{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Syntactic parser bridge: call Python spaCy parser for Russian input when
available; otherwise use a rule-based Haskell fallback.

Thin IO wrapper.  The spaCy path runs scripts/parse_input.py; the fallback
performs whitespace tokenisation, simple POS guessing, and naive dependency
attachment so downstream semantic slots still function without Python.
-}
module QxFx0.Semantic.Input.Parse
  ( ParsedInput(..)
  , ParsedToken(..)
  , parseInput
  , parseInputOrFallback
  , emptyParsedInput
  , ruleBasedParse
  ) where

import Control.DeepSeq (NFData)
import Control.Exception (IOException, catch)
import Data.Aeson (FromJSON(..), eitherDecodeStrict)
import Data.Char (isPunctuation)
import Data.List (findIndex)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import System.Process (readProcess)

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
-- IO entry points
--------------------------------------------------------------------------------

{-| Try spaCy first; on any failure (missing python3, missing spacy, bad JSON,
   script error) fall back to the rule-based parser.  This makes the Python
   dependency truly optional. -}
parseInput :: SemanticConfig -> Text -> IO (Maybe ParsedInput)
parseInput cfg raw =
  (trySpacy raw >>= \case
     Just pi -> pure (Just pi)
     Nothing -> pure (Just (ruleBasedParse cfg raw)))
  `catch` \(_ :: IOException) -> pure (Just (ruleBasedParse cfg raw))

trySpacy :: Text -> IO (Maybe ParsedInput)
trySpacy raw = do
  let script = "scripts/parse_input.py"
  result <- readProcess "python3" [script] (T.unpack raw)
  pure $ case eitherDecodeStrict (TE.encodeUtf8 (T.pack result)) of
    Right pi -> Just pi
    Left  _  -> Nothing

{-| Convenience wrapper that always yields a 'ParsedInput' (spaCy or fallback). -}
parseInputOrFallback :: SemanticConfig -> Text -> IO ParsedInput
parseInputOrFallback cfg raw = do
  mParsed <- parseInput cfg raw
  pure $ fromMaybe (ruleBasedParse cfg raw) mParsed

emptyParsedInput :: Text -> ParsedInput
emptyParsedInput raw = ParsedInput [] 0 raw

--------------------------------------------------------------------------------
-- Rule-based fallback parser
--------------------------------------------------------------------------------

{-| Fast, deterministic rule-based parser for Russian text.  Good enough to
   keep downstream semantic slots (subject, object, negation, verb, agreement)
   functional when spaCy is unavailable. -}
ruleBasedParse :: SemanticConfig -> Text -> ParsedInput
ruleBasedParse cfg raw =
  let tokens = tokenizeRussian raw
      indexed = zip [0..] tokens
      rootIdx = fromMaybe 0 (findIndex (isVerbLike cfg . T.toLower . snd) indexed)
      negWords = scParseParticles cfg  -- "не" lives in particles for the rule parser
      mkToken (idx, word) =
        let lemma = T.toLower word
            pos   = guessPos cfg lemma
            (dep, headIdx)
              | idx == rootIdx            = ("ROOT", idx)
              | lemma `elem` negWords     = ("advmod", rootIdx)
              | isPronoun cfg lemma       = ("nsubj",  rootIdx)
              | pos == "NOUN"             = ("obj",    rootIdx)
              | pos == "ADJ"              = ("amod",   rootIdx)
              | otherwise                 = ("dep",    rootIdx)
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
