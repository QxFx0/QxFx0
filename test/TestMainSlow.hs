{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.RuntimeInfrastructure (runtimeInfrastructureTests)
import Test.Suite.StatePersistence (statePersistenceTests)
import Test.Suite.HttpRuntime (httpRuntimeTests)

main :: IO ()
main = do
  mGroup <- lookupEnv "QXFX0_SLOW_GROUP"
  let groupTests =
        [ ("runtime", runtimeInfrastructureTests)
        , ("state", statePersistenceTests)
        , ("http", httpRuntimeTests)
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
