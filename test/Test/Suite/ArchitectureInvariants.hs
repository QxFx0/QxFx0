module Test.Suite.ArchitectureInvariants
  ( architectureInvariantTests
  ) where

import Control.Monad (forM)
import Data.List (isPrefixOf, sort)
import System.Directory (doesDirectoryExist, getCurrentDirectory, listDirectory)
import System.FilePath ((</>), takeExtension)
import Test.HUnit

-- | Per ADR-0013 §3 Rule 2: a "supplier" Core
-- module must not import a canonical-orchestrator
-- writer. The supplier subtree is
-- 'QxFx0.Core.Consciousness.*'; the orchestrator
-- writers are the 'QxFx0.Core.TurnPipeline.*'
-- subtree plus 'QxFx0.Core.TurnRouting' (and
-- 'QxFx0.Core.TurnPlanning', 'QxFx0.Core.TurnRender',
-- 'QxFx0.Core.TurnLegitimacy', which are sibling
-- orchestrators of the TurnPipeline).
--
-- This test is the R2 (test) yellow row in
-- 'docs/closure/ENFORCEMENT_MATRIX.md'. Closing
-- it brings the matrix to 6G/1Y/0R.
architectureInvariantTests :: [Test]
architectureInvariantTests =
  [ TestLabel "Self layer stays foundational" testSelfLayerStaysFoundational
  , TestLabel "R2: Core/Consciousness/* supplier does not import canonical-orchestrator writers"
      testR2SupplierDoesNotImportOrchestrator
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

-- | R2: walk 'QxFx0.Core.Consciousness/*' and
-- assert that no file imports the canonical
-- orchestrator writers. This is the inverse of
-- the R1 test ('testSelfLayerStaysFoundational'):
-- R1 says "Self must not import runtime-y
-- things"; R2 says "the supplier (Consciousness)
-- must not import the orchestrator (TurnPipeline,
-- TurnRouting)".
testR2SupplierDoesNotImportOrchestrator :: Test
testR2SupplierDoesNotImportOrchestrator = TestCase $ do
  root <- getCurrentDirectory
  files <- listHsFilesRecursive
             (root </> "src" </> "QxFx0" </> "Core" </> "Consciousness")
  violations <-
    fmap sort (concat <$> mapM forbiddenOrchestratorImportsInFile files)
  assertEqual
    ("QxFx0.Core.Consciousness supplier must not import "
     <> "QxFx0.Core.TurnPipeline.*, QxFx0.Core.TurnRouting, "
     <> "QxFx0.Core.TurnPlanning, QxFx0.Core.TurnRender, "
     <> "or QxFx0.Core.TurnLegitimacy (per ADR-0013 §3 R2)")
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

-- | R2-specific helper. Same shape as
-- 'forbiddenImportsInFile' but with a different
-- forbidden list. The two helpers exist separately
-- so that the R1 and R2 test failure messages
-- cite the right rule.
forbiddenOrchestratorImportsInFile :: FilePath -> IO [String]
forbiddenOrchestratorImportsInFile filePath = do
  contents <- lines <$> readFile filePath
  pure
    [ filePath <> ":" <> show lineNo <> ": " <> line
    | (lineNo, line) <- zip [1 :: Int ..] contents
    , let trimmed = dropWhile (`elem` [' ', '\t']) line
    , any (`isPrefixOf` trimmed) forbiddenOrchestratorImportPrefixes
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

-- | R2 forbidden list. The 'QxFx0.Core.Turn*'
-- subtrees are the canonical-orchestrator writers
-- (per ADR-0013 §3 and the role split). A supplier
-- (QxFx0.Core.Consciousness) must not import them.
--
-- The list is intentionally **specific** (not
-- "QxFx0.Core.Turn*" generic) to allow other
-- QxFx0.Core.Turn* modules that are not writers
-- (e.g. QxFx0.Core.TurnModulation is a calibration
-- struct, not a writer). The test is the static
-- companion of the more general
-- 'check_architecture.sh' rule [14] (which uses
-- Haddock + import heuristics).
forbiddenOrchestratorImportPrefixes :: [String]
forbiddenOrchestratorImportPrefixes =
  [ "import QxFx0.Core.TurnPipeline"
  , "import qualified QxFx0.Core.TurnPipeline"
  , "import QxFx0.Core.TurnRouting"
  , "import qualified QxFx0.Core.TurnRouting"
  , "import QxFx0.Core.TurnPlanning"
  , "import qualified QxFx0.Core.TurnPlanning"
  , "import QxFx0.Core.TurnRender"
  , "import qualified QxFx0.Core.TurnRender"
  , "import QxFx0.Core.TurnLegitimacy"
  , "import qualified QxFx0.Core.TurnLegitimacy"
  ]
