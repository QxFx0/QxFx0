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
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)

import QxFx0.Semantic.Network.Ingest
  ( LoadedRelation
  , loadRelations
  , mergeSelfPlayRelations
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
  , ioSelfPlay  :: !(Maybe FilePath)
  } deriving stock (Eq, Show)

-- | Human-readable result of an ingest run.
data IngestSummary = IngestSummary
  { isRelationsCount    :: !Int
  , isOntologyNodeCount :: !Int
  , isNetworkNodeCount  :: !Int
  , isNetworkEdgeCount  :: !Int
  , isSampleEdge        :: !(Maybe (Text, Text, Text, Text))
  , isSelfPlayEdgeCount :: !Int
  } deriving stock (Eq, Show)

-- | Canonical resource paths used when no flags are supplied.
defaultSelfPlayPath :: FilePath
defaultSelfPlayPath = "resources/knowledge/selfplay_relations.jsonl"

defaultIngestOptions :: IngestOptions
defaultIngestOptions = IngestOptions
  { ioRelations = "resources/knowledge/relations.jsonl"
  , ioOntology  = "resources/knowledge/ontology.jsonl"
  , ioSelfPlay  = Nothing
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
    go opts ("--selfplay":rest)       =
      case rest of
        (path:rest') | not ("--" `isPrefixOf` path) ->
          go (opts { ioSelfPlay = Just path }) rest'
        _ -> go (opts { ioSelfPlay = Just defaultSelfPlayPath }) rest
    go _    _                         = Nothing

-- | Run an ingest and return a summary, or an error message on failure.
runIngest :: IngestOptions -> IO (Either Text IngestSummary)
runIngest opts = do
  result <- try $ do
    ontology     <- loadOntology (ioOntology opts)
    rawRelations <- loadRelations (ioRelations opts)
    let baseNetwork = semanticNetworkFromLoaded ontology rawRelations
    mergedNetwork  <- case ioSelfPlay opts of
      Nothing    -> pure baseNetwork
      Just spath -> do
        exists <- doesFileExist spath
        if exists
          then mergeSelfPlayRelations spath baseNetwork
          else pure baseNetwork
    pure (ontology, rawRelations, mergedNetwork)
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
      selfPlayCount = length (filter isSelfPlay (M.elems (snEdges network)))
      isSelfPlay e = seProvenance e == ProvenanceSelfPlay
  in IngestSummary
      { isRelationsCount    = length rawRelations
      , isOntologyNodeCount = M.size (otNodes ontology)
      , isNetworkNodeCount  = S.size (snNodes network)
      , isNetworkEdgeCount  = M.size (snEdges network)
      , isSampleEdge        = sample
      , isSelfPlayEdgeCount = selfPlayCount
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
  , "Self-play edges added: " <> T.pack (show (isSelfPlayEdgeCount s))
  , case isSampleEdge s of
      Nothing                -> "Sample edge: none"
      Just (fromN, toN, rt, prov) ->
        "Sample edge: " <> fromN <> " -> " <> toN
          <> " [" <> rt <> "] (" <> prov <> ")"
  ]
