{-# LANGUAGE OverloadedStrings #-}

module Test.Support
  ( assertExec
  , queryCount
  , withFakeSouffle
  , withFakeNixInstantiateOk
  , withRuntimeEnv
  , withStrictRuntimeEnv
  , withEnvVar
  , removeIfExists
  , removeDirIfExists
  , testTempDir
  , freshTestPath
  , freshTestDbPath
  ) where

import Test.HUnit (assertFailure)
import Control.Exception (bracket_)
import System.Directory
  ( Permissions(..)
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , findExecutable
  , getCurrentDirectory
  , getPermissions
  , removeFile
  , removePathForcibly
  , setPermissions
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified Data.Text as T

import qualified QxFx0.Bridge.AgdaWitness as AW
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Runtime as Runtime

freshTestPath :: FilePath -> IO FilePath
freshTestPath stem = do
  tmpDir <- testTempDir
  ts <- getPOSIXTime
  let suffix = show (round (ts * 1000000) :: Integer)
  pure (tmpDir <> "/" <> stem <> "-" <> suffix)

freshTestDbPath :: FilePath -> IO FilePath
freshTestDbPath = freshTestPath

assertExec :: NSQL.Database -> FilePath -> T.Text -> IO ()
assertExec db label sql = do
  result <- NSQL.execSql db sql
  case result of
    Left err -> assertFailure ("SQL apply failed for " <> label <> ": " <> T.unpack err)
    Right _ -> pure ()

queryCount :: NSQL.Database -> T.Text -> IO Int
queryCount db sql = do
  stmtRes <- NSQL.prepare db sql
  stmt <- case stmtRes of
    Left err -> assertFailure ("Prepare failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  hasRow <- NSQL.stepRow stmt
  count <- if hasRow then NSQL.columnInt stmt 0 else pure 0
  NSQL.finalize stmt
  pure count

withFakeSouffle :: IO a -> IO a
withFakeSouffle action = do
  oldPath <- lookupEnv "PATH"
  binDir <- freshTestPath "qxfx0_fake_souffle_bin"
  let cleanup = removeDirIfExists binDir
      scriptPath = binDir </> "souffle"
      fakePath = binDir <> maybe "" (\p -> ":" <> p) oldPath
  bracket_ (createDirectoryIfMissing True binDir) cleanup $ do
    writeFile scriptPath (unlines fakeSouffleScript)
    perms <- getPermissions scriptPath
    setPermissions scriptPath perms { executable = True }
    withEnvVar "PATH" (Just fakePath) action
  where
    fakeSouffleScript =
      [ "#!/bin/sh"
      , "outdir=''"
      , "dlfile=''"
      , "while [ \"$#\" -gt 0 ]; do"
      , "  if [ \"$1\" = \"-D\" ]; then"
      , "    outdir=\"$2\""
      , "    shift 2"
      , "  else"
      , "    dlfile=\"$1\""
      , "    shift"
      , "  fi"
      , "done"
      , "if grep -qx 'InputAtom(\"NeedContact\").' \"$dlfile\"; then"
      , "  printf 'CMContact\\tIFContact\\tDeclarative\\tContactLayer\\tAlwaysWarranted\\n' > \"$outdir/R5Verdict.csv\""
      , "  printf 'requested_family_shift\\tatom_signals_overrode_requested_family\\n' > \"$outdir/ShadowAlert.csv\""
      , "else"
      , "  printf 'CMGround\\tIFAssert\\tDeclarative\\tContentLayer\\tAlwaysWarranted\\n' > \"$outdir/R5Verdict.csv\""
      , "  : > \"$outdir/ShadowAlert.csv\""
      , "fi"
      ]

withFakeNixInstantiateOk :: IO a -> IO a
withFakeNixInstantiateOk action = do
  oldPath <- lookupEnv "PATH"
  binDir <- freshTestPath "qxfx0_fake_nix_bin"
  let cleanup = removeDirIfExists binDir
      scriptPath = binDir </> "nix-instantiate"
      fakePath = binDir <> maybe "" (\p -> ":" <> p) oldPath
  bracket_ (createDirectoryIfMissing True binDir) cleanup $ do
    writeFile scriptPath (unlines fakeNixScript)
    perms <- getPermissions scriptPath
    setPermissions scriptPath perms { executable = True }
    withEnvVar "PATH" (Just fakePath) action
  where
    fakeNixScript =
      [ "#!/bin/sh"
      , "printf 'true\\n'"
      ]

testTempDir :: IO FilePath
testTempDir = do
  root <- getCurrentDirectory
  let dir = root <> "/.test-tmp"
  createDirectoryIfMissing True dir
  pure dir

withRuntimeEnv :: FilePath -> IO a -> IO a
withRuntimeEnv dbName action = do
  root <- getCurrentDirectory
  dbPath <- freshTestDbPath dbName
  stateDir <- freshTestPath (dbName <> ".state")
  bracket_
    (do
      mapM_ removeIfExists (runtimeArtifacts dbPath)
      removeDirIfExists stateDir)
    (do
      mapM_ removeIfExists (runtimeArtifacts dbPath)
      removeDirIfExists stateDir)
    $ withEnvVar "QXFX0_ROOT" (Just root) $
        withEnvVar "QXFX0_DB" (Just dbPath) $
          withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
            withEnvVar "QXFX0_RUNTIME_MODE" (Just "degraded") $
              action

withStrictRuntimeEnv :: FilePath -> IO a -> IO a
withStrictRuntimeEnv dbName action = do
  root <- getCurrentDirectory
  dbPath <- freshTestDbPath dbName
  witnessPath <- freshTestPath (dbName <> ".agda-witness.json")
  stateDir <- freshTestPath (dbName <> ".state")
  let cleanup = witnessPath : runtimeArtifacts dbPath
  bracket_
    (do
      mapM_ removeIfExists cleanup
      removeDirIfExists stateDir)
    (do
      mapM_ removeIfExists cleanup
      removeDirIfExists stateDir)
    $ withFakeSouffle $
        withFakeNixInstantiateOk $
          withEnvVar "QXFX0_ROOT" (Just root) $
            withEnvVar "QXFX0_DB" (Just dbPath) $
              withEnvVar "QXFX0_STATE_DIR" (Just stateDir) $
                withEnvVar "QXFX0_RUNTIME_MODE" (Just "strict") $
                  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "local-deterministic") $
                    withEnvVar "EMBEDDING_API_URL" Nothing $
                      withEnvVar "QXFX0_AGDA_WITNESS" (Just witnessPath) $ do
                        mAgda <- findExecutable "agda"
                        case mAgda of
                          Just _  -> do
                            _ <- Runtime.writeAgdaWitness
                            action
                          Nothing -> do
                            AW.writeStubAgdaWitness witnessPath
                            action

withEnvVar :: String -> Maybe String -> IO a -> IO a
withEnvVar key mValue action = do
  old <- lookupEnv key
  let apply = case mValue of
        Just value -> setEnv key value
        Nothing -> unsetEnv key
      restore = case old of
        Just value -> setEnv key value
        Nothing -> unsetEnv key
  bracket_ apply restore action

removeIfExists :: FilePath -> IO ()
removeIfExists filePath = do
  exists <- doesFileExist filePath
  if exists then removeFile filePath else pure ()

removeDirIfExists :: FilePath -> IO ()
removeDirIfExists dirPath = do
  exists <- doesDirectoryExist dirPath
  if exists then removePathForcibly dirPath else pure ()

_withCleanFiles :: [FilePath] -> IO a -> IO a
_withCleanFiles paths =
  bracket_
    (mapM_ removeIfExists paths)
    (mapM_ removeIfExists paths)

runtimeArtifacts :: FilePath -> [FilePath]
runtimeArtifacts dbPath =
  [ dbPath
  , dbPath <> "-wal"
  , dbPath <> "-shm"
  , dbPath <> ".http-session-tokens.json"
  , dbPath <> ".http-session-tokens.json.tmp"
  ]
