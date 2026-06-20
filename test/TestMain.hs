{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.CoreBehavior (coreBehaviorTests)
import Test.Suite.ArchitectureInvariants (architectureInvariantTests)
import Test.Suite.SelfPerspective (selfPerspectiveTests)
import Test.Suite.PerspectiveRegistry (perspectiveRegistryTests)
import Test.Suite.Guardrails (guardrailsTests)
import Test.Suite.KnowledgeTree (knowledgeTreeTests)
import Test.Suite.DialogueDevelopment (dialogueDevelopmentTests)
import Test.Suite.TurnPipelineProtocol (turnPipelineProtocolTests)
import Test.Suite.RuntimeInfrastructure (runtimeInfrastructureTests)
import Test.Suite.HttpRuntime (httpRuntimeTests)
import Test.Suite.SemanticCorpus (semanticCorpusTests)
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.LegalAdapter (legalAdapterTests)
import Test.Suite.RenderDialogueCoverage (renderDialogueCoverageTests)
import Test.Suite.ObserverDiscipline (observerDisciplineTests)
import Test.Suite.TraceSchema (traceSchemaTests)
import Test.Suite.RegenerableDerived (regenerableDerivedTests)
import Test.Suite.PromotionFlagDiscipline (promotionFlagDisciplineTests)
import Test.Suite.ReplayGate (replayGateTests)
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
import Test.Suite.ReliabilityHardening (reliabilityHardeningTests)
import Test.Suite.M6Witness (m6WitnessTests)
import Test.Suite.M5Regime (m5RegimeTests)
import Test.Suite.SubstrateNetwork (substrateTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (coreBehaviorTests ++ architectureInvariantTests ++ selfPerspectiveTests ++ perspectiveRegistryTests ++ guardrailsTests ++ knowledgeTreeTests ++ dialogueDevelopmentTests ++ turnPipelineProtocolTests ++ runtimeInfrastructureTests ++ httpRuntimeTests
     ++ semanticCorpusTests ++ lexiconTests ++ legalAdapterTests ++ renderDialogueCoverageTests      ++ observerDisciplineTests ++ traceSchemaTests ++ regenerableDerivedTests ++ promotionFlagDisciplineTests ++ replayGateTests ++ russianQualityTests ++ selfBlanketTests ++ selfConatusTests ++ selfAdjunctionTests    ++ selfFieldTests ++ selfSalienceTests ++ selfDeliberationTests ++ selfEssenceTests ++ selfEssenceCommitTests ++ p5GovernanceTests ++ phaseM2dTests ++ longSessionCorpusTests ++ vecPropertiesTests ++ egoReadTests ++ learningLoopTests ++ trainingCycleTests ++ reliabilityHardeningTests ++ m6WitnessTests ++ m5RegimeTests ++ substrateTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
