{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Semantic.Content.Category
Description : Concept category type shared between content and ontology layers.

This module exists to break the otherwise-cyclic dependency between
'QxFx0.Semantic.Content' (which needs the ontology-aware classifier) and
'QxFx0.Semantic.Ontology' (which needs the category type for its nodes).
-}
module QxFx0.Semantic.Content.Category
  ( ConceptCategory(..)
  ) where

import QxFx0.Types.Semantic.Content (ConceptCategory(..))
