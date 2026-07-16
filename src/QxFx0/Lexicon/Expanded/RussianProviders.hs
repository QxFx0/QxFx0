{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE RecordWildCards #-}

module QxFx0.Lexicon.Expanded.RussianProviders
  ( RussianParadigmsProvider
  , loadRussianParadigmsProvider
  , RussianRuleProvider(..)
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

-- | TierCore: Provider that uses the Russian paradigm files.
data RussianParadigmsProvider = RussianParadigmsProvider
  { rppMap :: M.Map Text ParadigmEntry
  }

instance MorphologyProvider RussianParadigmsProvider where
  providerName _ = "RussianParadigmsProvider"
  providerTier _ = TierCore
  resolveForm RussianParadigmsProvider{..} req =
    case M.lookup (mrLemma req) rppMap of
      Nothing -> Nothing
      Just entry ->
        let 
          caseF = findFeature (\case FeatureCase c -> Just c; _ -> Nothing) (mrFeatures req)
          numF  = findFeature (\case FeatureNumber n -> Just n; _ -> Nothing) (mrFeatures req)
          
          key = case (caseF, numF) of
              (Just NominativeCase, Just SingularNumber)    -> "NomSg"
              (Just GenitiveCase, Just SingularNumber)      -> "GenSg"
              (Just PrepositionalCase, Just SingularNumber) -> "LocSg"
              (Just AccusativeCase, Just SingularNumber)    -> "AccSg"
              (Just InstrumentalCase, Just SingularNumber)  -> "InsSg"
              (Just DativeCase, Just SingularNumber)        -> "DatSg"
              (Just NominativeCase, Just PluralNumber)      -> "NomPl"
              (Just GenitiveCase, Just PluralNumber)        -> "GenPl"
              (Just PrepositionalCase, Just PluralNumber)   -> "LocPl"
              (Just AccusativeCase, Just PluralNumber)      -> "AccPl"
              (Just InstrumentalCase, Just PluralNumber)    -> "InsPl"
              (Just DativeCase, Just PluralNumber)          -> "DatPl"
              _                                             -> "NomSg"
        in case M.lookup key (peForms entry) of
             Nothing -> Nothing
             Just surface -> Just $ MorphologyResponse surface TierCore 0.9 "RussianParadigmsProvider"

-- | Safe loading of Russian Paradigms.
loadRussianParadigmsProvider :: IO (Either LexiconError RussianParadigmsProvider)
loadRussianParadigmsProvider = do
  mDirRaw <- getMorphologyDir
  let path = mDirRaw </> "paradigms.json"
  exists <- doesFileExist path
  if not exists
    then pure $ Left (ResourceMissing path)
    else do
      content <- BS.readFile path
      case Aeson.eitherDecodeStrict content of
        Left err -> pure $ Left (ParseError err)
        Right mp -> pure $ Right $ RussianParadigmsProvider mp

-- | TierAlgorithmic: Improved Russian noun rules.
data RussianRuleProvider = RussianRuleProvider

instance MorphologyProvider RussianRuleProvider where
  providerName _ = "RussianRuleProvider"
  providerTier _ = TierAlgorithmic
  resolveForm _ req =
    let lemma = mrLemma req
        caseF = findFeature (\case FeatureCase c -> Just c; _ -> Nothing) (mrFeatures req)
        numF  = findFeature (\case FeatureNumber n -> Just n; _ -> Nothing) (mrFeatures req)
    in if T.null lemma 
       then Nothing 
       else Just $ MorphologyResponse (applyEnhancedRule lemma caseF numF) TierAlgorithmic 0.4 "RussianRuleProvider"

-- | Enhanced rules handling basic common patterns.
applyEnhancedRule :: Text -> Maybe LexemeCase -> Maybe LexemeNumber -> Text
applyEnhancedRule lemma caseTag number
  | number == Just PluralNumber = inflectPlural lemma
  | otherwise = case caseTag of
      Just NominativeCase    -> lemma
      Just GenitiveCase      -> inflectGenitive lemma
      Just PrepositionalCase -> inflectPrepositional lemma
      Just AccusativeCase    -> lemma
      Just InstrumentalCase  -> inflectInstrumental lemma
      Just DativeCase        -> inflectDative lemma
      _                      -> lemma

inflectPlural :: Text -> Text
inflectPlural l
  | "а" `T.isSuffixOf` l || "я" `T.isSuffixOf` l = T.dropEnd 1 l <> "ы"
  | "о" `T.isSuffixOf` l || "е" `T.isSuffixOf` l = l <> "и"
  | "ь" `T.isSuffixOf` l = T.dropEnd 1 l <> "и"
  | otherwise = l <> "ы"

inflectGenitive :: Text -> Text
inflectGenitive l
  | "а" `T.isSuffixOf` l || "я" `T.isSuffixOf` l = T.dropEnd 1 l <> "ы"
  | "о" `T.isSuffixOf` l || "е" `T.isSuffixOf` l = T.dropEnd 1 l <> "а"
  | "ь" `T.isSuffixOf` l = l <> "а"
  | otherwise = l <> "а"

inflectPrepositional :: Text -> Text
inflectPrepositional l
  | "а" `T.isSuffixOf` l || "я" `T.isSuffixOf` l = T.dropEnd 1 l <> "е"
  | "о" `T.isSuffixOf` l || "е" `T.isSuffixOf` l = T.dropEnd 1 l <> "е"
  | otherwise = l <> "е"

inflectInstrumental :: Text -> Text
inflectInstrumental l
  | "а" `T.isSuffixOf` l || "я" `T.isSuffixOf` l = l <> "ой"
  | otherwise = l <> "ом"

inflectDative :: Text -> Text
inflectDative l
  | "а" `T.isSuffixOf` l || "я" `T.isSuffixOf` l = T.dropEnd 1 l <> "е"
  | otherwise = l <> "у"

-- Helper to find a feature in the list.
findFeature :: (a -> Maybe b) -> [a] -> Maybe b
findFeature f = foldr (\x acc -> case f x of Just v -> Just v; Nothing -> acc) Nothing
