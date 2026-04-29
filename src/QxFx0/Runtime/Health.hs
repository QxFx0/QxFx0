{-# LANGUAGE DerivingStrategies, DeriveAnyClass, OverloadedStrings, BangPatterns, StrictData, DeriveGeneric #-}
module QxFx0.Runtime.Health
  ( SystemHealth(..)
  , checkHealth
  , probeRuntimeReadiness
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (find)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (takeDirectory)
import QxFx0.ExceptionPolicy (tryIO)
import QxFx0.Types.Readiness
  ( AgdaVerificationStatus
  , AgdaVerificationStatus(..)
  , agdaVerificationReady
  )

import QxFx0.Runtime.Context
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
  )
import QxFx0.Runtime.Paths (resolveDbPath)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.Morphology (MorphBackend(..), resolveMorphBackend)
import QxFx0.Bridge.SQLite.SchemaContract
  ( SchemaContractResult(..)
  , checkSchemaContract
  , renderSchemaContractResult
  )

import GHC.Generics (Generic)
import Data.Aeson (ToJSON)

data SystemHealth = SystemHealth
  { shStatus         :: !Text
  , shRuntimeMode    :: !Text
  , shReady          :: !Bool
  , shDbAlive        :: !Bool
  , shDbBootstrapable :: !Bool
  , shMorphoReady    :: !Bool
  , shNixPolicyPresent :: !Bool
  , shNixReady       :: !Bool
  , shNixIssues      :: ![Text]
  , shEmbeddingAlive :: !Bool
  , shEmbeddingOperational :: !Bool
  , shEmbeddingExplicit :: !Bool
  , shEmbeddingBackend :: !Text
  , shEmbeddingQuality :: !Text
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
   deriving anyclass (ToJSON)

checkHealth :: RuntimeContext -> IO SystemHealth
checkHealth ctx = do
  let dbPath = rcDbPath ctx
  readiness <- assessResourceReadiness dbPath
  runtimeMode <- resolveRuntimeMode
  backendResult <- tryIO (wireRuntimeReadiness ctx)
  let backend =
        either
          (const (BackendReadiness False False False "unknown" "unknown" False ["backend_probe_failed"] False ["backend_probe_failed"] AgdaInvalid "" ["backend_probe_failed"]))
          id
          backendResult
  mkSystemHealth runtimeMode dbPath readiness backend

probeRuntimeReadiness :: IO SystemHealth
probeRuntimeReadiness = do
  dbPath <- resolveDbPath
  readiness <- assessResourceReadiness dbPath
  backendResult <- tryIO probeBackendReadiness
  let backend =
        either
          (const (BackendReadiness False False False "unknown" "unknown" False ["backend_probe_failed"] False ["backend_probe_failed"] AgdaInvalid "" ["backend_probe_failed"]))
          id
          backendResult
  runtimeMode <- resolveRuntimeMode
  mkSystemHealth runtimeMode dbPath readiness backend

mkSystemHealth :: RuntimeMode -> FilePath -> ReadinessStatus -> BackendReadiness -> IO SystemHealth
mkSystemHealth runtimeMode dbPath readiness backend = do
  morphBackend <- resolveMorphBackend
  let readinessMode = computeReadinessMode readiness
      componentOk rc = maybe False (\(_, ok, _) -> ok) (find (\(c, _, _) -> c == rc) (rsComponents readiness))
      morpOk = componentOk RcMorphology
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
      readinessText = case readinessMode of
        Ready -> "ready"
        Degraded xs -> "degraded:" <> T.intercalate "," (map (T.pack . show) xs)
        NotReady xs -> "not_ready:" <> T.intercalate "," (map (T.pack . show) xs)
      strictDecisionPathOk = not strictBackendRequired || decisionPathLocalOnly
      ready = strictReadinessOk && dbReady && schemaOk && (not strictBackendRequired || backendOk) && strictDecisionPathOk
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
    , shNixPolicyPresent = nixPolicyPresent
    , shNixReady = nixOk
    , shNixIssues = nixIssues
    , shEmbeddingAlive = embedStrictReady
    , shEmbeddingOperational = brEmbeddingOperational backend
    , shEmbeddingExplicit = brEmbeddingExplicit backend
    , shEmbeddingBackend = brEmbeddingBackend backend
    , shEmbeddingQuality = brEmbeddingQuality backend
    , shMorphBackend = morphBackendText
    , shMorphBackendLocal = morphBackendLocal
    , shDecisionPathLocalOnly = decisionPathLocalOnly
    , shNetworkOptionalOnly = networkOptionalOnly
    , shLlmDecisionPath = False
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
    mStmt <- NSQL.prepare db "SELECT 1"
    case mStmt of
      Left _ -> pure False
      Right stmt -> do
        hasRow <- NSQL.stepRow stmt
        _ <- if hasRow then NSQL.columnInt stmt 0 else pure 0
        NSQL.finalize stmt
        pure hasRow
  pure (either (const False) id result)
