{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.SemanticCorpus (semanticCorpusTests)
import Test.Suite.LegalAdapter (legalAdapterTests)
import Test.Suite.RenderDialogueCoverage (renderDialogueCoverageTests)
import Test.Suite.RussianQuality (russianQualityTests)

main :: IO ()
main = do
  testCounts <- runTestTT $ TestList (semanticCorpusTests ++ legalAdapterTests ++ renderDialogueCoverageTests ++ russianQualityTests)
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess
