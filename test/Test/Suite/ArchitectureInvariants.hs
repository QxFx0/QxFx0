module Test.Suite.ArchitectureInvariants
  ( architectureInvariantTests
  ) where

import Control.Monad (forM)
import Data.List (isPrefixOf, sort)
import System.Directory (doesDirectoryExist, getCurrentDirectory, listDirectory)
import System.FilePath ((</>), takeExtension)
import Test.HUnit

architectureInvariantTests :: [Test]
architectureInvariantTests =
  [ TestLabel "Self layer stays foundational" testSelfLayerStaysFoundational
  ]

testSelfLayerStaysFoundational :: Test
testSelfLayerStaysFoundational = TestCase $ do
  root <- getCurrentDirectory
  files <- listHsFilesRecursive (root </> "src" </> "QxFx0" </> "Self")
  violations <- fmap sort (concat <$> mapM forbiddenImportsInFile files)
  assertEqual
    "QxFx0.Self modules must not import runtime, bridge, render, CLI, or app layers"
    []
    violations

forbiddenImportsInFile :: FilePath -> IO [String]
forbiddenImportsInFile filePath = do
  contents <- lines <$> readFile filePath
  pure
    [ filePath <> ":" <> show lineNo <> ": " <> line
    | (lineNo, line) <- zip [1 :: Int ..] contents
    , let trimmed = dropWhile (`elem` [' ', '\t']) line
    , any (`isPrefixOf` trimmed) forbiddenImportPrefixes
    ]

listHsFilesRecursive :: FilePath -> IO [FilePath]
listHsFilesRecursive dir = do
  entries <- sort <$> listDirectory dir
  fmap concat $ forM entries $ \entry -> do
    let entryPath = dir </> entry
    isDir <- doesDirectoryExist entryPath
    if isDir
      then listHsFilesRecursive entryPath
      else pure [entryPath | takeExtension entryPath == ".hs"]

forbiddenImportPrefixes :: [String]
forbiddenImportPrefixes =
  [ "import QxFx0.Runtime"
  , "import qualified QxFx0.Runtime"
  , "import QxFx0.Bridge"
  , "import qualified QxFx0.Bridge"
  , "import QxFx0.Render"
  , "import qualified QxFx0.Render"
  , "import QxFx0.CLI"
  , "import qualified QxFx0.CLI"
  , "import QxFx0.App"
  , "import qualified QxFx0.App"
  ]
