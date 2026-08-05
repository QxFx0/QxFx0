module Test.Suite.ArchitectureInvariants
  ( architectureInvariantTests
  ) where

import Control.Monad (forM)
import Data.List (isInfixOf, isPrefixOf, sort)
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory, listDirectory)
import System.FilePath ((</>), takeExtension)
import Test.HUnit

-- | Per ADR-0013 §3 Rule 2: a "supplier" Core
-- module must not import a canonical-orchestrator
-- writer. The supplier subtree is
-- 'QxFx0.Core.StanceClassifier.*'; the orchestrator
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
  , TestLabel "Types layer imports contracts only" testTypesLayerImportsContractsOnly
  , TestLabel "Semantic layer does not import Bridge" testSemanticLayerDoesNotImportBridge
  , TestLabel "runtime projection lives at the Bridge boundary" testRuntimeProjectionLivesInBridge
  , TestLabel "session bootstrap owns Self configuration" testSessionBootstrapOwnsSelfConfiguration
  , TestLabel "SystemState Types module stays contract-only" testSystemStateModuleIsContractOnly
  , TestLabel "R2: Core/StanceClassifier/* supplier does not import canonical-orchestrator writers"
      testR2SupplierDoesNotImportOrchestrator
  ]

testSelfLayerStaysFoundational :: Test
testSelfLayerStaysFoundational = TestCase $ do
  root <- getCurrentDirectory
  files <- listHsFilesRecursive (root </> "src" </> "QxFx0" </> "Self")
  violations <- fmap sort (concat <$> mapM forbiddenImportsInFile files)
  assertEqual
    "QxFx0.Self modules must not import runtime, bridge, render, CLI, app, or unsafe IO layers"
    []
    violations

testTypesLayerImportsContractsOnly :: Test
testTypesLayerImportsContractsOnly = TestCase $ do
  root <- getCurrentDirectory
  files <- listHsFilesRecursive (root </> "src" </> "QxFx0" </> "Types")
  violations <- fmap sort (concat <$> mapM implementationImportsInFile files)
  assertEqual
    "QxFx0.Types modules must not import implementation namespaces"
    []
    violations

implementationImportsInFile :: FilePath -> IO [String]
implementationImportsInFile filePath = do
  contents <- lines <$> readFile filePath
  pure
    [ filePath <> ":" <> show lineNo <> ": " <> line
    | (lineNo, line) <- zip [1 :: Int ..] contents
    , let trimmed = dropWhile (`elem` [' ', '\t']) line
    , any (`isPrefixOf` trimmed) forbiddenTypesImportPrefixes
    ]

-- | R2: walk 'QxFx0.Core.StanceClassifier/*' and
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
             (root </> "src" </> "QxFx0" </> "Core" </> "StanceClassifier")
  violations <-
    fmap sort (concat <$> mapM forbiddenOrchestratorImportsInFile files)
  assertEqual
    ("QxFx0.Core.StanceClassifier supplier must not import "
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
        || "unsafePerformIO" `isInfixOf` trimmed
    ]

testSemanticLayerDoesNotImportBridge :: Test
testSemanticLayerDoesNotImportBridge = TestCase $ do
  root <- getCurrentDirectory
  files <- listHsFilesRecursive (root </> "src" </> "QxFx0" </> "Semantic")
  violations <- fmap sort (concat <$> mapM bridgeImportsInFile files)
  assertEqual "QxFx0.Semantic modules must not import QxFx0.Bridge" [] violations

bridgeImportsInFile :: FilePath -> IO [String]
bridgeImportsInFile filePath = do
  contents <- lines <$> readFile filePath
  pure
    [ filePath <> ":" <> show lineNo <> ": " <> line
    | (lineNo, line) <- zip [1 :: Int ..] contents
    , let trimmed = dropWhile (`elem` [' ', '\t']) line
    , "import QxFx0.Bridge" `isPrefixOf` trimmed
        || "import qualified QxFx0.Bridge" `isPrefixOf` trimmed
    ]

testRuntimeProjectionLivesInBridge :: Test
testRuntimeProjectionLivesInBridge = TestCase $ do
  root <- getCurrentDirectory
  let bridgePath = root </> "src" </> "QxFx0" </> "Bridge" </> "SemanticNetwork" </> "RuntimeProjection.hs"
      semanticPath = root </> "src" </> "QxFx0" </> "Semantic" </> "Network" </> "RuntimeProjection.hs"
      cabalPath = root </> "qxfx0.cabal"
  bridgeExists <- doesFileExist bridgePath
  semanticExists <- doesFileExist semanticPath
  cabalContents <- readFile cabalPath
  assertBool "Bridge runtime projection module must exist" bridgeExists
  assertBool "old Semantic runtime projection module must be absent" (not semanticExists)
  assertBool "Bridge runtime projection module must be registered in Cabal"
    ("QxFx0.Bridge.SemanticNetwork.RuntimeProjection" `isInfixOf` cabalContents)
  assertBool "old Semantic runtime projection module must not be registered in Cabal"
    (not ("QxFx0.Semantic.Network.RuntimeProjection" `isInfixOf` cabalContents))

