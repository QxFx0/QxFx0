{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Lexicon.Analyze
  ( lexicalExtractNouns
  , lexicalAnalyzeWord
  ) where

import QxFx0.Semantic.Morphology (MorphToken(..), POS(..), analyzeMorph)
import Data.Text (Text)
import qualified Data.Text as T

lexicalAnalyzeWord :: Text -> MorphToken
lexicalAnalyzeWord = analyzeMorph

lexicalExtractNouns :: Text -> [Text]
lexicalExtractNouns input =
  let tokens = map analyzeMorph (T.words input)
  in [ mtLemma t | t <- tokens, mtPOS t == Noun, not (T.null (mtLemma t)) ]
