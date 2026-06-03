{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.RuntimeInfrastructure (runtimeInfrastructureTests)
import Test.Suite.StatePersistence (statePersistenceTests)
import Test.Suite.HttpRuntime (httpRuntimeTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (runtimeInfrastructureTests ++ statePersistenceTests ++ httpRuntimeTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
