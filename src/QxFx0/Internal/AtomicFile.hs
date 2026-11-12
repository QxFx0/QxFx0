{-# LANGUAGE ScopedTypeVariables #-}

-- | Atomic file replacement with a durability barrier.
--
-- The three writers that replace a file in place (feedback mirror, tuned
-- calibration config, Agda witness) used to write a temp file, close the
-- handle and rename it.  'hClose' only flushes user-space buffers into the
-- page cache; a crash between the rename and the filesystem's writeback can
-- leave an empty or truncated file where a valid one was.  'rename' gives
-- atomic visibility, not durability.
--
-- This module is the single implementation of the barrier:
--
-- 1. write the temp file in the target directory (same filesystem, so the
--    rename is atomic);
-- 2. flush the handle and @fsync@ the file descriptor — the bytes are on the
--    device before the name changes;
-- 3. rename over the target;
-- 4. @fsync@ the directory so the rename itself survives (best effort: some
--    filesystems reject directory fsync and the write is already visible).
--
-- A failure before the rename removes the temp file and leaves the target
-- untouched.  Pre-registration: @docs/closure/TMP_FSYNC_PREREG_2026-11-11.md@.
module QxFx0.Internal.AtomicFile
  ( atomicWriteFile
  ) where

import Control.Exception (IOException, bracket, bracketOnError, catch, finally)
import qualified Data.ByteString.Lazy as BL
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (Handle, hClose, openTempFile)
import System.Posix.IO
  ( OpenMode(ReadOnly)
  , closeFd
  , defaultFileFlags
  , handleToFd
  , openFd
  )
import System.Posix.Unistd (fileSynchronise)

-- | Replace @path@ with @content@ atomically and durably.
atomicWriteFile :: FilePath -> BL.ByteString -> IO ()
atomicWriteFile path content = do
  let dir = takeDirectory path
      -- No dot in the template: 'openTempFile' inserts its random part before
      -- the extension, so a @.tmp@ suffix would hide the marker from the
      -- leftover checks.
      template = takeFileName path <> "-tmp"
  createDirectoryIfMissing True dir
  bracketOnError
    (openTempFile dir template)
    (\(tmpPath, h) -> do
        ignoreIO (hClose h)
        ignoreIO (removeFile tmpPath))
    (\(tmpPath, h) -> do
        BL.hPutStr h content
        syncHandle h
        renameFile tmpPath path
        syncDirectory dir)

-- | Flush the handle and force its bytes to the device before closing it.
syncHandle :: Handle -> IO ()
syncHandle h = do
  fd <- handleToFd h
  fileSynchronise fd `finally` closeFd fd

-- | Best-effort directory barrier: the rename is already visible, so a
-- filesystem that rejects directory fsync must not turn a completed write
-- into an exception.
syncDirectory :: FilePath -> IO ()
syncDirectory dir =
  ignoreIO (bracket (openFd dir ReadOnly defaultFileFlags) closeFd fileSynchronise)

ignoreIO :: IO () -> IO ()
ignoreIO action = action `catch` \(_ :: IOException) -> pure ()
