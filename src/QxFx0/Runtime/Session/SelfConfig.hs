{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-| Explicit session-bootstrap loading for pure Self-layer tunables. -}
module QxFx0.Runtime.Session.SelfConfig
  ( SelfBootstrapConfig(..)
  , defaultSelfBootstrapConfig
  , resolveSelfConfigPath
  , loadConfigOrBuiltinIO
  , loadTunedOrDefaultIO
  , loadSelfBootstrapConfig
  , applySelfBootstrapConfig
  , bootstrapSelfState
  ) where

import Data.Aeson (FromJSON, eitherDecodeStrict)
import qualified Data.ByteString as BS
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)
import Paths_qxfx0 (getDataFileName)

import QxFx0.Self.Conatus (ConatusWeights, defaultConatusWeights)
import QxFx0.Self.FamilyTargets (FamilyTarget, familyTargets)
import QxFx0.Self.Field (FieldHeuristics, defaultFieldHeuristics)
import QxFx0.Self.Salience (SalienceWeights, defaultSalienceWeights)
import QxFx0.Runtime.StateDefaults (emptySelfState)
import QxFx0.Types.State.SelfState (SelfState(..))

-- | All file-tuned Self parameters captured once at session bootstrap.
data SelfBootstrapConfig = SelfBootstrapConfig
  { sbcSalienceWeights :: !SalienceWeights
  , sbcFieldHeuristics :: !FieldHeuristics
  , sbcConatusWeights  :: !ConatusWeights
  , sbcFamilyTargets   :: ![FamilyTarget]
  } deriving stock (Eq, Show)

-- | Pure fallback used when no configuration files are available.
defaultSelfBootstrapConfig :: SelfBootstrapConfig
defaultSelfBootstrapConfig = SelfBootstrapConfig
  { sbcSalienceWeights = defaultSalienceWeights
  , sbcFieldHeuristics = defaultFieldHeuristics
  , sbcConatusWeights = defaultConatusWeights
  , sbcFamilyTargets = familyTargets
  }

-- | Prefer a directly accessible path, then Cabal's installed data directory.
-- Returning the original path when neither exists keeps fallback diagnostics
-- meaningful and lets the caller apply its pure builtin.
resolveSelfConfigPath :: FilePath -> IO FilePath
resolveSelfConfigPath path = do
  localExists <- doesFileExist path
  if localExists
    then pure path
    else do
      installedPath <- getDataFileName path
      installedExists <- doesFileExist installedPath
      pure (if installedExists then installedPath else path)

-- | Load one JSON value, falling back to the supplied pure builtin.
loadConfigOrBuiltinIO :: FromJSON a => FilePath -> a -> IO a
loadConfigOrBuiltinIO requestedPath builtin = do
  path <- resolveSelfConfigPath requestedPath
  exists <- doesFileExist path
  if not exists
    then pure builtin
    else decodeOrFallback path builtin

-- | Prefer a tuned JSON value, then a base file, then the pure builtin.
loadTunedOrDefaultIO :: FromJSON a => FilePath -> FilePath -> a -> IO a
loadTunedOrDefaultIO requestedTunedPath basePath builtin = do
  tunedPath <- resolveSelfConfigPath requestedTunedPath
  tunedExists <- doesFileExist tunedPath
  if not tunedExists
    then loadConfigOrBuiltinIO basePath builtin
    else do
      bytes <- BS.readFile tunedPath
      case eitherDecodeStrict bytes of
        Right config -> pure config
        Left err -> do
          hPutStrLn stderr
            ("[config] " <> tunedPath <> " parse error: " <> err
              <> "; falling back to " <> basePath)
          loadConfigOrBuiltinIO basePath builtin

-- | Read all Self tunables exactly once for a new runtime session.
loadSelfBootstrapConfig :: IO SelfBootstrapConfig
loadSelfBootstrapConfig = do
  salience <- loadTunedOrDefaultIO
    "resources/config/tuned_salience_weights.json"
    "resources/config/salience_weights.json"
    defaultSalienceWeights
  field <- loadTunedOrDefaultIO
    "resources/config/tuned_field_heuristics.json"
    "resources/config/field_heuristics.json"
    defaultFieldHeuristics
  conatus <- loadConfigOrBuiltinIO
    "resources/config/conatus_weights.json"
    defaultConatusWeights
  targets <- loadConfigOrBuiltinIO
    "resources/config/family_targets.json"
    familyTargets
  pure SelfBootstrapConfig
    { sbcSalienceWeights = salience
    , sbcFieldHeuristics = field
    , sbcConatusWeights = conatus
    , sbcFamilyTargets = targets
    }

-- | Inject one captured bootstrap configuration into persistent session state.
applySelfBootstrapConfig :: SelfBootstrapConfig -> SelfState -> SelfState
applySelfBootstrapConfig config selfState = selfState
  { selfSalienceWeights = sbcSalienceWeights config
  , selfFieldHeuristics = sbcFieldHeuristics config
  , selfConatusWeights = sbcConatusWeights config
  , selfFamilyTargets = sbcFamilyTargets config
  }

-- | Install ambient bootstrap configuration only for a fresh session.
-- Restored sessions retain their persisted governing values for deterministic
-- continuation, including values adapted by earlier turns.
bootstrapSelfState :: SelfBootstrapConfig -> Maybe SelfState -> SelfState
bootstrapSelfState config Nothing = applySelfBootstrapConfig config emptySelfState
bootstrapSelfState _ (Just persisted) = persisted

decodeOrFallback :: FromJSON a => FilePath -> a -> IO a
decodeOrFallback path builtin = do
  bytes <- BS.readFile path
  case eitherDecodeStrict bytes of
    Right config -> pure config
    Left err -> do
      hPutStrLn stderr ("[config] " <> path <> " parse error: " <> err)
      pure builtin
