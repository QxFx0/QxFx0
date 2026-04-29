{-# LANGUAGE OverloadedStrings, StrictData #-}
module QxFx0.Lexicon.Runtime
  ( LexicalRuntime(..)
  , loadLexicalRuntime
  , emptyLexicalRuntime
  , lexicalToNominative
  , lexicalGenitiveForm
  , lexicalPrepositionalForm
  ) where

import QxFx0.Lexicon.Types
import QxFx0.Lexicon.Loader
import Data.Text (Text)
import qualified Data.Map.Strict as Map

data LexicalRuntime = LexicalRuntime
  { lrData :: !LexicalRuntimeData
  }

emptyLexicalRuntime :: LexicalRuntime
emptyLexicalRuntime = LexicalRuntime
  { lrData = emptyLexicalRuntimeData (LanguageCode "ru")
  }

loadLexicalRuntime :: IO LexicalRuntime
loadLexicalRuntime = do
  lrd <- loadLexicalRuntimeData
  pure LexicalRuntime { lrData = lrd }

lexicalToNominative :: LexicalRuntime -> Text -> Text
lexicalToNominative rt word =
  case Map.lookup word (lrdNominative (lrData rt)) of
    Just lemma -> lemma
    Nothing    -> word

lexicalGenitiveForm :: LexicalRuntime -> Text -> Text
lexicalGenitiveForm rt word =
  case Map.lookup word (lrdGenitive (lrData rt)) of
    Just form -> form
    Nothing   -> word

lexicalPrepositionalForm :: LexicalRuntime -> Text -> Text
lexicalPrepositionalForm rt word =
  case Map.lookup word (lrdPrepositional (lrData rt)) of
    Just form -> form
    Nothing   -> word
