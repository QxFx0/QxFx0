{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Resource-root discovery and path resolution for repo and installed assets. -}
module QxFx0.Resources.Paths
  ( ResourcePaths(..)
   , findResourceDir
    , getNixGuardPath
    , getMigrationDir
    , getMorphologyDir
    , resolveDatalogRuleCandidates
    , resolveHttpRuntimeScriptPath
    , resolveReadinessResourcePaths
    , resolveResourcePaths
   ) where

import Control.Monad (filterM)
import Data.List (intercalate, nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe, maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import Paths_qxfx0 (getDataDir, getDataFileName)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , mkRuntimeInitError
  , throwQxFx0
  , tryIO
  , tryQxFx0
  )
import QxFx0.Internal.FilePath (isPathWithin)
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist, getCurrentDirectory)
import System.Environment (getExecutablePath, lookupEnv)
import System.FilePath ((</>), normalise, takeDirectory, takeFileName)

data ResourcePaths = ResourcePaths
  { rpResourceDir   :: FilePath
  , rpNixGuard      :: FilePath
  , rpMigrationDir  :: FilePath
  , rpMorphologyDir :: FilePath
  , rpAgdaSpec      :: FilePath
  , rpAgdaSnapshot  :: FilePath
  , rpDatalogRules  :: FilePath
  , rpSchemaSql     :: FilePath
  , rpSeedClusters  :: FilePath
  , rpSeedTemplates :: FilePath
  , rpSeedIdentity  :: FilePath
  } deriving stock (Show, Eq)

resolveResourcePaths :: IO ResourcePaths
resolveResourcePaths = do
  mResourceRootEnv <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRootEnv <- lookupEnv "QXFX0_ROOT"
  mConceptsOverride <- lookupEnv "QXFX0_CONCEPTS_PATH"
  let explicitRootConfigured = maybe False (const True) mResourceRootEnv || maybe False (const True) mRootEnv
  rootResolution <- resolveOptionalResourceRoot
  mResourceRoot <-
    case rootResolution of
      Left err -> throwResourceError (T.pack err)
      Right mRoot -> pure mRoot
  migrationSql <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["migrations/001_initial_schema.sql"]
  morphologyPrepositional <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["resources/morphology/prepositional.json"]
  _morphologyGenitive <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["resources/morphology/genitive.json"]
  _morphologyNominative <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["resources/morphology/nominative.json"]
  _morphologyQuality <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["resources/morphology/lexicon_quality.json"]
  nixGuard <- resolveConceptsPath (not explicitRootConfigured) mResourceRoot mConceptsOverride
  agdaSpec <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/R5Core.agda"]
  agdaSnapshot <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/r5-snapshot.tsv"]
  datalogPath <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/datalog/semantic_rules.dl", "semantic_rules.dl"]
  schemaSql <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/sql/schema.sql"]
  seedClusters <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/sql/seed_clusters.sql"]
  seedTemplates <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/sql/seed_templates.sql"]
  seedIdentity <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["spec/sql/seed_identity.sql"]
  let migrationDir = takeDirectory migrationSql
      morphologyDir = takeDirectory morphologyPrepositional
      resourceDir = maybe (deriveResourceRoot schemaSql migrationDir morphologyDir) id mResourceRoot
  pure ResourcePaths
    { rpResourceDir = resourceDir
    , rpNixGuard = nixGuard
    , rpMigrationDir = migrationDir
    , rpMorphologyDir = morphologyDir
    , rpAgdaSpec = agdaSpec
    , rpAgdaSnapshot = agdaSnapshot
    , rpDatalogRules = datalogPath
    , rpSchemaSql = schemaSql
    , rpSeedClusters = seedClusters
    , rpSeedTemplates = seedTemplates
    , rpSeedIdentity = seedIdentity
    }

