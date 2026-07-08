{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

module QxFx0.CLI.Ingest
  ( IngestOptions(..)
  , IngestSummary(..)
  , defaultIngestOptions
  , parseIngestArgs
  , runIngest
  , formatIngestSummary
  ) where

import Control.Exception (SomeException, try)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Network.Ingest
  ( LoadedRelation
  , loadRelations
  , semanticNetworkFromLoaded
  )
import QxFx0.Semantic.Network.Types
  ( SemanticEdge(..)
  , SemanticNetwork(..)
  , EdgeProvenance(..)
  )
import QxFx0.Semantic.Ontology (Ontology(..), loadOntology)
import QxFx0.Semantic.Content.AtomStore (RelationType)

-- | Paths required by the @ingest@ command.
data IngestOptions = IngestOptions
  { ioRelations :: !FilePath
  , ioOntology  :: !FilePath
  } deriving stock (Eq, Show)

-- | Human-readable result of an ingest run.
data IngestSummary = IngestSummary
  { isRelationsCount    :: !Int
  , isOntologyNodeCount :: !Int
  , isNetworkNodeCount  :: !Int
  , isNetworkEdgeCount  :: !Int
  , isSampleEdge        :: !(Maybe (Text, Text, Text, Text))
  } deriving stock (Eq, Show)

-- | Canonical resource paths used when no flags are supplied.
defaultIngestOptions :: IngestOptions
defaultIngestOptions = IngestOptions
  { ioRelations = "resources/knowledge/relations.jsonl"
  , ioOntology  = "resources/knowledge/ontology.jsonl"
  }

-- | Parse the argument tail following the @ingest@ command.
--
-- Recognizes @--relations <path>@ and @--ontology <path>@.  Unknown
-- tokens or dangling flags make parsing fail.
parseIngestArgs :: [String] -> Maybe IngestOptions
parseIngestArgs = go defaultIngestOptions
  where
    go :: IngestOptions -> [String] -> Maybe IngestOptions
    go opts [] = Just opts
    go opts ("--relations":path:rest) = go (opts { ioRelations = path }) rest
    go opts ("--ontology":path:rest)  = go (opts { ioOntology = path }) rest
    go _    _                         = Nothing

-- | Run an ingest and return a summary, or an error message on failure.
runIngest :: IngestOptions -> IO (Either Text IngestSummary)
runIngest opts = do
  result <- try $ do
    ontology     <- loadOntology (ioOntology opts)
    rawRelations <- loadRelations (ioRelations opts)
    let network = semanticNetworkFromLoaded ontology rawRelations
    pure (ontology, rawRelations, network)
  case result of
    Left exc -> pure (Left ("Ingest failed: " <> T.pack (show (exc :: SomeException))))
    Right (ontology, rawRelations, network) ->
      pure (Right (mkSummary ontology rawRelations network))

mkSummary :: Ontology -> [LoadedRelation] -> SemanticNetwork -> IngestSummary
mkSummary ontology rawRelations network =
  let sample = case M.lookupMin (snEdges network) of
        Nothing         -> Nothing
        Just (_, edge) ->
          Just ( seFrom edge
               , seTo edge
               , renderRelationType (seRelationType edge)
               , renderProvenance (seProvenance edge)
               )
  in IngestSummary
      { isRelationsCount    = length rawRelations
      , isOntologyNodeCount = M.size (otNodes ontology)
      , isNetworkNodeCount  = S.size (snNodes network)
      , isNetworkEdgeCount  = M.size (snEdges network)
      , isSampleEdge        = sample
      }

renderRelationType :: Maybe RelationType -> Text
renderRelationType Nothing  = "unknown"
renderRelationType (Just rt) = T.pack (show rt)

renderProvenance :: EdgeProvenance -> Text
renderProvenance p = T.pack (show p)

-- | Render the summary for stdout.
formatIngestSummary :: IngestSummary -> Text
formatIngestSummary s = T.unlines
  [ "Relations loaded: " <> T.pack (show (isRelationsCount s))
  , "Ontology nodes loaded: " <> T.pack (show (isOntologyNodeCount s))
  , "Semantic network nodes: " <> T.pack (show (isNetworkNodeCount s))
  , "Semantic network edges: " <> T.pack (show (isNetworkEdgeCount s))
  , case isSampleEdge s of
      Nothing                -> "Sample edge: none"
      Just (fromN, toN, rt, prov) ->
        "Sample edge: " <> fromN <> " -> " <> toN
          <> " [" <> rt <> "] (" <> prov <> ")"
  ]
