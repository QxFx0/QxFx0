{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Runtime backend readiness probes and cached bridge checks. -}
module QxFx0.Runtime.Wiring.Readiness
  ( BackendReadiness(..)
  , probeBackendReadiness
  , wireRuntimeReadiness
  , wireNixEval
  , wireVerifyAgda
  , readAgdaWitnessReportCached
  , checkNixWithCache
  , verifyAgdaCached
  , getNixPathCached
  ) where

import Control.Concurrent.MVar (modifyMVar_, newMVar)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Bridge.AgdaWitness (AgdaWitnessReport(..), readAgdaWitnessReport)
import QxFx0.Bridge.NixCache (NixCache, cachedNixEval)
import qualified QxFx0.Bridge.Datalog as Datalog
import qualified QxFx0.Bridge.NixGuard as NixGuard
import QxFx0.Runtime.Wiring.Context
  ( RuntimeContext(..)
  , rcTurn
  , readEmbeddingHealth
  , resolveNixPath
  , resolveSouffleExecutableCached
  , rtrAgdaWitness
  )
import QxFx0.Semantic.Embedding
  ( embeddingBackendText
  , embeddingQualityText
  , checkEmbeddingHealth
  , EmbeddingHealth(..)
  )
import QxFx0.Types.Domain (CanonicalMoveFamily(..), NixGuardStatus(..))
import QxFx0.Types.Readiness (AgdaVerificationStatus)

data BackendReadiness = BackendReadiness
  { brEmbeddingAlive       :: !Bool
  , brEmbeddingOperational :: !Bool
  , brEmbeddingExplicit    :: !Bool
  , brEmbeddingBackend     :: !Text
  , brEmbeddingQuality     :: !Text
  , brNixOperational       :: !Bool
  , brNixIssues            :: ![Text]
  , brDatalogReady         :: !Bool
  , brDatalogIssues        :: ![Text]
  , brAgdaStatus           :: !AgdaVerificationStatus
  , brAgdaWitnessPath      :: !Text
  , brAgdaIssues           :: ![Text]
  } deriving stock (Eq, Show)

wireVerifyAgda :: RuntimeContext -> IO AgdaVerificationStatus
wireVerifyAgda ctx = awrStatus <$> readAgdaWitnessReportCached ctx

readAgdaWitnessReportCached :: RuntimeContext -> IO AgdaWitnessReport
readAgdaWitnessReportCached ctx = do
  report <- readAgdaWitnessReport
  modifyMVar_ (rtrAgdaWitness (rcTurn ctx)) $ \_ -> pure (Just report)
  pure report

probeBackendReadiness :: IO BackendReadiness
probeBackendReadiness = do
  healthCache <- newMVar Nothing
  embeddingHealth <- checkEmbeddingHealth healthCache
  nixProbe <- probeNixEvaluator
  datalogProbe <- probeDatalogBackend
  agdaReport <- readAgdaWitnessReport
  pure (mkBackendReadiness embeddingHealth nixProbe datalogProbe agdaReport)

wireRuntimeReadiness :: RuntimeContext -> IO BackendReadiness
wireRuntimeReadiness ctx = do
  embeddingHealth <- readEmbeddingHealth ctx
  nixProbe <- probeNixEvaluator
  datalogProbe <- probeDatalogBackendCached ctx
  agdaReport <- readAgdaWitnessReportCached ctx
  pure (mkBackendReadiness embeddingHealth nixProbe datalogProbe agdaReport)

mkBackendReadiness
  :: EmbeddingHealth
  -> Either Text ()
  -> Either Text ()
  -> AgdaWitnessReport
  -> BackendReadiness
mkBackendReadiness embeddingHealth nixProbe datalogProbe agdaReport =
  BackendReadiness
    { brEmbeddingAlive = ehStrictReady embeddingHealth
    , brEmbeddingOperational = ehOperational embeddingHealth
    , brEmbeddingExplicit = ehExplicit embeddingHealth
    , brEmbeddingBackend = embeddingBackendText (ehBackend embeddingHealth)
    , brEmbeddingQuality = embeddingQualityText (ehQuality embeddingHealth)
    , brNixOperational = either (const False) (const True) nixProbe
    , brNixIssues = either (:[]) (const []) nixProbe
    , brDatalogReady = either (const False) (const True) datalogProbe
    , brDatalogIssues = either (:[]) (const []) datalogProbe
    , brAgdaStatus = awrStatus agdaReport
    , brAgdaWitnessPath = T.pack (awrPath agdaReport)
    , brAgdaIssues = awrIssues agdaReport
    }

wireNixEval :: NixCache -> Maybe FilePath -> Text -> Double -> Double -> IO NixGuardStatus
wireNixEval cache mNixPath concept agency tension =
  case mNixPath of
    Just nixPath -> cachedNixEval cache nixPath concept agency tension
    Nothing -> pure (Unavailable "No Nix guard path")

checkNixWithCache :: NixCache -> Maybe FilePath -> Text -> Double -> Double -> IO NixGuardStatus
checkNixWithCache = wireNixEval

verifyAgdaCached :: RuntimeContext -> IO AgdaVerificationStatus
verifyAgdaCached = wireVerifyAgda

getNixPathCached :: RuntimeContext -> IO (Maybe FilePath)
getNixPathCached = resolveNixPath

probeNixEvaluator :: IO (Either Text ())
probeNixEvaluator = do
  status <- NixGuard.getNixGuardStatus
  pure $
    case status of
      Right _ -> Right ()
      Left err -> Left err

probeDatalogBackend :: IO (Either Text ())
probeDatalogBackend = do
  execResult <- Datalog.resolveSouffleExecutable
  case execResult of
    Left err -> pure (Left err)
    Right executable -> do
      probe <- Datalog.compileAndRunDatalogWithExecutable executable "" CMGround
      pure $ case probe of
        Left err -> Left err
        Right _ -> Right ()

probeDatalogBackendCached :: RuntimeContext -> IO (Either Text ())
probeDatalogBackendCached ctx = do
  execResult <- resolveSouffleExecutableCached ctx
  case execResult of
    Left err -> pure (Left err)
    Right executable -> do
      probe <- Datalog.compileAndRunDatalogWithExecutable executable "" CMGround
      pure $ case probe of
        Left err -> Left err
        Right _ -> Right ()
