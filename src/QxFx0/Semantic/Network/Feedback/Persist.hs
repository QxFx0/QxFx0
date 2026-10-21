{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module QxFx0.Semantic.Network.Feedback.Persist
  ( persistFeedbackNetwork
  ) where

import Control.Exception (IOException, bracketOnError, catch)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (foldl')
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , removeFile
  , renameFile
  )
import System.FilePath (takeDirectory, takeFileName)
import System.IO (hClose, hPutStrLn, openTempFile, stderr)

import QxFx0.ExceptionPolicy (tryIO)
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Ingest (LoadedRelation(..))
import QxFx0.Semantic.Network.Types (EdgeProvenance(..), SemanticEdge(..), SemanticNetwork(..))

-- | Persist edges that changed as a result of feedback to a JSONL file.
--
-- Reads the existing file (if any), builds a map keyed by
-- @(from, to, relation type)@, replaces entries for edges that changed
-- in this turn, and writes the merged map back as JSONL.  This prevents
-- the unbounded append-only growth of the original implementation while
-- keeping the same JSONL format.
--
-- Audit 2026-10-16 п.9: the mirror is runtime data, not a curated
-- corpus, so reading is resilient (malformed lines are skipped with one
-- warning and disappear on the next rewrite) and writing is atomic
-- (unique temp file + rename).  A read error other than "missing file"
-- aborts the rewrite instead of clobbering the history with partial
-- data; the caller stays best-effort.
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
  mExisting <- loadExisting path
  case mExisting of
    Nothing -> pure ()
    Just existing -> do
      let baseMap = M.fromList [ (loadedKey lr, lr) | lr <- existing ]
          merged = foldl' (insertChanged previousEdges) baseMap changedEdges
      writeMirrorAtomically path
        (BL.concat [Aeson.encode lr <> BL.singleton 0x0A | lr <- M.elems merged])
  where
    -- 'Just' carries the surviving rows; 'Nothing' means the file exists
    -- but could not be read, so the rewrite must not proceed.
    loadExisting p = do
      exists <- doesFileExist p
      if not exists
        then pure (Just [])
        else do
          readResult <- tryIO (BS.readFile p)
          case readResult of
            Left err -> do
              hPutStrLn stderr $
                "[feedback-mirror] read failed: " <> p <> ": " <> show err
                  <> "; mirror left unchanged"
              pure Nothing
            Right bytes -> do
              let rawLines = filter (not . BS.null) (BS.split 0x0A bytes)
                  decoded = map Aeson.eitherDecodeStrict rawLines
                  surviving = [lr | Right lr <- decoded]
                  skipped = length [() | Left _ <- decoded]
              if skipped > 0
                then hPutStrLn stderr $
                  "[feedback-mirror] skipped " <> show skipped
                    <> " malformed line(s) in " <> p
                else pure ()
              pure (Just surviving)

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
        authorFromProvenance ProvenanceRuntimeLLM       = "runtime_llm"
        authorFromProvenance ProvenanceHumanCorrection  = "human_correction"
        authorFromProvenance ProvenanceDerived          = "derived"

-- | Write via a unique temp file in the target directory, then rename
-- over the target: the target is always either the previous complete
-- file or the new complete file, never a partial JSONL.  On any
-- failure the temp file is closed and removed (best-effort) and the
-- exception propagates to the best-effort post-commit caller.
writeMirrorAtomically :: FilePath -> BL.ByteString -> IO ()
writeMirrorAtomically path content = do
  let dir = takeDirectory path
      -- No dot in the template: 'openTempFile' inserts its random part
      -- before the extension, so a @.tmp@ suffix would hide the marker
      -- from the leftover checks.
      template = takeFileName path <> "-tmp"
  createDirectoryIfMissing True dir
  bracketOnError
    (openTempFile dir template)
    (\(tmpPath, h) -> do
        ignoreIO (hClose h)
        ignoreIO (removeFile tmpPath))
    (\(tmpPath, h) -> do
        BL.hPutStr h content
        hClose h
        renameFile tmpPath path)

ignoreIO :: IO () -> IO ()
ignoreIO action = action `catch` \(_ :: IOException) -> pure ()
