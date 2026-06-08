{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.ConfigExternalize
Description : Round-trip and loader tests for EXTERNALIZE-CONFIG.

EC-0: Round-trip 'decode (encode defaultX) == Just defaultX' for all
four externalized types.

EC-1: Loader behaviour — missing file → builtin; valid JSON → parsed;
malformed JSON → builtin with stderr warning.

EC-2..5: Per-target externalization tests (JSON-absent vs JSON-present).

NOTE: Each test uses a unique temporary path to avoid GHC CSE
(Common Subexpression Elimination) sharing two 'loadConfigOrBuiltin'
applications with the same arguments. The NOINLINE pragma prevents
inlining of the function body, but does not prevent CSE of two
identical applications.
-}
module Test.Suite.ConfigExternalize
  ( configExternalizeTests
  ) where

import Control.Exception (SomeException, catch)
import Data.Aeson (FromJSON, ToJSON, decode, encode)
import qualified Data.ByteString.Lazy as BSL
import System.Directory (removeFile)
import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)

import QxFx0.Self.ConfigLoad (loadConfigOrBuiltin)
import QxFx0.Self.Conatus (ConatusWeights (..), defaultConatusWeights)
import QxFx0.Self.FamilyTargets (FamilyTarget (..), familyTargets)
import QxFx0.Self.Field (FieldHeuristics (..), defaultFieldHeuristics)
import QxFx0.Self.Salience (SalienceWeights (..), defaultSalienceWeights)

-- ---------------------------------------------------------------------------
-- EC-0: Round-trip tests
-- ---------------------------------------------------------------------------

roundTripTest :: (Eq a, Show a, ToJSON a, FromJSON a) => String -> a -> Test
roundTripTest name val =
  TestLabel ("round-trip " <> name) $
    TestCase $ do
      let encoded = encode val
          decoded = decode encoded
      case decoded of
        Nothing -> assertFailure ("decode failed for " <> name)
        Just v  -> assertEqual (name <> " round-trip mismatch") val v

-- ---------------------------------------------------------------------------
-- EC-1: Loader tests
-- ---------------------------------------------------------------------------

loaderTests :: [Test]
loaderTests =
  [ TestLabel "loadConfigOrBuiltin missing file → builtin" $
      TestCase $ do
        let result = loadConfigOrBuiltin "/nonexistent/path.json" (42 :: Int)
        assertEqual "builtin fallback" 42 result

  , TestLabel "loadConfigOrBuiltin valid JSON → parsed" $
      TestCase $ do
        let tmpPath = "/tmp/test_config_externalize_valid.json"
        BSL.writeFile tmpPath (encode (99 :: Int))
        let result = loadConfigOrBuiltin tmpPath (42 :: Int)
        assertEqual "parsed value" 99 result

  , TestLabel "loadConfigOrBuiltin malformed JSON → builtin" $
      TestCase $ do
        let tmpPath = "/tmp/test_config_externalize_broken.json"
        writeFile tmpPath "not json"
        let result = loadConfigOrBuiltin tmpPath (42 :: Int)
        assertEqual "builtin fallback for malformed" 42 result
  ]

-- ---------------------------------------------------------------------------
-- EC-2..5: Externalization smoke tests
-- ---------------------------------------------------------------------------

-- | Verify that the JSON-generated defaults are byte-identical to the
-- builtin values when the config file is missing.
externalizeAbsentTest :: (Eq a, Show a, ToJSON a, FromJSON a) => String -> a -> FilePath -> Test
externalizeAbsentTest name builtin path =
  TestLabel ("externalize absent " <> name) $
    TestCase $ do
      removeFile path `catch` (\(_ :: SomeException) -> pure ())
      let result = loadConfigOrBuiltin path builtin
      assertEqual (name <> " absent mismatch") builtin result

-- | Verify that a config file with a modified value overrides the builtin.
externalizeModifiedTest :: (Eq a, Show a, ToJSON a, FromJSON a) => String -> a -> FilePath -> a -> Test
externalizeModifiedTest name builtin path modified =
  TestLabel ("externalize modified " <> name) $
    TestCase $ do
      BSL.writeFile path (encode modified)
      let result = loadConfigOrBuiltin path builtin
      assertEqual (name <> " modified mismatch") modified result

configExternalizeTests :: [Test]
configExternalizeTests =
  -- EC-0 round-trip
  [ roundTripTest "SalienceWeights" defaultSalienceWeights
  , roundTripTest "FieldHeuristics" defaultFieldHeuristics
  , roundTripTest "ConatusWeights" defaultConatusWeights
  , roundTripTest "FamilyTargets" familyTargets
  ]
  -- EC-1 loader
  ++ loaderTests
  -- EC-2..5 per-target smoke (JSON-absent + JSON-present)
  -- Each pair uses a UNIQUE path to avoid GHC CSE sharing.
  ++
  [ externalizeAbsentTest "salience-absent" defaultSalienceWeights
      "/tmp/test_config_externalize_salience_absent.json"
  , externalizeModifiedTest "salience-modified" defaultSalienceWeights
      "/tmp/test_config_externalize_salience_modified.json"
      (defaultSalienceWeights { weightResonance = 2.0 })
  , externalizeAbsentTest "field-absent" defaultFieldHeuristics
      "/tmp/test_config_externalize_field_absent.json"
  , externalizeModifiedTest "field-modified" defaultFieldHeuristics
      "/tmp/test_config_externalize_field_modified.json"
      (defaultFieldHeuristics { fhNarrativeWindowSize = 10 })
  , externalizeAbsentTest "conatus-absent" defaultConatusWeights
      "/tmp/test_config_externalize_conatus_absent.json"
  , externalizeModifiedTest "conatus-modified" defaultConatusWeights
      "/tmp/test_config_externalize_conatus_modified.json"
      (defaultConatusWeights { cwMorphology = 2.0 })
  , externalizeAbsentTest "family-absent" familyTargets
      "/tmp/test_config_externalize_family_absent.json"
  , externalizeModifiedTest "family-modified" familyTargets
      "/tmp/test_config_externalize_family_modified.json"
      (take 1 familyTargets)
  ]
