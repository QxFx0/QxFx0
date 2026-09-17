{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector.Types
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , SelectorDiagnostic(..)
  , selectorPolicyVersion
  , selectorMathVersion
  , emptyContentSelector
  ) where

import qualified Data.Map.Strict as M
import Data.Text (Text)

import QxFx0.Semantic.Space.Types (SemanticSpace, emptySemanticSpace)
import QxFx0.Types.Semantic.ContentSelector (ContentSelector(..), SelectedPredicate(..), SelectorDiagnostic(..))

selectorPolicyVersion :: Text
selectorPolicyVersion = "selector-policy-v3-topic-relevance-modulated"

selectorMathVersion :: Text
selectorMathVersion = "selector-math-v4-topic-field-activation-ontology-assembly"

emptyContentSelector :: ContentSelector
emptyContentSelector = ContentSelector
  { csSpace = emptySemanticSpace
  , csTopicAtoms = M.empty
  , csTopicPredicates = M.empty
  , csLemmaMap = M.empty
  , csOntology = Nothing
  }
