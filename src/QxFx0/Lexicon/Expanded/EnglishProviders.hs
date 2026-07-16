{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE RecordWildCards #-}

module QxFx0.Lexicon.Expanded.EnglishProviders
  ( EnglishParadigmsProvider
  , loadEnglishParadigmsProvider
  , EnglishRuleProvider(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import System.FilePath ((</>))
import System.Directory (doesFileExist)
import QxFx0.Lexicon.Expanded.Types
import QxFx0.Lexicon.Expanded.Provider (MorphologyProvider(..))
import QxFx0.Resources.Paths (getMorphologyDir)
import QxFx0.Types.Lexicon.RuntimeParadigms (ParadigmEntry(..))
import QxFx0.Types (LexemeCase(..), LexemeNumber(..))

-- | TierCore: Provider that uses the English paradigm files.
data EnglishParadigmsProvider = EnglishParadigmsProvider
  { eppMap :: M.Map Text ParadigmEntry
  }

instance MorphologyProvider EnglishParadigmsProvider where
  providerName _ = "EnglishParadigmsProvider"
  providerTier _ = TierCore
  resolveForm EnglishParadigmsProvider{..} req =
    case M.lookup (mrLemma req) eppMap of
      Nothing -> Nothing
      Just entry ->
        let 
          -- English uses a subset of cases
          caseF = findFeature (\case FeatureCase c -> Just c; _ -> Nothing) (mrFeatures req)
          numF  = findFeature (\case FeatureNumber n -> Just n; _ -> Nothing) (mrFeatures req)
          poss  = any (\case FeaturePossessive -> True; _ -> False) (mrFeatures req)

          key = case (caseF, numF, poss) of
              (_, Just PluralNumber, False) -> "NomPl"
              (Just GenitiveCase, _, _)      -> "GenSg"
              (_, _, True)                  -> "GenSg"
              _                             -> "NomSg"
        in case M.lookup key (peForms entry) of
             Nothing -> Nothing
             Just surface -> Just $ MorphologyResponse surface TierCore 0.9 "EnglishParadigmsProvider"

-- | Safe loading of English Paradigms.
loadEnglishParadigmsProvider :: IO (Either LexiconError EnglishParadigmsProvider)
loadEnglishParadigmsProvider = do
  mDirRaw <- getMorphologyDir
  let path = mDirRaw </> "en" </> "paradigms.json"
  exists <- doesFileExist path
  if not exists
    then pure $ Left (ResourceMissing path)
    else do
      content <- BS.readFile path
      case Aeson.eitherDecodeStrict content of
        Left err -> pure $ Left (ParseError err)
        Right mp -> pure $ Right $ EnglishParadigmsProvider mp

-- | TierAlgorithmic: Improved English noun rules.
data EnglishRuleProvider = EnglishRuleProvider

instance MorphologyProvider EnglishRuleProvider where
  providerName _ = "EnglishRuleProvider"
  providerTier _ = TierAlgorithmic
  resolveForm _ req =
    let lemma = mrLemma req
    in if T.null lemma 
       then Nothing 
       else Just $ MorphologyResponse (applyEnglishRule lemma (mrFeatures req)) TierAlgorithmic 0.4 "EnglishRuleProvider"

applyEnglishRule :: Text -> [GrammaticalFeature] -> Text
applyEnglishRule lemma features
  | any (\case FeaturePossessive -> True; _ -> False) features = lemma <> "'s"
  | any (\case FeaturePlural -> True; _ -> False) features || any (\case FeatureNumber PluralNumber -> True; _ -> False) features = inflectPlural lemma
  | otherwise = lemma

inflectPlural :: Text -> Text
inflectPlural l
  | "y" `T.isSuffixOf` l && not ("ey" `T.isSuffixOf` l) = T.dropEnd 1 l <> "ies"
  | "s" `T.isSuffixOf` l || "x" `T.isSuffixOf` l || "z" `T.isSuffixOf` l || "ch" `T.isSuffixOf` l || "sh" `T.isSuffixOf` l = l <> "es"
  | otherwise = l <> "s"

-- Helper to find a feature in the list.
findFeature :: (a -> Maybe b) -> [a] -> Maybe b
findFeature f = foldr (\x acc -> case f x of Just v -> Just v; Nothing -> acc) Nothing
