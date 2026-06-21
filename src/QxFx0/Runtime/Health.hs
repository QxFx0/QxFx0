{-# LANGUAGE DerivingStrategies, DeriveAnyClass, OverloadedStrings, BangPatterns, StrictData, DeriveGeneric, TypeApplications #-}
module QxFx0.Runtime.Health
  ( SystemHealth(..)
  , checkHealth
  , probeRuntimeReadiness
  ) where

import Control.Exception (try, IOException)
import Data.Text (Text)
import qualified Data.Text as T
import Data.List (find)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath ((</>), takeDirectory)
import System.IO.Error (isDoesNotExistError)
import System.IO.Unsafe (unsafePerformIO)
import qualified PGF2 as PGF
import QxFx0.ExceptionPolicy (tryIO, tryQxFx0)
import QxFx0.Types.Readiness
  ( AgdaVerificationStatus
  , AgdaVerificationStatus(..)
  , agdaVerificationReady
  )

import QxFx0.Runtime.Wiring
  ( RuntimeContext(..)
  , probeBackendReadiness
  , wireRuntimeReadiness
  )
import QxFx0.Runtime.Mode
  ( RuntimeMode
  , resolveRuntimeMode
  , runtimeModeText
  , isStrictRuntimeMode
  )
import QxFx0.Runtime.Wiring (BackendReadiness(..))
import QxFx0.Resources
  ( assessResourceReadiness
  , ReadinessStatus(..), ReadinessComponent(..), ReadinessMode(..), computeReadinessMode
  , resolveResourcePaths
  , rpResourceDir
  )
import QxFx0.Runtime.Paths (resolveDbPath)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.Morphology (MorphBackend(..), resolveMorphBackend)
import QxFx0.Bridge.SQLite.SchemaContract
  ( SchemaContractResult(..)
  , checkSchemaContract
  , renderSchemaContractResult
  )
import QxFx0.Lexicon.GfMap (GfMapLoadStatus(..), loadGfMapStatusFromPath)

import GHC.Generics (Generic)
import Data.Aeson (ToJSON, FromJSON)

data SystemHealth = SystemHealth
  { shStatus         :: !Text
  , shRuntimeMode    :: !Text
  , shReady          :: !Bool
  , shDbAlive        :: !Bool
  , shDbBootstrapable :: !Bool
  , shMorphoReady    :: !Bool
  , shGfMapOk        :: !Bool
  , shGfMapStatus    :: !Text
  , shGfMapEntries   :: !Int
  , shGfMapIssue     :: !(Maybe Text)
  , shPgfOk          :: !Bool
  , shPgfStatus      :: !Text
  , shPgfIssue       :: !(Maybe Text)
  , shNixPolicyPresent :: !Bool
  , shNixReady       :: !Bool
  , shNixIssues      :: ![Text]
  , shEmbeddingAlive :: !Bool
  , shEmbeddingOperational :: !Bool
  , shEmbeddingExplicit :: !Bool
  , shEmbeddingBackend :: !Text
  , shEmbeddingQuality :: !Text
  , shEmbeddingIssues :: ![Text]
  , shMorphBackend :: !Text
  , shMorphBackendLocal :: !Bool
  , shDecisionPathLocalOnly :: !Bool
  , shNetworkOptionalOnly :: !Bool
  , shLlmDecisionPath :: !Bool
  , shAgdaReady      :: !Bool
  , shAgdaStatus     :: !AgdaVerificationStatus
  , shAgdaWitnessPath :: !Text
  , shAgdaIssues     :: ![Text]
  , shDatalogReady   :: !Bool
  , shDatalogIssues  :: ![Text]
  , shSchemaOk       :: !Bool
  , shSchemaVersion  :: !Int
  , shSchemaReason   :: !Text
  , shReadinessMode  :: !Text
  } deriving stock (Show, Eq, Generic)
   deriving anyclass (ToJSON, FromJSON)

data GfMapHealth = GfMapHealth
  { ghOk      :: !Bool
  , ghStatus  :: !Text
  , ghEntries :: !Int
  , ghIssue   :: !(Maybe Text)
  }

data PgfHealth = PgfHealth
  { phOk     :: !Bool
  , phStatus :: !Text
  , phIssue  :: !(Maybe Text)
  }

checkHealth :: RuntimeContext -> IO SystemHealth
checkHealth ctx = do
  let dbPath = rcDbPath ctx
  readiness <- assessResourceReadiness dbPath
  runtimeMode <- resolveRuntimeMode
  backendResult <- tryIO (wireRuntimeReadiness ctx)
  let backend = either (const backendProbeFailedReadiness) id backendResult
  mkSystemHealth runtimeMode dbPath readiness backend

probeRuntimeReadiness :: IO SystemHealth
probeRuntimeReadiness = do
  dbPath <- resolveDbPath
  readiness <- assessResourceReadiness dbPath
  backendResult <- tryIO probeBackendReadiness
  let backend = either (const backendProbeFailedReadiness) id backendResult
  runtimeMode <- resolveRuntimeMode
  mkSystemHealth runtimeMode dbPath readiness backend

backendProbeFailedReadiness :: BackendReadiness
backendProbeFailedReadiness = BackendReadiness
  { brEmbeddingAlive = False
  , brEmbeddingOperational = False
  , brEmbeddingExplicit = False
  , brEmbeddingBackend = "unknown"
  , brEmbeddingQuality = "unknown"
  , brEmbeddingIssues = ["backend_probe_failed"]
  , brNixOperational = False
  , brNixIssues = ["backend_probe_failed"]
  , brDatalogReady = False
  , brDatalogIssues = ["backend_probe_failed"]
  , brAgdaStatus = AgdaInvalid
  , brAgdaWitnessPath = ""
  , brAgdaIssues = ["backend_probe_failed"]
  }

mkSystemHealth :: RuntimeMode -> FilePath -> ReadinessStatus -> BackendReadiness -> IO SystemHealth
mkSystemHealth runtimeMode dbPath readiness backend = do
  morphBackend <- resolveMorphBackend
  gfHealth <- loadRuntimeGfMapHealth
  pgfHealth <- probePgfHealth
  let readinessMode = computeReadinessMode readiness
      componentOk rc = maybe False (\(_, ok, _) -> ok) (find (\(c, _, _) -> c == rc) (rsComponents readiness))
      morpOk = componentOk RcMorphology
      gfOk = ghOk gfHealth
      pgfOk = phOk pgfHealth
      nixPolicyPresent = componentOk RcNixPolicy
      nixOk = nixPolicyPresent && brNixOperational backend
      datalogOk = componentOk RcDatalogRules && brDatalogReady backend
      agdaSpecOk = componentOk RcAgdaSpec
      agdaStatus = brAgdaStatus backend
  dbHealth <- inspectDatabaseHealth dbPath
  contractResult <- inspectSchemaContract dbPath
  let dbReady = dhReady dbHealth && componentOk RcDatabase
      schemaOk = isSchemaContractOk contractResult
      schemaVersion = schemaContractVersion contractResult
      schemaReason = renderSchemaContractResult contractResult
      agdaOk = agdaSpecOk && agdaVerificationReady agdaStatus
      strictBackendRequired = isStrictRuntimeMode runtimeMode
      strictReadinessOk = case readinessMode of
        NotReady _ -> False
        Degraded _ -> not strictBackendRequired
        Ready -> True
      embedStrictReady = brEmbeddingAlive backend
      backendOk = embedStrictReady && agdaOk && datalogOk && nixOk
      morphBackendLocal = morphBackend == MorphBackendLocal
      morphBackendText =
        case morphBackend of
          MorphBackendLocal -> "local"
          MorphBackendRemote -> "remote"
      decisionPathLocalOnly = brEmbeddingBackend backend == "local_deterministic" && morphBackendLocal
      networkOptionalOnly = decisionPathLocalOnly
      nixIssues =
        (if nixPolicyPresent then [] else ["nix_policy_missing"])
          ++ brNixIssues backend
      gfReadinessNote = if gfOk then Nothing else Just ("gfmap:" <> maybe "failed" id (ghIssue gfHealth))
      pgfReadinessNote = if pgfOk then Nothing else Just ("pgf:" <> maybe "failed" id (phIssue pgfHealth))
      allReadinessNotes = catMaybes [gfReadinessNote, pgfReadinessNote]
        where catMaybes = foldr (\mx acc -> maybe acc (:acc) mx) []
      readinessText = case readinessMode of
        Ready -> if null allReadinessNotes then "ready" else "not_ready:" <> T.intercalate "," allReadinessNotes
        Degraded xs ->
          if null allReadinessNotes
            then "degraded:" <> T.intercalate "," (map (T.pack . show) xs)
            else "not_ready:" <> T.intercalate "," (map (T.pack . show) xs ++ allReadinessNotes)
        NotReady xs -> "not_ready:" <> T.intercalate "," (map (T.pack . show) xs ++ allReadinessNotes)
      strictDecisionPathOk = not strictBackendRequired || decisionPathLocalOnly
      ready = strictReadinessOk && dbReady && schemaOk && gfOk && pgfOk && (not strictBackendRequired || backendOk) && strictDecisionPathOk
      degraded = ready && (readinessMode /= Ready || not embedStrictReady || not agdaOk || not datalogOk || not nixOk)
      status
        | not ready = "not_ready"
        | degraded = "degraded"
        | otherwise = "ok"
  pure SystemHealth
    { shStatus = status
    , shRuntimeMode = runtimeModeText runtimeMode
    , shReady = ready
    , shDbAlive = dhAlive dbHealth
    , shDbBootstrapable = dhBootstrapable dbHealth
    , shMorphoReady = morpOk
    , shGfMapOk = ghOk gfHealth
    , shGfMapStatus = ghStatus gfHealth
    , shGfMapEntries = ghEntries gfHealth
    , shGfMapIssue = ghIssue gfHealth
    , shPgfOk = pgfOk
    , shPgfStatus = phStatus pgfHealth
    , shPgfIssue = phIssue pgfHealth
    , shNixPolicyPresent = nixPolicyPresent
    , shNixReady = nixOk
    , shNixIssues = nixIssues
    , shEmbeddingAlive = embedStrictReady
    , shEmbeddingOperational = brEmbeddingOperational backend
    , shEmbeddingExplicit = brEmbeddingExplicit backend
    , shEmbeddingBackend = brEmbeddingBackend backend
    , shEmbeddingQuality = brEmbeddingQuality backend
    , shEmbeddingIssues = brEmbeddingIssues backend
    , shMorphBackend = morphBackendText
    , shMorphBackendLocal = morphBackendLocal
    , shDecisionPathLocalOnly = decisionPathLocalOnly
    , shNetworkOptionalOnly = networkOptionalOnly
    , shLlmDecisionPath = not decisionPathLocalOnly
    , shAgdaReady = agdaOk
    , shAgdaStatus = agdaStatus
    , shAgdaWitnessPath = brAgdaWitnessPath backend
    , shAgdaIssues = brAgdaIssues backend
    , shDatalogReady = datalogOk
    , shDatalogIssues = brDatalogIssues backend
    , shSchemaOk = schemaOk
    , shSchemaVersion = schemaVersion
    , shSchemaReason = schemaReason
    , shReadinessMode = readinessText
    }

loadRuntimeGfMapHealth :: IO GfMapHealth
loadRuntimeGfMapHealth = do
  pathsResult <- tryQxFx0 resolveResourcePaths
  case pathsResult of
    Left _ -> pure (GfMapHealth False "failed" 0 (Just "resource_root_unavailable"))
    Right paths -> do
      status <- loadGfMapStatusFromPath (rpResourceDir paths </> "spec" </> "gf" </> "lexicon_funmap.tsv")
      pure (gfMapHealthFromStatus status)

gfMapHealthFromStatus :: GfMapLoadStatus -> GfMapHealth
gfMapHealthFromStatus status =
  case status of
    GfMapLoaded n -> GfMapHealth
      { ghOk = n > 0
      , ghStatus = "loaded"
      , ghEntries = n
      , ghIssue = if n > 0 then Nothing else Just "resource_empty_or_unparseable"
      }
    GfMapLoadFailed reason -> GfMapHealth
      { ghOk = False
      , ghStatus = "failed"
      , ghEntries = 0
      , ghIssue = Just reason
      }

-- | WP-H2: Boot-time PGF health probe. Attempts to load the PGF grammar
-- to verify it's valid and accessible. This enables GF default-on when
-- the probe succeeds.
probePgfHealth :: IO PgfHealth
probePgfHealth = do
  let pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  if not exists
    then pure $ PgfHealth
      { phOk = False
      , phStatus = "missing"
      , phIssue = Just ("pgf_file_not_found:" <> T.pack pgfPath)
      }
    else do
      result <- try @IOException $ do
        pgf <- PGF.readPGF pgfPath
        let langCount = length (PGF.languages pgf)
        pure langCount
      case result of
        Left e ->
          if isDoesNotExistError e
            then pure $ PgfHealth
              { phOk = False
              , phStatus = "missing"
              , phIssue = Just ("pgf_file_not_found:" <> T.pack pgfPath)
              }
            else pure $ PgfHealth
              { phOk = False
              , phStatus = "load_failed"
              , phIssue = Just ("pgf_io_error:" <> T.pack (show e))
              }
        Right langCount ->
          if langCount > 0
            then pure $ PgfHealth
              { phOk = True
              , phStatus = "loaded"
              , phIssue = Nothing
              }
            else pure $ PgfHealth
              { phOk = False
              , phStatus = "invalid"
              , phIssue = Just "pgf_no_languages"
              }

isSchemaContractOk :: SchemaContractResult -> Bool
isSchemaContractOk (SchemaContractOk _) = True
isSchemaContractOk SchemaContractFreshBootstrapable = True
isSchemaContractOk _ = False

schemaContractVersion :: SchemaContractResult -> Int
schemaContractVersion (SchemaContractOk v) = v
schemaContractVersion SchemaContractFreshBootstrapable = 0
schemaContractVersion (SchemaContractVersionBehind _ actual) = actual
schemaContractVersion _ = 0

inspectSchemaContract :: FilePath -> IO SchemaContractResult
inspectSchemaContract dbPath = do
  dbExists <- doesFileExist dbPath
  if not dbExists
    then pure SchemaContractFreshBootstrapable
    else do
      result <- NSQL.withDatabase dbPath $ \db -> checkSchemaContract db
      pure (either (\err -> SchemaContractQueryFailed (T.pack (show err))) id result)

data DatabaseHealth = DatabaseHealth
  { dhAlive         :: !Bool
  , dhBootstrapable :: !Bool
  , dhReady         :: !Bool
  }

inspectDatabaseHealth :: FilePath -> IO DatabaseHealth
inspectDatabaseHealth dbPath = do
  dbExists <- doesFileExist dbPath
  dbDirOk <- doesDirectoryExist (takeDirectory dbPath)
  dbAlive <-
    if dbExists
      then checkExistingDatabase dbPath
      else pure False
  pure DatabaseHealth
    { dhAlive = dbAlive
    , dhBootstrapable = dbDirOk
    , dhReady = if dbExists then dbAlive else dbDirOk
    }

checkExistingDatabase :: FilePath -> IO Bool
checkExistingDatabase dbPath = do
  result <- NSQL.withDatabase dbPath $ \db -> do
    NSQL.withStatement db "SELECT 1" $ \stmt -> do
      mStepResult <- NSQL.step stmt
      case mStepResult of
        Right rc | rc == 100 -> do
          _ <- NSQL.columnInt stmt 0
          pure True
        _ -> pure False
  case result of
    Left _   -> pure False
    Right (Left _) -> pure False
    Right (Right alive) -> pure alive


