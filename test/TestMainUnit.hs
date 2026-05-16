{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.CoreBehavior (coreBehaviorTests)
import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.VecProperties (vecPropertiesTests)
import Test.Suite.EgoRead (egoReadTests)

main :: IO ()
main = do
  testCounts <-
    runTestTT $
      TestList
        ( coreBehaviorTests
        ++ turnPipelineProtocolTests
        ++ lexiconTests
        ++ vecPropertiesTests
        ++ egoReadTests
        )
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
