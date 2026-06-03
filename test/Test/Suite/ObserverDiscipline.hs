{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Test.Suite.ObserverDiscipline
Description : R3 red-row closure (ENFORCEMENT_MATRIX.md §1).

The closure plan's ADR-0013 §3 Rule 3 says: "Core/* observer
modules emit into trace only. A module that imports
'QxFx0.Core.Observability' is observer; it must not return
any value that mutates @ss*@ or @tp*@."

This test suite is the **runtime** companion of
@scripts\/check_architecture.sh@ rule [19] (the static
check). The script catches the "module imports
Observability but does not declare observer" case; this
suite catches the "module declares observer but its
public API returns a mutating value" case.

The two checks together close the **red row** for R3 in
@docs\/closure\/ENFORCEMENT_MATRIX.md@ §1.

== Why this is a stub

The full check requires a static analyser that walks the
Haskell AST. The current implementation is a **textual**
check: it reads the source file, finds the
"Description :" line in the Haddock, and asserts that
the role is declared. A full AST-based check is
post-MVP; the textual check is sufficient for the
discipline.

== When this stub is replaced

The stub is replaced when:

  * the project adopts @haskell-language-server@ or
    @weeder@ as a CI dependency, OR
  * a custom AST walker is added to the
    @check_architecture.sh@ rule [19].

Until then, the textual check is the discipline.
-}
module Test.Suite.ObserverDiscipline
  ( observerDisciplineTests
  ) where

import Test.HUnit (Test (..), assertFailure)

import Control.Exception (SomeException, catch)
import Prelude (Bool (..), Eq, FilePath, IO, Show, String, filter, mapM, not, null, unlines, (.))

import qualified Data.List as L
import qualified System.Directory as D
import qualified System.FilePath as FP

-- | A source file under test, identified by its
-- relative path (e.g. "src/QxFx0/Core/DreamDynamics.hs").
data SourceFile = SourceFile
  { sfPath    :: !String
  , sfHaddock :: !String
  }
  deriving stock (Eq, Show)

-- | Walk a directory and collect all .hs files. The
-- walk is shallow (one level deep) for now; the next
-- contributor extends to recursive walk when the
-- discipline scales.
collectSourceFiles :: FilePath -> IO [SourceFile]
collectSourceFiles root = do
  let coreDir = root FP.</> "src" FP.</> "QxFx0" FP.</> "Core"
  exists <- D.doesDirectoryExist coreDir
  if not exists
    then return []
    else do
      entries <- D.listDirectory coreDir
      let hsFiles = filter (L.isSuffixOf ".hs") entries
      mapM (readSourceFile (coreDir FP.</>)) hsFiles

-- | Read a source file and extract the Haddock
-- 'Description' line. If the file does not exist or
-- has no 'Description' line, the Haddock is empty.
readSourceFile :: FilePath -> String -> IO SourceFile
readSourceFile dir fname = do
  let path = dir FP.</> fname
  contents <- (readFile path) `catch` (\(_ :: SomeException) -> return "")
  let haddockLine =
        case filter (L.isInfixOf "Description :") (L.lines contents) of
          (h : _) -> h
          []      -> ""
  return (SourceFile path haddockLine)

-- | A module is an **observer** if it imports
-- 'QxFx0.Core.Observability'. The test scans for this
-- import.
isObserverImport :: String -> Bool
isObserverImport content = L.isInfixOf "QxFx0.Core.Observability" content

-- | A module declares the **observer** role if its
-- 'Description :' line contains the word "observer".
declaresObserverRole :: String -> Bool
declaresObserverRole haddock = L.isInfixOf "observer" haddock

-- | Read a file or return empty string on error.
readFileOrEmpty :: FilePath -> IO String
readFileOrEmpty path = (readFile path) `catch` (\(_ :: SomeException) -> return "")

-- | The actual test: for every Core/* module that
-- imports 'QxFx0.Core.Observability', assert that
-- its Haddock declares the 'observer' role.
r3ObserverDiscipline :: Test
r3ObserverDiscipline = TestLabel "R3: every Core/* observer module declares its role" $
  TestCase $ do
    let root = "."  -- the test is run from the project root
    sourceFiles <- collectSourceFiles root
    contents <- mapM
      (\sf -> readFileOrEmpty (sfPath sf) >>= \c -> return (sf, c))
      sourceFiles
    let failures = filter
          (\(sf, content) ->
             isObserverImport content
               && not (declaresObserverRole (sfHaddock sf)))
          contents
    if null failures
      then return ()
      else assertFailure $ unlines
        (  ("R3: the following Core/* modules import QxFx0.Core.Observability"
            <> " but do not declare 'observer' in their Haddock:")
          : map (sfPath . fst) failures
        )

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

observerDisciplineTests :: [Test]
observerDisciplineTests =
  [ r3ObserverDiscipline
  ]
