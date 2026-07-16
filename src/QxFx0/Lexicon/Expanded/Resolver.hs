{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE GADTs #-}

module QxFx0.Lexicon.Expanded.Resolver
  ( HybridResolver(..)
  , AnyProvider(..)
  , createResolver
  , resolveWord
  ) where

import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import QxFx0.Lexicon.Expanded.Types
import QxFx0.Lexicon.Expanded.Provider

-- | A resolver that orchestrates multiple morphology providers.
-- It uses a GADT or a list of wrapped providers to maintain type erasure.
data AnyProvider where
  AnyProvider :: MorphologyProvider p => p -> AnyProvider

data HybridResolver = HybridResolver
  { providers :: [AnyProvider]
  }

-- | Create a resolver from a list of providers.
createResolver :: [AnyProvider] -> HybridResolver
createResolver = HybridResolver

-- | Resolve a word form by iterating through providers in priority order.
resolveWord :: HybridResolver -> MorphologyRequest -> Maybe MorphologyResponse
resolveWord resolver req = 
  let results = mapMaybe (\(AnyProvider p) -> resolveForm p req) (providers resolver)
  in listToMaybe results
