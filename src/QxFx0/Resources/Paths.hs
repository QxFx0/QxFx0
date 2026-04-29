{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Resource-root discovery and path resolution for repo and installed assets. -}
module QxFx0.Resources.Paths
  ( ResourcePaths(..)
  , findResourceDir
  , getNixGuardPath
  , getMigrationDir
  , getMorphologyDir
  , resolveResourcePaths
  ) where

import Data.List (intercalate, nub)
import Data.Maybe (mapMaybe, maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import Paths_qxfx0 (getDataDir, getDataFileName)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , throwQxFx0
  , tryIO
  , tryQxFx0
  )
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory)
import System.Environment (getExecutablePath, lookupEnv)
import System.FilePath ((</>), normalise, takeDirectory)

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
  nixGuard <- resolveResourceFile (not explicitRootConfigured) mResourceRoot ["semantics/concepts.nix"]
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
        [] ->
          case rootedCandidates of
            (path:_) -> pure path
            [] ->
              case candidates of
                (path:_) -> pure (normalise path)
                [] -> throwResourceError "resolveResourceFile: empty candidate list"
    Nothing ->
      case rootedCandidates of
        (path:_) -> pure path
        [] ->
          case candidates of
            (path:_) -> pure (normalise path)
            [] -> throwResourceError "resolveResourceFile: empty candidate list"

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
throwResourceError = throwQxFx0 . RuntimeInitError
