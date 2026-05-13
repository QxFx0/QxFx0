{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList turnPipelineProtocolTests
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
