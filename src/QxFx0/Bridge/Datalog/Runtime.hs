{-# LANGUAGE OverloadedStrings #-}

{-| Runtime execution path for Souffle resolution, rule loading, and shadow runs. -}
module QxFx0.Bridge.Datalog.Runtime
  ( compileAndRunDatalog
  , compileAndRunDatalogWithExecutable
  , runDatalogShadow
  , runDatalogShadowWithExecutable
  , resolveSouffleExecutable
  ) where

import Control.Exception (finally)
import Control.Monad (filterM)
import Data.Char (isSpace)
import Data.List (isPrefixOf, nub)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Text.Read (readMaybe)
import System.Directory
  ( canonicalizePath
  , doesDirectoryExist
  , doesFileExist
  , findExecutable
  , getPermissions
  )
import qualified System.Directory as Directory (executable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), isPathSeparator, normalise, splitDirectories, takeDirectory, takeFileName)
import System.Process (CreateProcess(cwd), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
import System.Timeout (timeout)

import QxFx0.Bridge.Datalog.Compare (compareShadowOutput)
import QxFx0.Bridge.Datalog.Support
  ( DatalogExecution(..)
  , buildShadowSnapshot
  , compactDiagnostic
  , createShadowTempFiles
  , parseShadowOutput
  , renderRuntimeFacts
  )
import QxFx0.Bridge.Datalog.Types
  ( ShadowResult(..)
  , shadowUnavailableResult
  )
import QxFx0.ExceptionPolicy (catchIO)
import QxFx0.Resources (resolveResourcePaths, rpDatalogRules, rpResourceDir)
import QxFx0.Types
  ( AtomTag
  , CanonicalMoveFamily
  , IllocutionaryForce
  , R5Verdict
  , forceForFamily
  , mkVerdict
  )
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowSnapshot(..)
  , mkShadowSnapshotId
  )

compileAndRunDatalog :: Text -> CanonicalMoveFamily -> IO (Either Text R5Verdict)
compileAndRunDatalog dlSource fam = do
  programResult <-
    if T.null (T.strip dlSource)
      then loadDatalogProgram
      else pure (Right dlSource)
  case programResult of
    Left err -> pure (Left err)
    Right program -> do
      execResult <- resolveSouffleExecutable
      case execResult of
        Left err -> pure (Left err)
        Right executable ->
          fmap deVerdict
            <$> executeDatalogShadowWithExecutable
                  executable
                  program
                  (buildShadowSnapshot fam (forceForFamily fam) [])

compileAndRunDatalogWithExecutable :: FilePath -> Text -> CanonicalMoveFamily -> IO (Either Text R5Verdict)
compileAndRunDatalogWithExecutable executable dlSource fam = do
  programResult <-
    if T.null (T.strip dlSource)
      then loadDatalogProgram
      else pure (Right dlSource)
  case programResult of
    Left err -> pure (Left err)
    Right program ->
      fmap deVerdict
        <$> executeDatalogShadowWithExecutable
              executable
              program
              (buildShadowSnapshot fam (forceForFamily fam) [])

runDatalogShadow :: CanonicalMoveFamily -> IllocutionaryForce -> [AtomTag] -> IO ShadowResult
runDatalogShadow fam force atoms = do
  let snapshot = buildShadowSnapshot fam force atoms
  programResult <- loadDatalogProgram
  case programResult of
    Left err -> pure (shadowUnavailableResult snapshot ShadowExecutionError err)
    Right _ -> do
      execResult <- resolveSouffleExecutable
      case execResult of
        Left err -> pure (shadowUnavailableResult snapshot ShadowUnavailableDivergence err)
        Right executable -> runDatalogShadowWithExecutableSnapshot executable snapshot

runDatalogShadowWithExecutable :: FilePath -> CanonicalMoveFamily -> IllocutionaryForce -> [AtomTag] -> IO ShadowResult
runDatalogShadowWithExecutable executable fam force atoms =
  runDatalogShadowWithExecutableSnapshot executable (buildShadowSnapshot fam force atoms)

resolveSouffleExecutable :: IO (Either Text FilePath)
resolveSouffleExecutable = do
  envConfigured <- lookupEnv "QXFX0_SOUFFLE_BIN"
  case nonEmptyString (fmap stripWhitespace envConfigured) of
    Just candidate ->
      resolveConfiguredSouffleExecutable candidate
    Nothing -> do
      localPath <- findExecutable "souffle"
      case localPath of
        Just path -> pure (Right path)
        Nothing -> resolveSouffleExecutableFromFlake

