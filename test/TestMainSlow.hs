{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.RuntimeInfrastructure (runtimeInfrastructureTests, runtimeLifecycleTests)
import Test.Suite.StatePersistence (statePersistenceTests)
import Test.Suite.HttpRuntime (httpRuntimeTests)
import Test.Suite.BootstrapRecovery (bootstrapRecoveryTests)

main :: IO ()
main = do
  mGroup <- lookupEnv "QXFX0_SLOW_GROUP"
  mRuntimeFilter <- lookupEnv "QXFX0_RUNTIME_TEST"
  mStateFilter <- lookupEnv "QXFX0_STATE_TEST"
  mHttpFilter <- lookupEnv "QXFX0_HTTP_TEST"
  let selectedRuntimeTests = maybe runtimeInfrastructureTests (selectTests "QXFX0_RUNTIME_TEST" runtimeInfrastructureTests) mRuntimeFilter
      selectedStateTests = maybe statePersistenceTests (selectTests "QXFX0_STATE_TEST" statePersistenceTests) mStateFilter
      selectedHttpTests = maybe httpRuntimeTests (selectTests "QXFX0_HTTP_TEST" httpRuntimeTests) mHttpFilter
      groupTests =
        [ ("runtime", selectedRuntimeTests)
        , ("state", selectedStateTests)
        , ("http", selectedHttpTests)
        , ("lifecycle", bootstrapRecoveryTests ++ runtimeLifecycleTests)
        ]
      selected = case mGroup of
        Nothing -> concatMap snd groupTests
        Just g -> case lookup g groupTests of
          Just tests -> tests
          Nothing -> error ("Unknown QXFX0_SLOW_GROUP: " ++ g)
  testCounts <- runTestTT $ TestList selected
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess

-- | Select 1-based test indices, for example @QXFX0_HTTP_TEST=1,18@.
selectTests :: String -> [a] -> String -> [a]
selectTests envName tests raw = map select (words (map commaToSpace raw))
  where
    commaToSpace ',' = ' '
    commaToSpace c = c
    select token =
      case reads token of
        [(index, "")]
          | index >= 1 && index <= length tests -> tests !! (index - 1)
        _ -> error ("Invalid " ++ envName ++ " index: " ++ token)
