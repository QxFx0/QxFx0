{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.SemanticCorpus (semanticCorpusTests)
import Test.Suite.LegalAdapter (legalAdapterTests)
import Test.Suite.RenderDialogueCoverage (renderDialogueCoverageTests)
import Test.Suite.RussianQuality (russianQualityTests)
import Test.Suite.LongSessionCorpus (longSessionCorpusTests)
import Test.Suite.CuratedOntologyIntegration (curatedOntologyIntegrationTests)
import Test.Suite.Anomaly (anomalyProductionBoundaryTests)
import Test.Suite.AutonomousIntegration (autonomousProductionBoundaryTests)
import Test.Suite.StatePersistence (statePersistenceProductionBoundaryTests)

main :: IO ()
main = do
  mGroup <- lookupEnv "QXFX0_INTEGRATION_GROUP"
  let corpusTests =
        semanticCorpusTests
        ++ legalAdapterTests
        ++ renderDialogueCoverageTests
        ++ russianQualityTests
        ++ longSessionCorpusTests
        ++ curatedOntologyIntegrationTests
      item8Tests =
        anomalyProductionBoundaryTests
        ++ autonomousProductionBoundaryTests
        ++ statePersistenceProductionBoundaryTests
      selected = case mGroup of
        Nothing -> corpusTests ++ item8Tests
        Just "corpus" -> corpusTests
        Just "item8" -> item8Tests
        Just groupName -> error ("Unknown QXFX0_INTEGRATION_GROUP: " ++ groupName)
  testCounts <- runTestTT (TestList selected)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
