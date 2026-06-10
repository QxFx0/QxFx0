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
import Test.Suite.LexiconTests (lexiconTests)
import Test.Suite.VecProperties (vecPropertiesTests)
import Test.Suite.BoundedLists (boundedListsTests)
import Test.Suite.EgoRead (egoReadTests)
import Test.Suite.SelfBlanket (selfBlanketTests)
import Test.Suite.SelfConatus (selfConatusTests)
import Test.Suite.ConatusGate (conatusGateTests)
import Test.Suite.SelfAdjunction (selfAdjunctionTests)
import Test.Suite.SelfField (selfFieldTests)
import Test.Suite.ReplayGate (replayGateTests)
import Test.Suite.ReplayDeterminism (replayDeterminismTests)
import Test.Suite.AdmissionEquivalence (admissionEquivalenceTests)
import Test.Suite.TraceSchema (traceSchemaTests)
import Test.Suite.RegenerableDerived (regenerableDerivedTests)
import Test.Suite.PromotionFlagDiscipline (promotionFlagDisciplineTests)
import Test.Suite.SelfSalience (selfSalienceTests)
import Test.Suite.SelfDeliberation (selfDeliberationTests)
import Test.Suite.SelfEssence (selfEssenceTests)
import Test.Suite.SelfEssenceCommit (selfEssenceCommitTests)
import Test.Suite.P5Governance (p5GovernanceTests)
import Test.Suite.PhaseM2d (phaseM2dTests)
import Test.Suite.LearningLoop (learningLoopTests)
import Test.Suite.TrainingCycle (trainingCycleTests)
import Test.Suite.DreamPressure (dreamPressureTests)
import Test.Suite.DatalogSafety (datalogSafetyTests)
import Test.Suite.SandboxBoundary (sandboxBoundaryTests)
import Test.Suite.PGFErrorHandling (pgfErrorHandlingTests)
import Test.Suite.StructuredErrors (structuredErrorsTests)
import Test.Suite.Observability (observabilityTests)
import Test.Suite.TraceAnalysis (traceAnalysisTests)
import Test.Suite.DoubtLoop (doubtLoopTests)
import Test.Suite.ContentSalience (contentSalienceTests)
import Test.Suite.MemoryEpisodic (episodicMemoryTests)
import Test.Suite.AffectModel (affectModelTests)
import Test.Suite.ResponseContentAdmission (responseContentAdmissionTests)
import Test.Suite.ConfigExternalize (configExternalizeTests)
import Test.Suite.CommitmentStoreAdmission (commitmentStoreAdmissionTests)
import Test.Suite.CommitmentQuarantine (commitmentQuarantineTests)
import Test.Suite.CommitmentAwareRouting (commitmentAwareRoutingTests)

main :: IO ()
main = do
  testCounts <-
    runTestTT $
      TestList
        ( coreBehaviorTests
        ++ architectureInvariantTests
        ++ selfPerspectiveTests
        ++ perspectiveRegistryTests
        ++ guardrailsTests
        ++ knowledgeTreeTests
        ++ dialogueDevelopmentTests
        ++ turnPipelineProtocolTests
        ++ lexiconTests
        ++ vecPropertiesTests
        ++ boundedListsTests
        ++ egoReadTests
        ++ selfConatusTests
        ++ conatusGateTests
        ++ selfBlanketTests
        ++ selfAdjunctionTests
         ++ selfFieldTests
         ++ replayGateTests
         ++ replayDeterminismTests
         ++ admissionEquivalenceTests
         ++ selfSalienceTests
           ++ selfDeliberationTests
           ++ traceSchemaTests
           ++ regenerableDerivedTests
           ++ promotionFlagDisciplineTests
            ++ selfEssenceTests
            ++ selfEssenceCommitTests
            ++ p5GovernanceTests
            ++ phaseM2dTests
            ++ learningLoopTests
            ++ trainingCycleTests
           
            ++ dreamPressureTests
            ++ datalogSafetyTests
            ++ sandboxBoundaryTests
            ++ pgfErrorHandlingTests
            ++ structuredErrorsTests
            ++ observabilityTests
            ++ traceAnalysisTests
            ++ doubtLoopTests
            ++ contentSalienceTests
            ++ episodicMemoryTests
             ++ affectModelTests
              ++ responseContentAdmissionTests
              ++ configExternalizeTests
                ++ commitmentStoreAdmissionTests
                ++ commitmentQuarantineTests
                ++ commitmentAwareRoutingTests
             )
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