resolveConfiguredSouffleExecutable :: FilePath -> IO (Either Text FilePath)
resolveConfiguredSouffleExecutable configuredPath
  | any isPathSeparator configuredPath =
      validateConfiguredSoufflePath configuredPath
  | otherwise = do
      found <- findExecutable configuredPath
      pure $
        case found of
          Just path -> Right path
          Nothing ->
            Left ("configured souffle executable not found in PATH: " <> T.pack configuredPath)

validateConfiguredSoufflePath :: FilePath -> IO (Either Text FilePath)
validateConfiguredSoufflePath configuredPath =
  catchIO
    (do canonicalPath <- canonicalizePath configuredPath
        exists <- doesFileExist canonicalPath
        if not exists
          then pure (Left ("configured souffle binary missing: " <> T.pack canonicalPath))
          else do
            perms <- getPermissions canonicalPath
            if not (Directory.executable perms)
              then pure (Left ("configured souffle binary is not executable: " <> T.pack canonicalPath))
              else do
                trustedRoots <- resolveSouffleTrustedRoots
                pure $
                  if any (`isPathWithin` canonicalPath) trustedRoots
                    then Right canonicalPath
                    else
                      Left
                        ( "configured souffle binary is outside trusted roots: "
                            <> T.pack canonicalPath
                        ))
    (\e -> pure (Left ("cannot resolve configured souffle binary: " <> compactDiagnostic (T.pack (show e)))))

resolveSouffleTrustedRoots :: IO [FilePath]
resolveSouffleTrustedRoots = do
  mEnvRoot <- lookupEnv "QXFX0_ROOT"
  mResourceRoot <- catchIO
    (Just . rpResourceDir <$> resolveResourcePaths)
    (\_ -> pure Nothing)
  let configuredRoots =
        [ "/nix/store"
        , "/usr/bin"
        , "/usr/local/bin"
        ]
      discoveredRoots =
        maybeToList (nonEmptyString (fmap stripWhitespace mEnvRoot))
          <> maybeToList mResourceRoot
      candidates = nub (configuredRoots <> discoveredRoots)
  existing <- filterM doesDirectoryExist candidates
  mapM canonicalizePath existing

isPathWithin :: FilePath -> FilePath -> Bool
isPathWithin root candidate =
  let rootParts = splitDirectories (normalise root)
      candidateParts = splitDirectories (normalise candidate)
  in rootParts `isPrefixOf` candidateParts

stripWhitespace :: String -> String
stripWhitespace = reverse . dropWhile isSpace . reverse . dropWhile isSpace

nonEmptyString :: Maybe String -> Maybe String
nonEmptyString = (>>= (\value -> if null value then Nothing else Just value))

runDatalogShadowWithExecutableSnapshot :: FilePath -> ShadowSnapshot -> IO ShadowResult
runDatalogShadowWithExecutableSnapshot executable snapshot = do
  let haskellVerdict = mkVerdict (ssRequestedFamily snapshot)
  programResult <- loadDatalogProgram
  case programResult of
    Left err ->
      pure (shadowUnavailableResult snapshot ShadowExecutionError err)
    Right program -> do
      execResult <- executeDatalogShadowWithExecutable executable program snapshot
      case execResult of
        Left err ->
          pure (shadowUnavailableResult snapshot ShadowExecutionError err)
        Right execution -> do
          let datalogVerdict = deVerdict execution
              divergence = compareShadowOutput haskellVerdict datalogVerdict
              anyMismatch =
                or
                  [ sdFamilyMismatch divergence
                  , sdForceMismatch divergence
                  , sdClauseMismatch divergence
                  , sdLayerMismatch divergence
                  , sdWarrantedMismatch divergence
                  ]
          pure ShadowResult
            { srStatus = if anyMismatch then ShadowDiverged else ShadowMatch
            , srDivergence = divergence
            , srDatalogVerdict = Just datalogVerdict
            , srSnapshotId = mkShadowSnapshotId snapshot
            , srDiagnostics = deDiagnostics execution
            }

resolveSouffleExecutableFromFlake :: IO (Either Text FilePath)
resolveSouffleExecutableFromFlake =
  catchIO
    (do paths <- resolveResourcePaths
        let repoRoot = rpResourceDir paths
        evalResult <- resolveSouffleExecutablePathFromFlake repoRoot
        case evalResult of
          Left err -> pure (Left err)
          Right path -> do
            validated <- validateResolvedSouffleExecutable "flake-resolved souffle" path
            case validated of
              Right executable -> pure (Right executable)
              Left missingErr ->
                if "flake-resolved souffle missing:" `T.isPrefixOf` missingErr
                  then materializeSouffleExecutableFromFlake repoRoot
                  else pure (Left missingErr))
    (\e -> pure (Left ("cannot resolve souffle executable: " <> compactDiagnostic (T.pack (show e)))))

