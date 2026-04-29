{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Resource readiness checks for runtime bootstrapping and strict/degraded mode decisions. -}
module QxFx0.Resources.Readiness
  ( assessResourceReadiness
  , checkResourceReadiness
  , ReadinessStatus(..)
  , ReadinessComponent(..)
  , ReadinessMode(..)
  , computeReadinessMode
  ) where

import QxFx0.ExceptionPolicy (tryQxFx0)
import QxFx0.Resources.Morphology (validateMorphologyResources)
import QxFx0.Resources.Paths
  ( ResourcePaths(..)
  , resolveResourcePaths
  )
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (takeDirectory)

data ReadinessComponent
  = RcResourceRoot
  | RcDatabase
  | RcMorphology
  | RcNixPolicy
  | RcAgdaSpec
  | RcDatalogRules
  | RcSchema
  deriving stock (Show, Eq, Enum, Bounded)

data ReadinessStatus = ReadinessStatus
  { rsComponents :: [(ReadinessComponent, Bool, String)]
  , rsIsReady    :: Bool
  , rsIsDegraded :: Bool
  } deriving stock (Show, Eq)

data ReadinessMode
  = Ready
  | Degraded [ReadinessComponent]
  | NotReady [ReadinessComponent]
  deriving stock (Show, Eq)

assessResourceReadiness :: FilePath -> IO ReadinessStatus
assessResourceReadiness dbFile = do
  dbExists <- doesFileExist dbFile
  dbDirOk <- doesDirectoryExist (takeDirectory dbFile)
  let dbOk = dbExists || dbDirOk
  pathsResult <- tryQxFx0 resolveResourcePaths
  case pathsResult of
    Left err -> pure (resourceRootFailureStatus dbOk dbFile (show err))
    Right paths -> checkResourceReadiness paths dbFile

checkResourceReadiness :: ResourcePaths -> FilePath -> IO ReadinessStatus
checkResourceReadiness paths dbFile = do
  dbExists <- doesFileExist dbFile
  dbDirOk <- doesDirectoryExist (takeDirectory dbFile)
  let dbOk = dbExists || dbDirOk
  checks <- mapM (checkComponent paths dbOk) [minBound .. maxBound]
  let critical = [RcResourceRoot, RcDatabase, RcMorphology, RcSchema]
      allOk = all (\(_, ok, _) -> ok) checks
      criticalOk = all (\(c, ok, _) -> c `notElem` critical || ok) checks
      degraded = criticalOk && not allOk
  pure ReadinessStatus
    { rsComponents = checks
    , rsIsReady = criticalOk
    , rsIsDegraded = degraded
    }
  where
    checkComponent :: ResourcePaths -> Bool -> ReadinessComponent -> IO (ReadinessComponent, Bool, String)
    checkComponent rp dbOk rc = case rc of
      RcResourceRoot ->
        pure (rc, True, "Resource root resolved: " ++ rpResourceDir rp)
      RcDatabase ->
        pure (rc, dbOk, if dbOk then "DB path accessible" else "DB directory not accessible: " ++ dbFile)
      RcMorphology -> do
        (ok, detail) <- validateMorphologyResources (rpMorphologyDir rp)
        pure (rc, ok, detail)
      RcNixPolicy -> do
        ok <- doesFileExist (rpNixGuard rp)
        pure (rc, ok, if ok then "Nix policy found" else "Nix policy missing (optional): " ++ rpNixGuard rp)
      RcAgdaSpec -> do
        ok <- doesFileExist (rpAgdaSpec rp)
        pure (rc, ok, if ok then "Agda spec found" else "Agda spec missing (optional): " ++ rpAgdaSpec rp)
      RcDatalogRules -> do
        ok <- doesFileExist (rpDatalogRules rp)
        pure (rc, ok, if ok then "Datalog rules found" else "Datalog rules missing (optional): " ++ rpDatalogRules rp)
      RcSchema -> do
        ok <- doesFileExist (rpSchemaSql rp)
        pure (rc, ok, if ok then "Schema SQL found" else "Schema SQL missing: " ++ rpSchemaSql rp)

computeReadinessMode :: ReadinessStatus -> ReadinessMode
computeReadinessMode status =
  let critical = [RcResourceRoot, RcDatabase, RcMorphology, RcSchema]
      failedCritical = [c | (c, ok, _) <- rsComponents status, not ok, c `elem` critical]
      failedOptional = [c | (c, ok, _) <- rsComponents status, not ok, c `notElem` critical]
  in if not (null failedCritical)
       then NotReady failedCritical
       else if null failedOptional then Ready else Degraded failedOptional

resourceRootFailureStatus :: Bool -> FilePath -> String -> ReadinessStatus
resourceRootFailureStatus dbOk dbFile msg =
  ReadinessStatus
    { rsComponents =
        [ (RcResourceRoot, False, "Resource root unavailable: " ++ msg)
        , (RcDatabase, dbOk, if dbOk then "DB path accessible" else "DB directory not accessible: " ++ dbFile)
        , (RcMorphology, False, "Morphology unavailable because resource root could not be resolved")
        , (RcNixPolicy, False, "Nix policy unavailable because resource root could not be resolved")
        , (RcAgdaSpec, False, "Agda spec unavailable because resource root could not be resolved")
        , (RcDatalogRules, False, "Datalog rules unavailable because resource root could not be resolved")
        , (RcSchema, False, "Schema SQL unavailable because resource root could not be resolved")
        ]
    , rsIsReady = False
    , rsIsDegraded = False
    }