resolveReadinessResourcePaths :: IO ResourcePaths
resolveReadinessResourcePaths = do
  mResourceRootEnv <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRootEnv <- lookupEnv "QXFX0_ROOT"
  mConceptsOverride <- lookupEnv "QXFX0_CONCEPTS_PATH"
  let mExplicitRoot =
        case fmap normalise mResourceRootEnv of
          Just root -> Just root
          Nothing -> normalise <$> mRootEnv
  mResourceRoot <-
    case mExplicitRoot of
      Just root -> do
        rootExists <- doesDirectoryExist root
        if rootExists
          then pure (Just root)
          else throwResourceError ("QXFX0 resource root is invalid: " <> T.pack root)
      Nothing -> do
        rootResolution <- resolveOptionalResourceRoot
        case rootResolution of
          Left err -> throwResourceError (T.pack err)
          Right resolved -> pure resolved
  migrationSql <- resolveReadinessFile mResourceRoot ["migrations/001_initial_schema.sql"]
  morphologyPrepositional <- resolveReadinessFile mResourceRoot ["resources/morphology/prepositional.json"]
  morphologyDir <- pure (takeDirectory morphologyPrepositional)
  schemaSql <- resolveReadinessFile mResourceRoot ["spec/sql/schema.sql"]
  nixGuard <- resolveReadinessConceptsPath mResourceRoot mConceptsOverride
  agdaSpec <- resolveReadinessFile mResourceRoot ["spec/R5Core.agda"]
  agdaSnapshot <- resolveReadinessFile mResourceRoot ["spec/r5-snapshot.tsv"]
  datalogPath <- resolveReadinessFile mResourceRoot ["spec/datalog/semantic_rules.dl", "semantic_rules.dl"]
  seedClusters <- resolveReadinessFile mResourceRoot ["spec/sql/seed_clusters.sql"]
  seedTemplates <- resolveReadinessFile mResourceRoot ["spec/sql/seed_templates.sql"]
  seedIdentity <- resolveReadinessFile mResourceRoot ["spec/sql/seed_identity.sql"]
  let migrationDir = takeDirectory migrationSql
      resourceDir = maybe (deriveResourceRoot schemaSql migrationDir morphologyDir) id mResourceRoot
  pure ResourcePaths
    { rpResourceDir = resourceDir
    , rpNixGuard = nixGuard
    , rpMigrationDir = migrationDir
    , rpMorphologyDir = morphologyDir
    , rpAgdaSpec = agdaSpec
    , rpAgdaSnapshot = agdaSnapshot
    , rpDatalogRules = datalogPath
    , rpSchemaSql = schemaSql
    , rpSeedClusters = seedClusters
    , rpSeedTemplates = seedTemplates
    , rpSeedIdentity = seedIdentity
    }

findResourceDir :: IO FilePath
findResourceDir = do
  mResourceRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRoot <- lookupEnv "QXFX0_ROOT"
  let mExplicitRoot =
        case fmap normalise mResourceRoot of
          Just root -> Just root
          Nothing -> normalise <$> mRoot
  case mExplicitRoot of
    Just root -> do
      ok <- isResourceRoot root
      if ok
        then pure root
        else throwResourceError ("QXFX0 resource root is invalid: " <> T.pack root)
    Nothing -> discoverResourceRoot

discoverInstalledDataDir :: IO (Maybe FilePath)
discoverInstalledDataDir = do
  result <- tryIO getDataDir
  pure $
    case result of
      Left _ -> Nothing
      Right path -> Just (normalise path)

discoverResourceRoot :: IO FilePath
discoverResourceRoot = do
  cwd <- getCurrentDirectory
  exePath <- getExecutablePath
  mDataDir <- discoverInstalledDataDir
  let roots = nub (maybeToList mDataDir ++ ancestors 12 cwd ++ ancestors 16 (takeDirectory exePath))
  firstOk <- pickFirstRoot roots
  case firstOk of
    Just root -> pure root
    Nothing ->
      throwResourceError
        ( "Could not locate QxFx0 resource root."
        <> " cwd=" <> T.pack cwd
        <> ", executable=" <> T.pack exePath
        <> ", searched=" <> T.pack (renderSearchRoots roots)
        )

pickFirstRoot :: [FilePath] -> IO (Maybe FilePath)
pickFirstRoot [] = pure Nothing
pickFirstRoot (root:rest) = do
  ok <- isResourceRoot root
  if ok then pure (Just root) else pickFirstRoot rest

isResourceRoot :: FilePath -> IO Bool
isResourceRoot root = do
  hasMigrations <- doesDirectoryExist (root </> "migrations")
  hasMorphology <- doesDirectoryExist (root </> "resources" </> "morphology")
  hasConcepts <- doesFileExist (root </> "semantics" </> "concepts.nix")
  hasSchema <- doesFileExist (root </> "spec" </> "sql" </> "schema.sql")
  pure (hasMigrations && hasMorphology && (hasConcepts || hasSchema))

ancestors :: Int -> FilePath -> [FilePath]
ancestors maxDepth start = go 0 (normalise start)
  where
    go n p
      | n > maxDepth = []
      | otherwise =
          let parent = takeDirectory p
          in if parent == p then [p] else p : go (n + 1) parent

getNixGuardPath :: IO FilePath
getNixGuardPath = rpNixGuard <$> resolveResourcePaths

getMigrationDir :: IO FilePath
getMigrationDir = rpMigrationDir <$> resolveResourcePaths

getMorphologyDir :: IO FilePath
getMorphologyDir = rpMorphologyDir <$> resolveResourcePaths

