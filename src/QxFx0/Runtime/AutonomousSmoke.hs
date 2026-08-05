{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.AutonomousSmoke
  ( autonomousSmokeDbEnv
  , resolveAutonomousSmokeDbPath
  , validateAutonomousSmokeDbPath
  , newSemanticEdges
  ) where

import Control.Exception (IOException, try)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (canonicalizePath, doesPathExist)
import System.Environment (lookupEnv)
import System.FilePath
  ( isAbsolute
  , makeRelative
  , normalise
  , splitDirectories
  )
import System.Posix.Files (ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.IO
  ( OpenFileFlags(creat, exclusive, nofollow)
  , OpenMode(WriteOnly)
  , closeFd
  , defaultFileFlags
  , openFd
  )

import QxFx0.Runtime.Paths (resolveDbPath)
import QxFx0.Semantic.Network.Types
  ( SemanticEdge
  , SemanticNetwork(..)
  )

autonomousSmokeDbEnv :: String
autonomousSmokeDbEnv = "QXFX0_AUTONOMOUS_SMOKE_DB"

-- | Resolve the smoke-only database independently of the normal runtime DB.
-- Canonicalization prevents a path below /tmp from escaping through a symlink.
resolveAutonomousSmokeDbPath :: IO (Either Text FilePath)
resolveAutonomousSmokeDbPath = do
  mCandidate <- lookupEnv autonomousSmokeDbEnv
  case fmap (T.unpack . T.strip . T.pack) mCandidate of
    Nothing -> pure (Left missingPathError)
    Just "" -> pure (Left missingPathError)
    Just candidate -> do
      occupied <- or <$> mapM doesPathExist [candidate, candidate <> "-wal", candidate <> "-shm"]
      if occupied
        then pure (Left "autonomous smoke database path must be fresh and must not already exist")
        else do
          normalDb <- resolveDbPath
          canonicalCandidate <- canonicalize candidate
          canonicalNormal <- canonicalize normalDb
          let validated = do
                candidate' <- canonicalCandidate
                normalDb' <- canonicalNormal
                validateAutonomousSmokeDbPath normalDb' candidate'
          case validated of
            Left err -> pure (Left err)
            Right path -> reserveFresh path
  where
    missingPathError =
      "--autonomous-smoke requires QXFX0_AUTONOMOUS_SMOKE_DB to name a disposable database under /tmp"

    canonicalize path = do
      result <- try (canonicalizePath path) :: IO (Either IOException FilePath)
      pure $ case result of
        Left err -> Left
          ("cannot canonicalize autonomous smoke database path "
            <> T.pack path <> ": " <> T.pack (show err))
        Right resolved -> Right resolved

    reserveFresh path = do
      let mode = ownerReadMode `unionFileModes` ownerWriteMode
          flags = defaultFileFlags { creat = Just mode, exclusive = True, nofollow = True }
      result <- try (openFd path WriteOnly flags >>= closeFd)
        :: IO (Either IOException ())
      pure $ case result of
        Left err -> Left ("cannot exclusively reserve autonomous smoke database: " <> T.pack (show err))
        Right () -> Right path

-- | Enforce the smoke database boundary after paths have been canonicalized.
validateAutonomousSmokeDbPath :: FilePath -> FilePath -> Either Text FilePath
validateAutonomousSmokeDbPath normalDb candidate
  | not (isAbsolute candidate') =
      Left "autonomous smoke database path must be absolute and under /tmp"
  | candidate' == tmpRoot =
      Left "autonomous smoke database path must name a file below /tmp"
  | escapesTmp =
      Left "autonomous smoke database path must be under /tmp"
  | candidate' == normalDb' =
      Left "autonomous smoke database must differ from the normal resolved database"
  | otherwise = Right candidate'
  where
    candidate' = normalise candidate
    normalDb' = normalise normalDb
    tmpRoot = normalise "/tmp"
    relative = makeRelative tmpRoot candidate'
    escapesTmp =
      isAbsolute relative
        || case splitDirectories relative of
             ("..":_) -> True
             _ -> False

-- | Return only keys absent from the pre-discovery network. Existing edges,
-- including provider-supplied replacements, are not smoke persistence input.
newSemanticEdges :: SemanticNetwork -> SemanticNetwork -> [SemanticEdge]
newSemanticEdges baseline discovered =
  M.elems (M.difference (snEdges discovered) (snEdges baseline))
