{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Lexicon.Expanded.Provider
  ( MorphologyProvider(..)
  ) where

import Data.Text (Text)
import QxFx0.Lexicon.Expanded.Types

-- | Interface for a morphology data source.
class MorphologyProvider p where
  providerName :: p -> Text
  providerTier :: p -> LexicalTier
  resolveForm  :: p -> MorphologyRequest -> Maybe MorphologyResponse
