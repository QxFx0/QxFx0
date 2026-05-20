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
import Test.Suite.SelfConatus (selfConatusTests)
import Test.Suite.SelfAdjunction (selfAdjunctionTests)
import Test.Suite.SelfField (selfFieldTests)
import Test.Suite.SelfSalience (selfSalienceTests)
import Test.Suite.SelfDeliberation (selfDeliberationTests)
import Test.Suite.SelfEssence (selfEssenceTests)
import Test.Suite.SelfEssenceCommit (selfEssenceCommitTests)
import Test.Suite.PhaseM2d (phaseM2dTests)
import Test.Suite.LearningLoop (learningLoopTests)
import Test.Suite.TrainingCycle (trainingCycleTests)

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
        ++ selfConatusTests
        ++ selfBlanketTests
        ++ selfAdjunctionTests
        ++ selfFieldTests
         ++ selfSalienceTests
         ++ selfDeliberationTests
          ++ selfEssenceTests
          ++ selfEssenceCommitTests
          ++ phaseM2dTests
          ++ learningLoopTests
          ++ trainingCycleTests
        )
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