resolveDatalogRuleCandidates :: IO [FilePath]
resolveDatalogRuleCandidates = do
  mResourceRootEnv <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRootEnv <- lookupEnv "QXFX0_ROOT"
  let explicitRootConfigured = maybe False (const True) mResourceRootEnv || maybe False (const True) mRootEnv
      relCandidates = ["spec/datalog/semantic_rules.dl", "semantic_rules.dl"]
      mExplicitRoot =
        case fmap normalise mResourceRootEnv of
          Just root -> Just root
          Nothing -> normalise <$> mRootEnv
  mRoot <-
    case mExplicitRoot of
      Just root -> pure (Just root)
      Nothing -> do
        rootResolution <- resolveOptionalResourceRoot
        pure $ case rootResolution of
          Right resolved -> resolved
          Left _ -> Nothing
  let rootedCandidates = maybe [] (\root -> map (normalise . (root </>)) relCandidates) mRoot
  dataCandidates <-
    if explicitRootConfigured
      then pure []
      else mapMaybe id <$> mapM resolveDataFileCandidate relCandidates
  pure (nub (rootedCandidates <> dataCandidates))

resolveHttpRuntimeScriptPath :: IO FilePath
resolveHttpRuntimeScriptPath = do
  mExplicit <- lookupEnv "QXFX0_HTTP_RUNTIME"
  case mExplicit of
    Just path -> do
      let normalized = normalise path
      exists <- doesFileExist normalized
      if exists
        then validateExplicitHttpRuntimeScript normalized
        else throwResourceError ("QXFX0_HTTP_RUNTIME points to missing file: " <> T.pack normalized)
    Nothing -> do
      exePath <- getExecutablePath
      dataFileResult <- tryIO (getDataFileName "scripts/http_runtime.py")
      resourcePathsResult <- tryQxFx0 resolveResourcePaths
      let candidates =
            [ eitherToMaybe (normalise <$> dataFileResult)
            , eitherToMaybe (normalise . (</> "scripts" </> "http_runtime.py") . rpResourceDir <$> resourcePathsResult)
            , Just (normalise (takeDirectory exePath </> "scripts" </> "http_runtime.py"))
            ]
      resolveExistingHttpRuntimeScript candidates

resolveConceptsPath :: Bool -> Maybe FilePath -> Maybe FilePath -> IO FilePath
resolveConceptsPath allowDataFallback mRoot mOverride =
  case fmap normalise mOverride of
    Just overridePath -> do
      exists <- doesFileExist overridePath
      if exists
        then pure overridePath
        else throwResourceError ("QXFX0_CONCEPTS_PATH points to missing file: " <> T.pack overridePath)
    Nothing -> resolveResourceFile allowDataFallback mRoot ["semantics/concepts.nix"]

resolveReadinessConceptsPath :: Maybe FilePath -> Maybe FilePath -> IO FilePath
resolveReadinessConceptsPath mRoot mOverride =
  case fmap normalise mOverride of
    Just overridePath -> pure overridePath
    Nothing -> resolveReadinessFile mRoot ["semantics/concepts.nix"]

renderSearchRoots :: [FilePath] -> String
renderSearchRoots roots =
  let preview = take 8 roots
      suffix = if length roots > length preview then ", ..." else ""
  in "[" ++ intercalate ", " preview ++ suffix ++ "]"

resolveOptionalResourceRoot :: IO (Either String (Maybe FilePath))
resolveOptionalResourceRoot = do
  mResourceRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRoot <- lookupEnv "QXFX0_ROOT"
  let mExplicitRoot =
        case fmap normalise mResourceRoot of
          Just root -> Just root
          Nothing -> normalise <$> mRoot
  case mExplicitRoot of
    Just root -> do
      ok <- isResourceRoot root
      pure $
        if ok
          then Right (Just root)
          else Left ("QXFX0 resource root is invalid: " ++ root)
    Nothing -> do
      discovered <- tryQxFx0 discoverResourceRoot
      pure $
        case discovered of
          Right root -> Right (Just root)
          Left _ -> Right Nothing

resolveResourceFile :: Bool -> Maybe FilePath -> [FilePath] -> IO FilePath
resolveResourceFile allowDataFallback mRoot candidates = do
  let rootedCandidates = case mRoot of
        Just root -> map (normalise . (root </>)) candidates
        Nothing -> []
  rootExisting <- pickExistingPath rootedCandidates
  case rootExisting of
    Just path -> pure path
    Nothing | allowDataFallback -> do
      dataCandidates <- mapM resolveDataFileCandidate candidates
      case mapMaybe id dataCandidates of
        (path:_) -> pure path
        [] -> throwMissingResourceError candidates mRoot
    Nothing ->
      throwMissingResourceError candidates mRoot

resolveReadinessFile :: Maybe FilePath -> [FilePath] -> IO FilePath
resolveReadinessFile mRoot candidates =
  case mRoot of
    Just root ->
      case candidates of
        candidate:_ -> pure (normalise (root </> candidate))
        [] -> throwMissingResourceError [] mRoot
    Nothing -> resolveResourceFile True mRoot candidates

