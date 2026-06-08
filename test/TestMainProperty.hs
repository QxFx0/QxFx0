{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.SelfDeliberation (selfDeliberationTests)
import Test.Suite.BoundedLists (boundedListsTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (turnPipelineProtocolTests ++ selfDeliberationTests ++ boundedListsTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
