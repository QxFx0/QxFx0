{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Runtime.Wiring.Handlers
  ( handleTurnEffect
  ) where

import qualified Data.Text as T
import Data.Char (isAlphaNum)
import qualified Data.Set as Set
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesDirectoryExist
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>), isAbsolute, normalise, takeDirectory, takeFileName)
import System.IO (hClose, hPutStr)
import System.Posix.Files (ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.IO (OpenFileFlags(creat, exclusive, nofollow), OpenMode(WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Posix.Types (FileMode)

import QxFx0.Bridge.SQLite (maybeCheckpoint)
import QxFx0.Bridge.StatePersistence (rollbackTurnProjections, saveStateWithProjectionExpected)
import qualified QxFx0.Bridge.Datalog as Datalog
import QxFx0.ExceptionPolicy (catchIO)
import QxFx0.Core.ConsciousnessLoop (clLastNarrative, runConsciousnessLoopWithSalience)
import QxFx0.Core.Intuition (checkIntuitionWithInputAndSalience, effectivePosterior)
import QxFx0.Self.Field (emptyField, fieldResonance, mkResonance)
import QxFx0.Self.Salience (computeSalience)
import QxFx0.Core.TurnPipeline.Effects (TurnEffectRequest(..), TurnEffectResult(..))
import QxFx0.Internal.FilePath (isPathWithin)
import QxFx0.Runtime.PGF (linearizeClaimAstGfLang, linearizeDialogAtomsGfLang)
import QxFx0.Runtime.Wiring.Context
  ( RuntimeContext(..)
  , RuntimeWorkers(..)
  , TimeSource
  , commitRuntimeTurnState
  , rcCaches
  , rcTimeSource
  , readConsciousLoop
  , readApiHealth
  , readIntuition
  , resolveNixPath
  , resolveSouffleExecutableCached
  , rtcNix
  , withRuntimeDb
  )
import QxFx0.Runtime.Wiring.Readiness (checkNixWithCache, wireVerifyAgda)
import QxFx0.Semantic.Embedding (textToEmbeddingResultWithManager)
import QxFx0.Bridge.ExternalLLM (buildTransportFromEnvWithManager, queryExternalTool)
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.Domain (r5Family, r5Force)
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergenceKind(..)
  , ShadowSnapshotId(..)
  , sdKind
  , emptyShadowDivergence
  )

handleTurnEffect :: RuntimeContext -> TurnEffectRequest -> IO TurnEffectResult
handleTurnEffect ctx request =
  case request of
    TurnReqEmbedding inputText ->
      TurnResEmbedding <$> textToEmbeddingResultWithManager (rtwHttpManager (rcWorkers ctx)) inputText
    TurnReqNixGuard concept agency tension -> do
      nixPath <- resolveNixPath ctx
      status <- checkNixWithCache (rtcNix (rcCaches ctx)) nixPath concept agency tension
      pure (TurnResNixGuard status)
    TurnReqConsciousness semanticInput humanTheta resonance conatusEnergy salienceWeights -> do
      cl <- readConsciousLoop ctx
      let contentSaliency = 0.0  -- WP-C: default for runtime handler
          salience = computeSalience salienceWeights conatusEnergy (emptyField { fieldResonance = mkResonance resonance }) contentSaliency
          (nextLoop, fragment) =
            runConsciousnessLoopWithSalience salience cl semanticInput humanTheta resonance
          currentNarrative = clLastNarrative nextLoop
          narrativeFragment = if T.null fragment then Nothing else Just fragment
      pure (TurnResConsciousness nextLoop currentNarrative narrativeFragment)
    TurnReqIntuition inputText resonance tension turnNumber conatusEnergy salienceWeights semanticConfig -> do
      intuitive <- readIntuition ctx
      let contentSaliency = 0.0  -- WP-C: default for runtime handler
          salience = computeSalience salienceWeights conatusEnergy (emptyField { fieldResonance = mkResonance resonance }) contentSaliency
          (mFlash, intuitionState) =
            checkIntuitionWithInputAndSalience
              salience semanticConfig inputText resonance tension turnNumber intuitive
      pure (TurnResIntuition mFlash (effectivePosterior intuitionState) intuitionState)
    TurnReqCommitRuntimeState previewLoop previewIntuition observation -> do
      commitRuntimeTurnState ctx previewLoop previewIntuition observation
      pure TurnResCommitRuntimeState
    TurnReqApiHealth ->
      TurnResApiHealth <$> readApiHealth ctx
    TurnReqReadEnv key ->
      if isAllowedReadEnvKey key
        then TurnResReadEnv . fmap T.pack <$> lookupEnv (T.unpack key)
        else pure (TurnResReadEnv Nothing)
    TurnReqTestMarkOnceFile pathText -> do
      mPath <- resolveTrustedMarkerPath (T.unpack (T.strip pathText))
      case mPath of
        Nothing ->
          pure (TurnResTestMarkOnceFile False)
        Just path -> do
          TurnResTestMarkOnceFile <$> markMarkerOnce path
    TurnReqShadow family force tags -> do
      execResult <- resolveSouffleExecutableCached ctx
      sr <- case execResult of
        Right executable -> Datalog.runDatalogShadowWithExecutable executable family force tags
        Left err ->
          pure Datalog.ShadowResult
            { Datalog.srStatus = ShadowUnavailable
            , Datalog.srDivergence = emptyShadowDivergence { sdKind = ShadowUnavailableDivergence }
            , Datalog.srDatalogVerdict = Nothing
            , Datalog.srSnapshotId = ShadowSnapshotId "shadow:runtime_souffle_unavailable"
            , Datalog.srDiagnostics = [err]
            }
      pure
        (TurnResShadow
          ((\v -> (r5Family v, r5Force v)) <$> Datalog.srDatalogVerdict sr)
          (Datalog.srStatus sr)
          (Datalog.srDivergence sr)
          (Datalog.srSnapshotId sr)
          (Datalog.srDiagnostics sr))
    TurnReqAgdaVerify ->
      TurnResAgdaVerify <$> wireVerifyAgda ctx
    TurnReqCurrentTime ->
      TurnResCurrentTime <$> rcTimeSource ctx
    TurnReqRequestId ->
      TurnResRequestId <$> generateRequestId (rcTimeSource ctx)
    TurnReqSemanticIntrospectionEnv -> do
      envResult <- handleTurnEffect ctx (TurnReqReadEnv "QXFX0_SEMANTIC_INTROSPECTION")
      case envResult of
        TurnResReadEnv value -> pure (TurnResSemanticIntrospectionEnv (maybe False (const True) value))
        _ -> pure (TurnResSemanticIntrospectionEnv False)
    TurnReqSaveState ss sid expectedRevision mProj ->
      TurnResSaveState <$> saveStateWithProjectionExpected (withRuntimeDb ctx) ss sid expectedRevision mProj
    TurnReqRollbackTurnProjections sid stableTurn ->
      TurnResRollbackTurnProjections <$> rollbackTurnProjections (withRuntimeDb ctx) sid stableTurn
    TurnReqCheckpoint turnCount -> do
      withRuntimeDb ctx $ \db -> maybeCheckpoint db turnCount
      pure TurnResCheckpointCompleted
    TurnReqLinearizeClaimAst mPgfPath lang claimAst ->
      TurnResLinearizeClaimAst <$> linearizeClaimAstGfLang mPgfPath lang claimAst
    TurnReqLinearizeDialogAtoms mPgfPath lang da ->
      TurnResLinearizeDialogAtoms <$> linearizeDialogAtomsGfLang mPgfPath lang da
    TurnReqExternalQuery tool need query -> do
      transport <- buildTransportFromEnvWithManager (rtwHttpManager (rcWorkers ctx))
      result <- queryExternalTool transport tool need query
      pure (TurnResExternalQuery result)

generateRequestId :: TimeSource -> IO T.Text
generateRequestId timeSource = do
  requestUuid <- UUIDv4.nextRandom
  now <- timeSource
  let ts = formatTime defaultTimeLocale "%Y%m%d%H%M%S" now
  pure (T.pack ts <> "-" <> UUID.toText requestUuid)

resolveTrustedMarkerPath :: FilePath -> IO (Maybe FilePath)
resolveTrustedMarkerPath rawPath = do
  let normalized = normalise (dropWhile (== ' ') rawPath)
  stateDir <- resolveStateDir
  createDirectoryIfMissing True stateDir
  canonicalStateDir <- canonicalizePath stateDir
  canonicalTmp <- canonicalizePath "/tmp"
  if null normalized
    then pure Nothing
    else
      if isAbsolute normalized
        then resolveAbsoluteMarkerPath canonicalTmp canonicalStateDir normalized
        else
          pure $
            if isSafeRelativeMarker normalized
              then Just (canonicalStateDir </> "test-hooks" </> takeFileName normalized)
              else Nothing

resolveStateDir :: IO FilePath
resolveStateDir = do
  mStateDir <- lookupEnv "QXFX0_STATE_DIR"
  pure $ case fmap normalise mStateDir of
    Just path | not (null path) -> path
    _ -> "/tmp/qxfx0"

resolveAbsoluteMarkerPath :: FilePath -> FilePath -> FilePath -> IO (Maybe FilePath)
resolveAbsoluteMarkerPath canonicalTmp canonicalStateDir absoluteCandidate = do
  let parentDir = takeDirectory absoluteCandidate
      markerName = takeFileName absoluteCandidate
  parentExists <- doesDirectoryExist parentDir
  if not parentExists || not (isSafeRelativeMarker markerName)
    then pure Nothing
    else do
      canonicalParent <- canonicalizePath parentDir
      let canonicalCandidate = canonicalParent </> markerName
      withinTmp <- isPathWithin canonicalTmp canonicalCandidate
      withinState <- isPathWithin canonicalStateDir canonicalCandidate
      pure $
        if withinTmp || withinState
          then Just canonicalCandidate
          else Nothing

isSafeRelativeMarker :: FilePath -> Bool
isSafeRelativeMarker relPath =
  relPath == takeFileName relPath
    && not (null relPath)
    && all isMarkerChar relPath

isMarkerChar :: Char -> Bool
isMarkerChar c = isAlphaNum c || c `elem` ("._-" :: String)

markMarkerOnce :: FilePath -> IO Bool
markMarkerOnce path = do
  createDirectoryIfMissing True (takeDirectory path)
  catchIO
    (do fd <- openFd path WriteOnly defaultFileFlags
          { exclusive = True
          , nofollow = True
          , creat = Just markerFileMode
          }
        handle <- fdToHandle fd
        hPutStr handle "triggered\n"
        hClose handle
        pure True)
    (\_ -> pure False)

markerFileMode :: FileMode
markerFileMode = ownerReadMode `unionFileModes` ownerWriteMode

isAllowedReadEnvKey :: T.Text -> Bool
isAllowedReadEnvKey key = key `Set.member` allowedReadEnvKeys

allowedReadEnvKeys :: Set.Set T.Text
allowedReadEnvKeys =
  Set.fromList
    [ "QXFX0_SEMANTIC_INTROSPECTION"
    , "QXFX0_WARN_MORPHOLOGY_FALLBACK"
    , "QXFX0_TEST_MODE"
    , "QXFX0_TEST_POST_COMMIT_TAIL_EXCEPTION_ONCE_FILE"
    , "QXFX0_GF_RUNTIME"
    , "QXFX0_GF_LANG"
    , "QXFX0_GF_PGF_PATH"
    , "QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST"
    ]
