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

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Category of a concept, used for category-typed generic predicates and
-- ontology nodes.
data ConceptCategory
  = CategoryPhilosophical
    -- ^ Abstract philosophical concepts (свобода, истина, сознание, etc.)
  | CategorySocial
    -- ^ Social/interpersonal concepts (ответственность, доверие, долг)
  | CategoryPsychological
    -- ^ Psychological/mental concepts (память, восприятие, эмоция)
  | CategoryPhysical
    -- ^ Physical/concrete concepts (тело, пространство, время)
  | CategoryGeneral
    -- ^ Fallback for unclassifiable topics
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