testSessionBootstrapOwnsSelfConfiguration :: Test
testSessionBootstrapOwnsSelfConfiguration = TestCase $ do
  root <- getCurrentDirectory
  let bootstrapPath = root </> "src" </> "QxFx0" </> "Runtime" </> "Session" </> "Bootstrap.hs"
      configPath = root </> "src" </> "QxFx0" </> "Runtime" </> "Session" </> "SelfConfig.hs"
      oldSelfConfigPath = root </> "src" </> "QxFx0" </> "Self" </> "ConfigLoad.hs"
      cabalPath = root </> "qxfx0.cabal"
  configExists <- doesFileExist configPath
  oldSelfConfigExists <- doesFileExist oldSelfConfigPath
  bootstrapContents <- readFile bootstrapPath
  cabalContents <- readFile cabalPath
  assertBool "runtime SelfConfig module must exist" configExists
  assertBool "old Self.ConfigLoad boundary must be absent" (not oldSelfConfigExists)
  assertBool "bootstrap must load one explicit Self configuration"
    ("selfBootstrapConfig <- loadSelfBootstrapConfig" `isInfixOf` bootstrapContents)
  assertBool "fresh bootstrap must inject the captured configuration"
    ("bootstrapSelfState selfBootstrapConfig Nothing" `isInfixOf` bootstrapContents)
  assertBool "restored bootstrap must preserve persisted Self configuration"
    ("bootstrapSelfState selfBootstrapConfig (Just (ssSelfState ss))" `isInfixOf` bootstrapContents)
  assertBool "runtime SelfConfig module must be registered in Cabal"
    ("QxFx0.Runtime.Session.SelfConfig" `isInfixOf` cabalContents)

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
  , "import System.IO.Unsafe"
  , "import qualified System.IO.Unsafe"
  ]

testSystemStateModuleIsContractOnly :: Test
testSystemStateModuleIsContractOnly = TestCase $ do
  root <- getCurrentDirectory
  let file = root </> "src" </> "QxFx0" </> "Types" </> "State" </> "System.hs"
  contents <- lines <$> readFile file
  let forbidden =
        [ "import QxFx0.Core"
        , "import qualified QxFx0.Core"
        , "import QxFx0.Bridge"
        , "import qualified QxFx0.Bridge"
        , "emptySystemState ="
        , "seedFromCorpus"
        , "seedGraph"
        , "defaultRuntimeRegime"
        , "defaultSelfState"
        , "instance ToJSON SystemState"
        , "instance FromJSON SystemState"
        ]
      violations =
        [ show lineNo <> ": " <> line
        | (lineNo, line) <- zip [1 :: Int ..] contents
        , any (`isPrefixOf` dropWhile (`elem` [' ', '\t']) line) forbidden
        ]
      implementationImportViolations =
        [ show lineNo <> ": " <> line
        | (lineNo, line) <- zip [1 :: Int ..] contents
        , let trimmed = dropWhile (`elem` [' ', '\t']) line
        , any (`isPrefixOf` trimmed) forbiddenTypesImportPrefixes
        ]
  assertEqual
    "QxFx0.Types.State.System must contain contracts only; runtime defaults belong to QxFx0.Runtime.StateDefaults"
    []
    (violations ++ implementationImportViolations)

forbiddenTypesImportPrefixes :: [String]
forbiddenTypesImportPrefixes = concatMap namespacePrefixes
  [ "QxFx0.Core"
  , "QxFx0.Bridge"
  , "QxFx0.Runtime"
  , "QxFx0.Self"
  , "QxFx0.Learning"
  , "QxFx0.Policy"
  , "QxFx0.Memory"
  , "QxFx0.Semantic"
  ]
  where
    namespacePrefixes namespace =
      [ "import " <> namespace <> " "
      , "import " <> namespace <> "."
      , "import qualified " <> namespace <> " "
      , "import qualified " <> namespace <> "."
      ]

-- | R2 forbidden list. The 'QxFx0.Core.Turn*'
-- subtrees are the canonical-orchestrator writers
-- (per ADR-0013 §3 and the role split). A supplier
-- (QxFx0.Core.StanceClassifier) must not import them.
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
