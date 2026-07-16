{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Lexicon.Expanded.Sandbox where

import qualified Data.Map.Strict as M
import QxFx0.Lexicon.Expanded.Types
import QxFx0.Lexicon.Expanded.Provider
import QxFx0.Lexicon.Expanded.Resolver
import QxFx0.Lexicon.Expanded.RussianProviders
import QxFx0.Lexicon.Expanded.EnglishProviders
import QxFx0.Lexicon.Expanded.MultilingualResolver
import QxFx0.Lexicon.Expanded.PGFBridge
import QxFx0.Types (LexemeCase(..), LexemeNumber(..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

-- | A simple curated provider for the sandbox.
data CuratedSandboxProvider = CuratedSandboxProvider

instance MorphologyProvider CuratedSandboxProvider where
  providerName _ = "CuratedSandbox"
  providerTier _ = TierCurated
  resolveForm _ req =
    if mrLemma req == "свобода" && any (\case FeatureCase GenitiveCase -> True; _ -> False) (mrFeatures req) && mrLang req == RU
    then Just $ MorphologyResponse "свободы" TierCurated 1.0 "CuratedSandbox"
    else if mrLemma req == "freedom" && any (\case FeaturePossessive -> True; _ -> False) (mrFeatures req) && mrLang req == EN
    then Just $ MorphologyResponse "freedom's" TierCurated 1.0 "CuratedSandbox"
    else Nothing

-- | Run a demonstration of the multilingual hybrid resolution.
runSandboxDemo :: IO ()
runSandboxDemo = do
  -- Use the robust initializer
  multiResolver <- initializeMultilingualResolver
  
  -- We manually add our curated provider to the resolver's underlying maps for demo
  -- In real system, this would be part of the initialized resolvers.
  let updatedResolvers = M.map (\res -> 
        let (HybridResolver ps) = res 
        in createResolver (AnyProvider CuratedSandboxProvider : ps)
        ) (langResolvers multiResolver)
  
  let finalResolver = createMultilingualResolver updatedResolvers
  
  let testCases = 
        [ (RU, "свобода", [FeatureCase GenitiveCase, FeatureNumber SingularNumber], "Curated RU")
        , (RU, "абсурд", [FeatureCase GenitiveCase, FeatureNumber SingularNumber], "Core RU")
        , (RU, "неизвестный_термин", [FeatureCase GenitiveCase, FeatureNumber SingularNumber], "Algo RU")
        , (EN, "freedom", [FeaturePossessive, FeatureNumber SingularNumber], "Curated EN")
        , (EN, "concept", [FeaturePlural], "Algo EN (Plural)")
        , (EN, "category", [FeaturePlural], "Algo EN (Plural)")
        , (EN, "unknown_word", [FeaturePossessive], "Algo EN (Possessive)")
        ]
  
  TIO.putStrLn "--- Robust Multilingual Expanded Lexicon Sandbox Demo ---"
  mapM_ (runTest finalResolver) testCases

runTest :: MultilingualResolver -> (LanguageCode, Text, [GrammaticalFeature], Text) -> IO ()
runTest resolver (lang, lemma, features, comment) = do
  let req = MorphologyRequest lang lemma features
  let res = resolveWordMultilingual resolver req
  case res of
    Nothing -> TIO.putStrLn $ "FAILED: " <> lemma
    Just r -> do
      let bridge = bridgeToPGF r
      TIO.putStrLn $ "[" <> (T.pack . show $ lang) <> " | " <> lemma <> "] " 
                  <> resSurface r <> " (" <> resSource r <> ") "
                  <> "-> PGF: " <> pgfExpr bridge 
                  <> " -> " <> comment
