{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.CoreBehavior (coreBehaviorTests)
import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.RuntimeInfrastructure (runtimeInfrastructureTests)
import Test.Suite.HttpRuntime (httpRuntimeTests)
import Test.Suite.SemanticCorpus (semanticCorpusTests)
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.LegalAdapter (legalAdapterTests)
import Test.Suite.RenderDialogueCoverage (renderDialogueCoverageTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (coreBehaviorTests ++ turnPipelineProtocolTests ++ runtimeInfrastructureTests ++ httpRuntimeTests ++ semanticCorpusTests ++ lexiconTests ++ legalAdapterTests ++ renderDialogueCoverageTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
