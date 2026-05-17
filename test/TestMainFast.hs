{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.CoreBehavior (coreBehaviorTests)
import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.SemanticCorpus (semanticCorpusTests)
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.SelfBlanket (selfBlanketTests)
import Test.Suite.SelfConatus (selfConatusTests)
import Test.Suite.SelfAdjunction (selfAdjunctionTests)
import Test.Suite.SelfField (selfFieldTests)
import Test.Suite.SelfSalience (selfSalienceTests)
import Test.Suite.PhaseM2d (phaseM2dTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (coreBehaviorTests ++ turnPipelineProtocolTests ++ semanticCorpusTests ++ lexiconTests ++ selfBlanketTests ++ selfConatusTests ++ selfAdjunctionTests ++ selfFieldTests ++ selfSalienceTests ++ phaseM2dTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
