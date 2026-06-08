{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.MeaningDecompose.Core
  ( decomposedFacts
  , factBySubject
  , heartFacts
  , bloodFacts
  ) where

import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.MeaningAtom (FactAtoms)
import QxFx0.Semantic.MeaningDecompose.Domains
  ( decomposedFacts
  , heartFacts
  , bloodFacts
  )

factBySubject :: Text -> Maybe FactAtoms
factBySubject key =
  case M.lookup (T.toLower (T.strip key)) decomposedFacts of
    Just fa -> Just fa
    Nothing ->
      case M.lookup (T.strip key) decomposedFacts of
        Just fa -> Just fa
        Nothing -> Nothing
