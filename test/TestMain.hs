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
import Test.Suite.RussianQuality (russianQualityTests)
import Test.Suite.SelfBlanket (selfBlanketTests)
import Test.Suite.SelfConatus (selfConatusTests)
import Test.Suite.SelfAdjunction (selfAdjunctionTests)
import Test.Suite.SelfField (selfFieldTests)
import Test.Suite.SelfSalience (selfSalienceTests)
import Test.Suite.SelfDeliberation (selfDeliberationTests)
import Test.Suite.SelfEssence (selfEssenceTests)
import Test.Suite.SelfEssenceCommit (selfEssenceCommitTests)
import Test.Suite.P5Governance (p5GovernanceTests)
import Test.Suite.LongSessionCorpus (longSessionCorpusTests)
import Test.Suite.PhaseM2d (phaseM2dTests)
import Test.Suite.VecProperties (vecPropertiesTests)
import Test.Suite.EgoRead (egoReadTests)
import Test.Suite.LearningLoop (learningLoopTests)
import Test.Suite.TrainingCycle (trainingCycleTests)
import Test.Suite.ModelComparison (modelComparisonTests)
import Test.Suite.ReliabilityHardening (reliabilityHardeningTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (coreBehaviorTests ++ turnPipelineProtocolTests ++ runtimeInfrastructureTests ++ httpRuntimeTests
     ++ semanticCorpusTests ++ lexiconTests ++ legalAdapterTests ++ renderDialogueCoverageTests ++ russianQualityTests ++ selfBlanketTests ++ selfConatusTests ++ selfAdjunctionTests    ++ selfFieldTests ++ selfSalienceTests ++ selfDeliberationTests ++ selfEssenceTests ++ selfEssenceCommitTests ++ p5GovernanceTests ++ phaseM2dTests ++ longSessionCorpusTests ++ vecPropertiesTests ++ egoReadTests ++ learningLoopTests ++ trainingCycleTests ++ modelComparisonTests ++ reliabilityHardeningTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
