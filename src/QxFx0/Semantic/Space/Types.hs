{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space.Types
  ( PredicateVector(..)
  , AtomVector(..)
  , FieldDimension(..)
  , DimensionPrototype(..)
  , SemanticSpace(..)
  , emptySemanticSpace
  , fieldDimensionPrototypes
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import QxFx0.Types.Semantic.Space

emptySemanticSpace :: SemanticSpace
emptySemanticSpace = SemanticSpace
  { ssDimensionCount = 0
  , ssAtomIndex = M.empty
  , ssPrototypes = M.empty
  , ssPredicateVectors = M.empty
  , ssFactVectors = M.empty
  }

fieldDimensionPrototypes :: Map FieldDimension [Text]
fieldDimensionPrototypes = M.fromList
  [ (FdResonance, ["связана", "связан", "зависит", "контекст", "related_to"])
  , (FdAtmosphere, ["выражает", "обозначает", "сигнализирует", "вызывает"])
  , (FdConfidence, ["претендует", "требует", "доказательства", "факт"])
  , (FdConsolidation, ["субъекта", "действие", "ответственность", "последствий"])
  , (FdCounterfactual, ["возможность", "независимо", "границу", "условиях"])
  ]
