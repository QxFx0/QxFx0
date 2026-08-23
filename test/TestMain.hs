{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Environment (lookupEnv)
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
import Test.Suite.SelfDivergence (selfDivergenceTests)
import Test.Suite.ControlAAblation (controlAAblationTests)
import Test.Suite.EssenceCollapse (essenceCollapseTests)
import Test.Suite.CrisisGuard (crisisGuardTests)
import Test.Suite.UserR5 (userR5Tests)
import Test.Suite.OntologicalAxis (ontologicalAxisTests)
import Test.Suite.MoveGraph (moveGraphTests)
import Test.Suite.P5Governance (p5GovernanceTests)
import Test.Suite.LongSessionCorpus (longSessionCorpusTests)
import Test.Suite.PhaseM2d (phaseM2dTests)
import Test.Suite.VecProperties (vecPropertiesTests)
import Test.Suite.EgoRead (egoReadTests)
import Test.Suite.LearningLoop (learningLoopTests)
import Test.Suite.TrainingCycle (trainingCycleTests)
import Test.Suite.ReliabilityHardening (reliabilityHardeningTests)
import Test.Suite.M6Witness (m6WitnessTests)
import Test.Suite.M6FeltGate (m6FeltGateTests)
import Test.Suite.M6FeltBenchmark (m6FeltBenchmarkTests)
import Test.Suite.M5Regime (m5RegimeTests)
import Test.Suite.SubstrateNetwork (substrateTests)
import Test.Suite.MorphologicalNormalization (morphologicalNormalizationTests)
import Test.Suite.AtomStore (atomStoreTests)
import Test.Suite.PathFinder (pathFinderTests)
import Test.Suite.GeneratedPredicateGate (generatedPredicateGateTests)
import Test.Suite.SubstrateCandidate (substrateCandidateTests)
import Test.Suite.SemanticContentB3 (semanticContentB3Tests)
import Test.Suite.SemanticRepairB3 (semanticRepairB3Tests)
import Test.Suite.B3MechanicalGateExecution (b3MechanicalGateExecutionTests)
import Test.Suite.ContentQualityGate (contentQualityGateTests)

main :: IO ()
main = do
  mGroup <- lookupEnv "QXFX0_AGGREGATE_GROUP"
  let coreTests = coreBehaviorTests ++ architectureInvariantTests ++ selfPerspectiveTests ++ perspectiveRegistryTests ++ guardrailsTests ++ knowledgeTreeTests ++ dialogueDevelopmentTests ++ turnPipelineProtocolTests
        ++ semanticCorpusTests ++ lexiconTests ++ legalAdapterTests ++ renderDialogueCoverageTests ++ observerDisciplineTests ++ traceSchemaTests ++ regenerableDerivedTests ++ promotionFlagDisciplineTests ++ replayGateTests ++ russianQualityTests ++ selfBlanketTests ++ selfConatusTests ++ selfAdjunctionTests ++ selfFieldTests ++ selfSalienceTests ++ selfDeliberationTests ++ selfEssenceTests ++ selfEssenceCommitTests ++ selfDivergenceTests ++ controlAAblationTests ++ essenceCollapseTests ++ crisisGuardTests ++ userR5Tests ++ ontologicalAxisTests ++ moveGraphTests ++ p5GovernanceTests ++ phaseM2dTests ++ longSessionCorpusTests ++ vecPropertiesTests ++ egoReadTests ++ learningLoopTests ++ trainingCycleTests ++ reliabilityHardeningTests ++ m6WitnessTests ++ m6FeltGateTests ++ m6FeltBenchmarkTests ++ m5RegimeTests ++ substrateTests ++ morphologicalNormalizationTests ++ atomStoreTests ++ pathFinderTests ++ generatedPredicateGateTests ++ substrateCandidateTests ++ semanticContentB3Tests ++ semanticRepairB3Tests ++ b3MechanicalGateExecutionTests ++ contentQualityGateTests
      groups =
        [ ("core", coreTests)
        , ("runtime", runtimeInfrastructureTests)
        , ("http", httpRuntimeTests)
        ]
      selected = case mGroup of
        Nothing -> concatMap snd groups
        Just group -> case lookup group groups of
          Just tests -> tests
          Nothing -> error ("Unknown QXFX0_AGGREGATE_GROUP: " ++ group)
  testCounts <- runTestTT $ TestList selected
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess

