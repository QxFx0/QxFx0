{-# LANGUAGE OverloadedStrings, TypeApplications #-}
{-| PGF load status (Lexicon resource layer).

    The compiled PGF grammar is a loaded resource, exactly like the GF function
    map ('QxFx0.Lexicon.GfMap.gfMapLoadStatus'). Keeping the load status here (a
    low layer with no Render/Core/Runtime dependencies) lets Render read it
    directly — Render → Lexicon is allowed, Render → Runtime is not.

    Pattern: unsafePerformIO + NOINLINE, same as 'gfMapLoadStatus'.
-}
module QxFx0.Lexicon.PGFStatus
  ( pgfRuntimeActive
  , pgfFallbackReason
  ) where

import Control.Exception (try, IOException)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.IO.Unsafe (unsafePerformIO)
import qualified PGF2 as PGF

-- | Global PGF load result, computed once at module load time.
pgfLoadResult :: (Maybe PGF.PGF, Maybe Text)
pgfLoadResult = unsafePerformIO loadPgfOnce
{-# NOINLINE pgfLoadResult #-}

-- | Load PGF file once, return (Just pgf, Nothing) on success or (Nothing, Just reason) on failure.
loadPgfOnce :: IO (Maybe PGF.PGF, Maybe Text)
loadPgfOnce = do
  let pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Nothing, Just ("pgf_file_not_found:" <> T.pack pgfPath))
    else do
      result <- try @IOException $ PGF.readPGF pgfPath
      case result of
        Left e -> pure (Nothing, Just ("pgf_io_error:" <> T.pack (show e)))
        Right pgf ->
          let langCount = length (PGF.languages pgf)
          in if langCount > 0
               then pure (Just pgf, Nothing)
               else pure (Nothing, Just "pgf_no_languages")

-- | True if PGF runtime is active (file loaded successfully).
pgfRuntimeActive :: Bool
pgfRuntimeActive = case fst pgfLoadResult of
  Just _  -> True
  Nothing -> False

-- | Reason why PGF runtime is not active (Nothing if active).
pgfFallbackReason :: Maybe Text
pgfFallbackReason = snd pgfLoadResult
