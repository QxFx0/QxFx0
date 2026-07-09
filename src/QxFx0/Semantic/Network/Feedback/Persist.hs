{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback.Persist
  ( persistFeedbackNetwork
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)

import QxFx0.Semantic.Network.Types (SemanticEdge(..), SemanticNetwork(..))

-- | Persist edges that changed as a result of feedback to a JSONL file.
--
-- The comparison is made against the previous network; any edge whose
-- confidence or rationale differs, plus any edge that did not exist in
-- the previous network, is appended as a JSON line.  This is a minimal
-- viable append-only tuning log.
persistFeedbackNetwork :: FilePath -> SemanticNetwork -> SemanticNetwork -> IO ()
persistFeedbackNetwork path previousNetwork updatedNetwork = do
  let previousEdges = snEdges previousNetwork
      changedEdges =
        [ edge
        | (_key, edge) <- M.toList (snEdges updatedNetwork)
        , case M.lookup (seFrom edge, seTo edge) previousEdges of
            Nothing      -> True
            Just oldEdge ->
              seConfidence edge /= seConfidence oldEdge
              || seRationale edge /= seRationale oldEdge
        ]
  createDirectoryIfMissing True (takeDirectory path)
  BL.appendFile path (BL.concat (map encodeLine changedEdges))
  where
    encodeLine edge = Aeson.encode edge <> BL.singleton 0x0a