resolveDataFileCandidate :: FilePath -> IO (Maybe FilePath)
resolveDataFileCandidate relativePath = do
  dataResult <- tryIO (getDataFileName relativePath)
  case dataResult of
    Left _ -> pure Nothing
    Right path -> do
      exists <- doesFileExist path
      pure $ if exists then Just (normalise path) else Nothing

pickExistingPath :: [FilePath] -> IO (Maybe FilePath)
pickExistingPath [] = pure Nothing
pickExistingPath (path:rest) = do
  exists <- doesFileExist path
  if exists then pure (Just path) else pickExistingPath rest

resolveExistingHttpRuntimeScript :: [Maybe FilePath] -> IO FilePath
resolveExistingHttpRuntimeScript candidates =
  pick [path | Just path <- candidates]
  where
    pick [] =
      throwResourceError
        ( "Could not locate http_runtime.py; checked: "
        <> T.pack (intercalate ", " [path | Just path <- candidates])
        <> ". Set QXFX0_HTTP_RUNTIME to an explicit script path."
        )
    pick (path:rest) = do
      exists <- doesFileExist path
      if exists then validateAutoResolvedHttpRuntimeScript path else pick rest

validateExplicitHttpRuntimeScript :: FilePath -> IO FilePath
validateExplicitHttpRuntimeScript path = do
  exePath <- getExecutablePath
  canonicalPath <- canonicalizePath path
  let scriptName = takeFileName canonicalPath
  if scriptName /= "http_runtime.py"
    then throwResourceError ("QXFX0_HTTP_RUNTIME must point to http_runtime.py, got: " <> T.pack canonicalPath)
    else do
      trustedRoots <- resolveTrustedHttpRuntimeScriptRoots exePath
      trustedMatches <- mapM (`isPathWithin` canonicalPath) trustedRoots
      if or trustedMatches
        then pure canonicalPath
        else throwResourceError ("QXFX0_HTTP_RUNTIME points outside trusted roots: " <> T.pack canonicalPath)

validateAutoResolvedHttpRuntimeScript :: FilePath -> IO FilePath
validateAutoResolvedHttpRuntimeScript path = do
  exePath <- getExecutablePath
  canonicalPath <- canonicalizePath path
  trustedRoots <- resolveTrustedHttpRuntimeScriptRoots exePath
  trustedMatches <- mapM (`isPathWithin` canonicalPath) trustedRoots
  if or trustedMatches
    then pure canonicalPath
    else
      throwResourceError
        ( "auto-resolved http_runtime.py outside trusted roots: " <> T.pack canonicalPath
        <> "; trusted roots: " <> T.pack (intercalate ", " trustedRoots)
        <> ". Set QXFX0_HTTP_RUNTIME to an explicit script path."
        )

resolveTrustedHttpRuntimeScriptRoots :: FilePath -> IO [FilePath]
resolveTrustedHttpRuntimeScriptRoots exePath = do
  dataScriptResult <- tryIO (getDataFileName "scripts/http_runtime.py")
  mResourceRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
  let roots =
        [ takeDirectory exePath
        , takeDirectory exePath </> "scripts"
        ]
        ++ maybe [] (\root -> [normalise root, normalise root </> "scripts"]) mResourceRoot
        ++ either (const []) (\path -> [takeDirectory path]) dataScriptResult
  existing <- filterM doesDirectoryExist roots
  canonical <- mapM canonicalizePath existing
  pure (nub canonical)

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Left _) = Nothing
eitherToMaybe (Right value) = Just value

throwMissingResourceError :: [FilePath] -> Maybe FilePath -> IO a
throwMissingResourceError candidates mRoot =
  throwResourceError
    ( "resolveResourceFile: no existing candidate found"
    <> maybe "" (\root -> " for resource root=" <> T.pack root) mRoot
    <> " candidates=" <> T.pack (show candidates)
    )

deriveResourceRoot :: FilePath -> FilePath -> FilePath -> FilePath
deriveResourceRoot schemaSql migrationDir morphologyDir =
  let fromSchema = takeDirectory (takeDirectory (takeDirectory schemaSql))
      fromMigrations = takeDirectory migrationDir
      fromMorphology = takeDirectory (takeDirectory morphologyDir)
  in normalise $
      case () of
        _ | fromSchema /= "." -> fromSchema
          | fromMigrations /= "." -> fromMigrations
          | fromMorphology /= "." -> fromMorphology
          | otherwise -> "."

throwResourceError :: Text -> IO a
throwResourceError msg = throwQxFx0 $ mkRuntimeInitError "Resources" "path_resolution" "RESOURCE_ERROR" (M.singleton "message" msg)
