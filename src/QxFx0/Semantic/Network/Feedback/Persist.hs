{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback.Persist
  ( persistFeedbackNetwork
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (foldl')
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Ingest (LoadedRelation(..), loadRelations)
import QxFx0.Semantic.Network.Types (EdgeProvenance(..), SemanticEdge(..), SemanticNetwork(..))

-- | Persist edges that changed as a result of feedback to a JSONL file.
--
-- Reads the existing file (if any), builds a map keyed by
-- @(from, to, relation type)@, replaces entries for edges that changed
-- in this turn, and writes the merged map back as JSONL.  This prevents
-- the unbounded append-only growth of the original implementation while
-- keeping the same JSONL format.
persistFeedbackNetwork :: FilePath -> SemanticNetwork -> SemanticNetwork -> IO ()
persistFeedbackNetwork path previousNetwork updatedNetwork = do
  let previousEdges = snEdges previousNetwork
      changedEdges =
        [ edge
        | edge <- M.elems (snEdges updatedNetwork)
        , case M.lookup (seFrom edge, seTo edge) previousEdges of
            Nothing      -> True
            Just oldEdge -> oldEdge /= edge
        ]
  existing <- loadExisting path
  let baseMap = M.fromList [ (loadedKey lr, lr) | lr <- existing ]
      merged = foldl' (insertChanged previousEdges) baseMap changedEdges
  createDirectoryIfMissing True (takeDirectory path)
  BL.writeFile path (BL.concat [Aeson.encode lr <> BL.singleton 0x0a | lr <- M.elems merged])
  where
    loadExisting p = do
      exists <- doesFileExist p
      if exists
        then loadRelations p
        else pure []

    loadedKey lr = (lrFrom lr, lrTo lr, lrType lr)

    edgeKey edge = (seFrom edge, seTo edge, fromMaybe RelRelatedTo (seRelationType edge))

    insertChanged prevEdges acc edge =
      let newRel = edgeToLoadedRelation edge
          newKey = edgeKey edge
          oldKey = case M.lookup (seFrom edge, seTo edge) prevEdges of
                     Nothing      -> Nothing
                     Just oldEdge -> Just (edgeKey oldEdge)
          acc' = maybe acc (\k -> M.delete k acc) oldKey
      in M.insert newKey newRel acc'

    edgeToLoadedRelation edge =
      LoadedRelation
        { lrFrom       = seFrom edge
        , lrTo         = seTo edge
        , lrType       = fromMaybe RelRelatedTo (seRelationType edge)
        , lrVerb       = seVerb edge
        , lrRationale  = seRationale edge
        , lrCounter    = seCounter edge
        , lrSynthesis  = seSynthesis edge
        , lrConfidence = seConfidence edge
        , lrAuthor     = authorFromProvenance (seProvenance edge)
        , lrVersion    = 1
        }
      where
        authorFromProvenance ProvenanceDialogueFeedback = "dialogue_feedback"
        authorFromProvenance ProvenanceSelfPlay         = "selfplay"
        authorFromProvenance ProvenanceCurated          = "curated"
        authorFromProvenance ProvenanceCorpus           = "corpus"
        authorFromProvenance ProvenanceSubstrate        = "substrate"
        authorFromProvenance ProvenanceIngested         = "ingested"
