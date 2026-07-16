{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Lexicon.Expanded.MultilingualResolver
  ( MultilingualResolver(..)
  , createMultilingualResolver
  , resolveWordMultilingual
  , initializeMultilingualResolver
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import QxFx0.Lexicon.Expanded.Types
import QxFx0.Lexicon.Expanded.Provider
import QxFx0.Lexicon.Expanded.Resolver
import QxFx0.Lexicon.Expanded.RussianProviders
import QxFx0.Lexicon.Expanded.EnglishProviders

-- | A resolver that manages multiple language-specific resolvers.
data MultilingualResolver = MultilingualResolver
  { langResolvers :: M.Map LanguageCode HybridResolver
  }

-- | Manually create a multilingual resolver.
createMultilingualResolver :: M.Map LanguageCode HybridResolver -> MultilingualResolver
createMultilingualResolver = MultilingualResolver

-- | Resolve a word form by first selecting the correct language resolver.
resolveWordMultilingual :: MultilingualResolver -> MorphologyRequest -> Maybe MorphologyResponse
resolveWordMultilingual MultilingualResolver{..} req = do
  resolver <- M.lookup (mrLang req) langResolvers
  resolveWord resolver req

-- | Robust initialization of the multilingual resolver from resources.
initializeMultilingualResolver :: IO MultilingualResolver
initializeMultilingualResolver = do
  -- Initialize Russian
  ruCoreRes <- loadRussianParadigmsProvider
  let ruCore = case ruCoreRes of
                 Right p -> [AnyProvider p]
                 Left _  -> [] -- Degrade to rules if file is missing
  let ruResolver = createResolver $ 
        [ AnyProvider RussianRuleProvider ] -- Rules are always available
        ++ ruCore

  -- Initialize English
  enCoreRes <- loadEnglishParadigmsProvider
  let enCore = case enCoreRes of
                 Right p -> [AnyProvider p]
                 Left _  -> [] -- Degrade to rules if file is missing
  let enResolver = createResolver $ 
        [ AnyProvider EnglishRuleProvider ] -- Rules are always available
        ++ enCore

  pure $ MultilingualResolver $ M.fromList 
    [ (RU, ruResolver)
    , (EN, enResolver)
    ]
