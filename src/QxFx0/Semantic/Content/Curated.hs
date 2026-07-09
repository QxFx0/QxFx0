{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | P1.2: curated predicate loader.
--
-- Loads a JSONL file of manually curated 'SemanticPredicate's for gap
-- concepts (concepts present in the atom graph but missing from the
-- hardcoded 'definitionCorpus') and merges them into the seed corpus.
module QxFx0.Semantic.Content.Curated
  ( CuratedPredicateEntry(..)
  , CuratedPredicateItem(..)
  , curatedPredicatesPath
  , loadCuratedPredicates
  , mergeCuratedIntoDefinitionCorpus
  , extendedDefinitionCorpus
  ) where

import qualified Data.ByteString as BS
import Control.Exception (SomeException, try)
import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(parseJSON), ToJSON(toJSON), eitherDecodeStrict, object
  , withObject, (.:), (.:?), (.=)
  )
import Data.Bifunctor (first)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import System.FilePath ((</>))

import QxFx0.Semantic.Content.Base
  ( PredicateRole(..)
  , SemanticPredicate(..)
  , mkArguedPred
  )
import QxFx0.Semantic.Content (DefinitionContent(..), definitionCorpus, normalizeTopic)

-- | A single predicate inside a curated entry.
data CuratedPredicateItem = CuratedPredicateItem
  { cpiRu :: !Text
  , cpiEn :: !Text
  , cpiKind :: !Text
  , cpiRationale :: !(Maybe Text)
  , cpiCounter :: !(Maybe Text)
  , cpiSynthesis :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON CuratedPredicateItem where
  toJSON item = object
    [ "ru"         .= cpiRu item
    , "en"         .= cpiEn item
    , "kind"       .= cpiKind item
    , "rationale"  .= cpiRationale item
    , "counter"    .= cpiCounter item
    , "synthesis"  .= cpiSynthesis item
    ]

instance FromJSON CuratedPredicateItem where
  parseJSON = withObject "CuratedPredicateItem" $ \o ->
    CuratedPredicateItem
      <$> o .:  "ru"
      <*> o .:  "en"
      <*> o .:  "kind"
      <*> o .:? "rationale"
      <*> o .:? "counter"
      <*> o .:? "synthesis"

-- | One curated topic with a list of predicates.
data CuratedPredicateEntry = CuratedPredicateEntry
  { cpeTopic :: !Text
  , cpePredicates :: ![CuratedPredicateItem]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON CuratedPredicateEntry where
  toJSON entry = object
    [ "topic"      .= cpeTopic entry
    , "predicates" .= cpePredicates entry
    ]

instance FromJSON CuratedPredicateEntry where
  parseJSON = withObject "CuratedPredicateEntry" $ \o ->
    CuratedPredicateEntry
      <$> o .: "topic"
      <*> o .: "predicates"

-- | Default path to the curated predicates file, relative to the project
-- knowledge directory.
curatedPredicatesPath :: FilePath
curatedPredicatesPath = "resources" </> "knowledge" </> "curated_predicates.jsonl"

-- | Convert the loose textual 'kind' field into a typed 'PredicateRole'.
parsePredicateKind :: Text -> PredicateRole
parsePredicateKind k = case T.toLower (T.strip k) of
  "rel"      -> RoleRelation
  "relation" -> RoleRelation
  "structure" -> RoleStructure
  "diff"      -> RoleDifferentiator
  "differentiator" -> RoleDifferentiator
  _           -> RoleProperty

-- | Build a 'SemanticPredicate' from a curated item.
semanticPredicateFromItem :: CuratedPredicateItem -> SemanticPredicate
semanticPredicateFromItem item =
  mkArguedPred
    (parsePredicateKind (cpiKind item))
    (T.strip (cpiRu item))
    (T.strip (cpiEn item))
    (T.strip <$> cpiRationale item)
    (T.strip <$> cpiCounter item)
    (T.strip <$> cpiSynthesis item)

-- | Build a 'DefinitionContent' from a curated entry.
definitionContentFromEntry :: CuratedPredicateEntry -> DefinitionContent
definitionContentFromEntry entry = DefinitionContent
  { dcTopic = normalizeTopic (cpeTopic entry)
  , dcPredicates = map semanticPredicateFromItem (cpePredicates entry)
  }

-- | Load curated predicates from a JSONL file.
-- Each line must be a valid 'CuratedPredicateEntry' JSON object.
loadCuratedPredicates :: FilePath -> IO (Map Text DefinitionContent)
loadCuratedPredicates path = do
  contents <- BS.readFile path
  let lines' = filter (not . BS.null) (BS.split 0x0A contents)
      decodeLine :: BS.ByteString -> Either String CuratedPredicateEntry
      decodeLine = eitherDecodeStrict
  entries <- mapM (\line -> case decodeLine line of
    Left err -> fail ("Failed to parse curated predicate line: " ++ err)
    Right e  -> pure e) lines'
  pure $ M.fromList
    [ (normalizeTopic (cpeTopic e), definitionContentFromEntry e)
    | e <- entries
    ]

-- | Load the bundled curated predicates and merge them into the
-- hardcoded seed corpus.  If the file is missing or fails to parse,
-- falls back to the seed corpus only.
extendedDefinitionCorpus :: IO (Map Text DefinitionContent)
extendedDefinitionCorpus = do
  result <- try @SomeException (loadCuratedPredicates curatedPredicatesPath)
  case result of
    Left _    -> pure definitionCorpus
    Right cur -> pure (mergeCuratedIntoDefinitionCorpus cur definitionCorpus)

-- | Merge curated predicates into the seed definition corpus.
-- Curated entries override seed entries on topic key collision.
mergeCuratedIntoDefinitionCorpus
  :: Map Text DefinitionContent
  -- ^ Curated predicates.
  -> Map Text DefinitionContent
  -- ^ Seed corpus.
  -> Map Text DefinitionContent
mergeCuratedIntoDefinitionCorpus curated seed =
  M.unionWith mergeTopic curated seed
  where
    mergeTopic curatedEntry seedEntry =
      seedEntry { dcPredicates = dcPredicates curatedEntry ++ dcPredicates seedEntry }
