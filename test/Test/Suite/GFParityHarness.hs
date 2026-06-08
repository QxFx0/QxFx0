{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.GFParityHarness
Description : M3.0 — parity harness infrastructure test.

Verifies the reference table operations and the verifyParity gate.
-}
module Test.Suite.GFParityHarness
  ( gfParityHarnessTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Core.GFParityHarness
import QxFx0.Semantic.Proposition.Types (PropositionType (..))

gfParityHarnessTests :: [Test]
gfParityHarnessTests =
  [ TestLabel "M3-GF: empty reference has no entries" $
      TestCase $ do
        assertEqual "empty table lookup returns Nothing"
          Nothing (lookupParityReference ReflectiveQ emptyParityReference)

  , TestLabel "M3-GF: insert + lookup round-trips" $
      TestCase $ do
        let ref = insertParityReference ReflectiveQ "test output" emptyParityReference
        assertEqual "inserted entry is found"
          (Just "test output") (lookupParityReference ReflectiveQ ref)

  , TestLabel "M3-GF: verifyParity passes for missing entry" $
      TestCase $ do
        assertEqual "no reference => always passes"
          (Right ()) (verifyParity ReflectiveQ "anything" emptyParityReference)

  , TestLabel "M3-GF: verifyParity detects mismatch" $
      TestCase $ do
        let ref = insertParityReference ReflectiveQ "reference text" emptyParityReference
        assertBool "mismatch returns Left"
          (case verifyParity ReflectiveQ "different text" ref of
             Left _ -> True
             Right _ -> False)

  , TestLabel "M3-GF: verifyParity passes on match (stripped)" $
      TestCase $ do
        let ref = insertParityReference ReflectiveQ "match" emptyParityReference
        assertEqual "match passes"
          (Right ()) (verifyParity ReflectiveQ "  match  " ref)
  ]
