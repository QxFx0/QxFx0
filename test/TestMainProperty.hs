{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.SelfDeliberation (selfDeliberationTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (turnPipelineProtocolTests ++ selfDeliberationTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
