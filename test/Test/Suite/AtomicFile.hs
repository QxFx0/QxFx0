{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Test.Suite.AtomicFile
  ( atomicFileTests
  ) where

import Control.Exception (SomeException, try)
import qualified Data.ByteString.Lazy as BL
import Data.Either (isLeft)
import Data.List (isPrefixOf)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , removePathForcibly
  )
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.Posix.Files (fileID, getFileStatus)
import Test.HUnit

import QxFx0.Internal.AtomicFile (atomicWriteFile)
import Test.Support (freshTestPath, removeIfExists)

-- | Pins for the fsync barrier (pre-registration:
-- @docs/closure/TMP_FSYNC_PREREG_2026-11-11.md@).
--
-- The durability itself (fsync before rename, directory fsync after) is not
-- observable from a unit test; it is pinned by the strace evidence in the
-- pre-registration.  These cases pin the invariants the barrier must not
-- break: byte-exact content, rename (new inode), no temp leftovers, the old
-- target surviving a failed rename, and parent-directory creation.
atomicFileTests :: [Test]
atomicFileTests =
  [ testWritesContent
  , testOverwriteChangesInode
  , testFailedRenameLeavesTargetAndCleansTemp
  , testCreatesMissingParent
  , testRepeatedWritesLeaveNoTempFiles
  ]

tempLeftovers :: FilePath -> IO [FilePath]
tempLeftovers path = do
  entries <- listDirectory (takeDirectory path)
  pure (filter ((takeFileName path <> "-tmp") `isPrefixOf`) entries)

testWritesContent :: Test
testWritesContent = TestLabel "atomic write round-trips content" $ TestCase $ do
  path <- freshTestPath "qxfx0_atomic_file_content.bin"
  let payload = BL.replicate 5000000 65
  atomicWriteFile path payload
  actual <- BL.readFile path
  leftovers <- tempLeftovers path
  removeIfExists path
  assertBool "content must round-trip byte for byte" (payload == actual)
  assertEqual "no temp file may remain after a successful write" [] leftovers

testOverwriteChangesInode :: Test
testOverwriteChangesInode = TestLabel "overwrite replaces the file via rename" $ TestCase $ do
  path <- freshTestPath "qxfx0_atomic_file_inode.bin"
  atomicWriteFile path "first"
  before <- getFileStatus path
  atomicWriteFile path "second"
  after <- getFileStatus path
  actual <- BL.readFile path
  removeIfExists path
  assertBool "the rewrite must replace the inode" (fileID before /= fileID after)
  assertEqual "the new content must win" "second" actual

testFailedRenameLeavesTargetAndCleansTemp :: Test
testFailedRenameLeavesTargetAndCleansTemp =
  TestLabel "a failed rename leaves the target untouched and removes the temp" $ TestCase $ do
    dir <- freshTestPath "qxfx0_atomic_file_target_dir"
    createDirectoryIfMissing True dir
    result <- try @SomeException (atomicWriteFile dir "payload")
    stillDir <- doesDirectoryExist dir
    leftovers <- tempLeftovers dir
    removePathForcibly dir
    assertBool "a directory target must fail the write" (isLeft result)
    assertBool "the target must be untouched" stillDir
    assertEqual "a failed write must not leave a temp file behind" [] leftovers

testCreatesMissingParent :: Test
testCreatesMissingParent = TestLabel "missing parent directories are created" $ TestCase $ do
  base <- freshTestPath "qxfx0_atomic_file_nested"
  let path = base </> "a" </> "b" </> "file.txt"
  atomicWriteFile path "nested"
  exists <- doesFileExist path
  actual <- BL.readFile path
  removePathForcibly base
  assertBool "the nested file must exist" exists
  assertEqual "the nested content must round-trip" "nested" actual

testRepeatedWritesLeaveNoTempFiles :: Test
testRepeatedWritesLeaveNoTempFiles =
  TestLabel "repeated writes leave no temp files" $ TestCase $ do
    path <- freshTestPath "qxfx0_atomic_file_repeat.bin"
    mapM_ (\i -> atomicWriteFile path (BL.replicate 1000 (fromIntegral i))) [1 .. 5 :: Int]
    leftovers <- tempLeftovers path
    entries <- listDirectory (takeDirectory path)
    removeIfExists path
    assertEqual "no temp file may remain after repeated writes" [] leftovers
    assertBool "the target must still be the only matching file"
      (length (filter ((takeFileName path) `isPrefixOf`) entries) == 1)
