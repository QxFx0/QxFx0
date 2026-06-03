{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Char (toLower)
import Data.List (isInfixOf)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import Test.HUnit

import Test.Suite.SemanticSlices (semanticSliceTests)

main :: IO ()
main = do
  mFilter <- lookupEnv "QXFX0_SEMANTIC_SLICE_FILTER"
  let selectedTests = maybe semanticSliceTests (`filterSemanticSliceTests` semanticSliceTests) mFilter
  testCounts <- runTestTT $ TestList selectedTests
  if errors testCounts + failures testCounts > 0
    then exitFailure
    else exitSuccess

filterSemanticSliceTests :: String -> [Test] -> [Test]
filterSemanticSliceTests rawQuery = filter matches
  where
    query = map toLower rawQuery
    matches (TestLabel label _) = query `isInfixOf` map toLower label
    matches _ = False
