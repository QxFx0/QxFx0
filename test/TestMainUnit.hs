{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.CoreBehavior (coreBehaviorTests)
import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.VecProperties (vecPropertiesTests)
import Test.Suite.EgoRead (egoReadTests)
import Test.Suite.SelfBlanket (selfBlanketTests)

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
        ++ selfBlanketTests
        )
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
