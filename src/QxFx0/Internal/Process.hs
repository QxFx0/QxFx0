{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Internal.Process
  ( resolveTrustedExecutable
  ) where

import Control.Monad (filterM)
import Data.List (nub)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.ExceptionPolicy (catchIO)
import QxFx0.Internal.FilePath (isPathWithin)
import System.Directory
  ( canonicalizePath
  , doesDirectoryExist
  , doesFileExist
  , findExecutable
  , getPermissions
  )
import qualified System.Directory as Directory (executable)
import System.Environment (lookupEnv)
import System.FilePath (isPathSeparator)

resolveTrustedExecutable :: FilePath -> Maybe FilePath -> [FilePath] -> IO (Either Text FilePath)
resolveTrustedExecutable fallbackCommand mConfigured extraSearchRoots =
  case sanitizeCandidate =<< mConfigured of
    Just configured -> resolveCandidate True configured
    Nothing -> resolveCandidate False fallbackCommand
  where
    resolveCandidate :: Bool -> FilePath -> IO (Either Text FilePath)
    resolveCandidate explicitConfig candidate
      | any isPathSeparator candidate = validateExplicitCandidate candidate
      | explicitConfig = resolveNamedTrustedCandidate candidate
      | otherwise = resolveNamedTrustedCandidate candidate

    resolveNamedTrustedCandidate :: FilePath -> IO (Either Text FilePath)
    resolveNamedTrustedCandidate candidate = do
      mResolved <- findExecutable candidate
      case mResolved of
        Nothing -> pure (Left (missingExecutableMessage candidate))
        Just path -> validateTrustedSearchCandidate candidate path

    validateExplicitCandidate :: FilePath -> IO (Either Text FilePath)
    validateExplicitCandidate candidate = do
      resolvedResult <- canonicalizePathSafe candidate
      case resolvedResult of
        Left err -> pure (Left err)
        Right resolved -> validateExecutable resolved

    validateTrustedSearchCandidate :: FilePath -> FilePath -> IO (Either Text FilePath)
    validateTrustedSearchCandidate commandName candidate = do
      resolvedResult <- canonicalizePathSafe candidate
      case resolvedResult of
        Left err -> pure (Left err)
        Right resolved -> do
          executableResult <- validateExecutable resolved
          case executableResult of
            Left err -> pure (Left err)
            Right validPath -> do
              trustedRoots <- resolveTrustedSearchRoots extraSearchRoots
              trustedMatches <- mapM (`isPathWithin` validPath) trustedRoots
              pure $
                if or trustedMatches
                  then Right validPath
                  else Left (untrustedExecutableMessage commandName validPath)

canonicalizePathSafe :: FilePath -> IO (Either Text FilePath)
canonicalizePathSafe path =
  catchIO
    (Right <$> canonicalizePath path)
    (\err -> pure (Left ("cannot resolve executable path: " <> T.pack (show err))))

validateExecutable :: FilePath -> IO (Either Text FilePath)
validateExecutable candidate = do
  exists <- doesFileExist candidate
  if not exists
    then pure (Left ("configured executable missing: " <> T.pack candidate))
    else do
      perms <- getPermissions candidate
      pure $
        if Directory.executable perms
          then Right candidate
          else Left ("configured executable is not executable: " <> T.pack candidate)

resolveTrustedSearchRoots :: [FilePath] -> IO [FilePath]
resolveTrustedSearchRoots extraRoots = do
  mRoot <- lookupEnv "QXFX0_ROOT"
  mResourceRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mHome <- lookupEnv "HOME"
  let configuredRoots =
        [ "/nix/store"
        , "/usr/bin"
        , "/usr/local/bin"
        , "/bin"
        , "/run/current-system/sw/bin"
        ]
      homeRoots =
        case mHome of
          Just home -> [home <> "/.local/bin", home <> "/.cabal/bin"]
          Nothing -> []
      candidates = nub (configuredRoots <> homeRoots <> extraRoots <> maybeToList mRoot <> maybeToList mResourceRoot)
  existing <- filterM doesDirectoryExist candidates
  canonical <- mapM canonicalizePath existing
  pure (nub canonical)

sanitizeCandidate :: FilePath -> Maybe FilePath
sanitizeCandidate raw =
  let trimmed = reverse (dropWhile (== ' ') (reverse (dropWhile (== ' ') raw)))
  in if null trimmed then Nothing else Just trimmed

missingExecutableMessage :: FilePath -> Text
missingExecutableMessage commandName =
  "executable not found in PATH: " <> T.pack commandName

untrustedExecutableMessage :: FilePath -> FilePath -> Text
untrustedExecutableMessage commandName resolvedPath =
  "PATH-resolved executable is outside trusted roots for "
    <> T.pack commandName
    <> ": "
    <> T.pack resolvedPath