resolveSouffleExecutablePathFromFlake :: FilePath -> IO (Either Text FilePath)
resolveSouffleExecutablePathFromFlake repoRoot = do
  let command =
        flakeCommand
          repoRoot
          ["eval", "--raw", ".#apps.x86_64-linux.souffle-runtime.program"]
  (exitCode, stdout, stderr) <- readCreateProcessWithExitCode command ""
  pure $
    case exitCode of
      ExitSuccess -> Right (T.unpack (T.strip (T.pack stdout)))
      ExitFailure _ ->
        Left ("nix eval for souffle-runtime failed: " <> compactDiagnostic (T.pack stderr))

materializeSouffleExecutableFromFlake :: FilePath -> IO (Either Text FilePath)
materializeSouffleExecutableFromFlake repoRoot = do
  let command =
        flakeCommand
          repoRoot
          ["build", "--no-link", "--print-out-paths", ".#souffle-runtime"]
  (exitCode, stdout, stderr) <- readCreateProcessWithExitCode command ""
  case exitCode of
    ExitSuccess -> do
      let outPath = T.unpack (T.strip (T.pack stdout))
          executable = outPath </> "bin" </> "souffle"
      validateResolvedSouffleExecutable "flake-built souffle" executable
    ExitFailure _ ->
      pure (Left ("nix build for souffle-runtime failed: " <> compactDiagnostic (T.pack stderr)))

flakeCommand :: FilePath -> [String] -> CreateProcess
flakeCommand repoRoot args =
  (proc "nix" (["--option", "warn-dirty", "false", "--extra-experimental-features", "nix-command flakes"] <> args))
    { cwd = Just repoRoot }

validateResolvedSouffleExecutable :: Text -> FilePath -> IO (Either Text FilePath)
validateResolvedSouffleExecutable sourceLabel path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (sourceLabel <> " missing: " <> T.pack path))
    else do
      perms <- getPermissions path
      pure $
        if Directory.executable perms
          then Right path
          else Left (sourceLabel <> " is not executable: " <> T.pack path)

loadDatalogProgram :: IO (Either Text Text)
loadDatalogProgram =
  catchIO
    (do paths <- resolveResourcePaths
        let resourceRoot = rpResourceDir paths
            rulesFile = takeFileName (rpDatalogRules paths)
            specDatalogDir = takeDirectory (rpDatalogRules paths)
            checkedPaths =
              nub
                [ specDatalogDir </> rulesFile
                , resourceRoot </> rulesFile
                , rpDatalogRules paths
                ]
        existingPaths <- filterM doesFileExist checkedPaths
        case existingPaths of
          (rulesPath : _) -> Right <$> TIO.readFile rulesPath
          [] ->
            pure
              (Left
                ( "datalog rules missing: checked="
                    <> T.intercalate "|" (map T.pack checkedPaths)
                )
              ))
    (\e -> pure (Left ("cannot load datalog rules: " <> compactDiagnostic (T.pack (show e)))))

executeDatalogShadowWithExecutable :: FilePath -> Text -> ShadowSnapshot -> IO (Either Text DatalogExecution)
executeDatalogShadowWithExecutable executable dlSource snapshot = do
  souffleTimeoutMicros <- resolveSouffleTimeoutMicros
  result <- catchIO
    (do (dlFile, outDir, cleanup) <- createShadowTempFiles
        let program = dlSource <> "\n" <> renderRuntimeFacts snapshot
        finalResult <-
          (do TIO.writeFile dlFile program
              runResult <- timeout souffleTimeoutMicros (readProcessWithExitCode executable ["-D", outDir, dlFile] "")
              case runResult of
                Nothing ->
                  pure
                    (Left
                      ("souffle timed out after " <> T.pack (show (souffleTimeoutMicros `div` 1000)) <> "ms"))
                Just (exitCode, _stdout, stderr) ->
                  case exitCode of
                    ExitSuccess -> parseShadowOutput outDir
                    ExitFailure _ -> pure (Left ("souffle failed: " <> compactDiagnostic (T.pack stderr))))
          `finally` cleanup
        pure finalResult)
    (\e -> pure (Left ("datalog exception: " <> compactDiagnostic (T.pack (show e)))))
  pure result

resolveSouffleTimeoutMicros :: IO Int
resolveSouffleTimeoutMicros = do
  mRaw <- lookupEnv "QXFX0_SOUFFLE_TIMEOUT_MS"
  let timeoutMs =
        case mRaw >>= readMaybe of
          Just n | n > 0 -> n
          _ -> 5000
  pure (timeoutMs * 1000)
