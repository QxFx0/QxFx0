{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.TuningRuntimeIntegration
Description : Phase II corpus tuning output reaches runtime defaults.

Verifies that when 'resources/config/tuned_salience_weights.json' and
'resources/config/tuned_field_heuristics.json' exist, the runtime loaders
used by 'QxFx0.Self.Salience.defaultSalienceWeights' and
'QxFx0.Self.Field.defaultFieldHeuristics' pick up the tuned values instead
of the builtin defaults.

The test is hermetic: it writes deliberately distinct JSON payloads to the
runtime tuned paths, forces the top-level default values, asserts the tuned
payloads are loaded, and removes the files in a 'bracket' cleanup.
-}
module Test.Suite.TuningRuntimeIntegration
  ( tuningRuntimeIntegrationTests
  ) where

import Control.Exception (bracket_)
import Control.Monad (when)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as BL
import System.Directory (doesFileExist)
import Test.HUnit

import QxFx0.Self.Field
  ( FieldHeuristics(..)
  , defaultFieldHeuristics
  )
import QxFx0.Self.Salience
  ( SalienceWeights(..)
  , defaultSalienceWeights
  )

import Test.Support (removeIfExists)

-- ---------------------------------------------------------------------------
-- Paths used by the runtime loaders.
-- ---------------------------------------------------------------------------

tunedSaliencePath :: FilePath
tunedSaliencePath = "resources/config/tuned_salience_weights.json"

tunedFieldPath :: FilePath
tunedFieldPath = "resources/config/tuned_field_heuristics.json"

-- ---------------------------------------------------------------------------
-- Reference builtin values (mirrors the private builtins in the production
-- modules).  We keep a local copy so the test can prove the loaded value is
-- *not* the builtin fallback.
-- ---------------------------------------------------------------------------

builtinSalienceWeights :: SalienceWeights
builtinSalienceWeights = SalienceWeights
  { weightResonance       = 1.0
  , weightAtmosphere      = 0.5
  , weightConsolidation   = 0.75
  , weightCounterfactual  = 0.75
  , weightFieldConfidence = 0.5
  , weightContentSaliency = 0.6
  , conatusGateThreshold  = 0.0
  , verdictThreshold      = 0.05
  , sigmoidTemperature    = 1.0
  }

builtinFieldHeuristics :: FieldHeuristics
builtinFieldHeuristics = FieldHeuristics
  { fhNarrativeWindowSize     = 5
  , fhDefaultNarrativeRate    = 0.2
  , fhTopicStabilityBoost     = 0.5
  , fhEntropyEpsilon          = 1e-9
  , fhHolisticStreakBoostRate = 0.05
  , fhHolisticStreakBoostCap  = 0.2
  , fhLegitimacyMidpoint      = 0.5
  , fhLegitimacyBonusScale    = 0.4
  , fhOntologyDepthBoost      = 0.0
  }

-- ---------------------------------------------------------------------------
-- Synthetic tuned payloads.  Every field is deliberately shifted from the
-- builtin so the assertion that tuning "wins" is unambiguous.
-- ---------------------------------------------------------------------------

tunedSalienceWeights :: SalienceWeights
tunedSalienceWeights = SalienceWeights
  { weightResonance       = 1.25
  , weightAtmosphere      = 0.55
  , weightConsolidation   = 0.8
  , weightCounterfactual  = 0.8
  , weightFieldConfidence = 0.55
  , weightContentSaliency = 0.65
  , conatusGateThreshold  = 0.05
  , verdictThreshold      = 0.06
  , sigmoidTemperature    = 1.1
  }

tunedFieldHeuristics :: FieldHeuristics
tunedFieldHeuristics = FieldHeuristics
  { fhNarrativeWindowSize     = 6
  , fhDefaultNarrativeRate    = 0.25
  , fhTopicStabilityBoost     = 0.55
  , fhEntropyEpsilon          = 1.1e-9
  , fhHolisticStreakBoostRate = 0.06
  , fhHolisticStreakBoostCap  = 0.25
  , fhLegitimacyMidpoint      = 0.55
  , fhLegitimacyBonusScale    = 0.45
  , fhOntologyDepthBoost      = 0.1
  }

-- ---------------------------------------------------------------------------
-- Fixture: write tuned files, run an action, then remove them.
--
-- Note: because 'defaultSalienceWeights' and 'defaultFieldHeuristics' are
-- top-level CAFs backed by 'unsafePerformIO', this fixture must run /before/
-- any other test in the suite forces those values.  'TestMainFast' therefore
-- lists 'tuningRuntimeIntegrationTests' first.
-- ---------------------------------------------------------------------------

withTunedFiles :: IO a -> IO a
withTunedFiles action = bracket_
  (do
    BL.writeFile tunedSaliencePath (encode tunedSalienceWeights)
    BL.writeFile tunedFieldPath    (encode tunedFieldHeuristics))
  (do
    removeIfExists tunedSaliencePath
    removeIfExists tunedFieldPath)
  action

-- ---------------------------------------------------------------------------
-- Test cases
-- ---------------------------------------------------------------------------

testTunedSalienceAffectsRuntime :: Test
testTunedSalienceAffectsRuntime = TestCase $ withTunedFiles $ do
  salienceExists <- doesFileExist tunedSaliencePath
  assertBool "tuned salience file must exist during test" salienceExists
  let loaded = defaultSalienceWeights
  assertEqual "tuned salience weights must be loaded" tunedSalienceWeights loaded
  assertBool "loaded salience weights must differ from builtin"
             (loaded /= builtinSalienceWeights)

testTunedFieldAffectsRuntime :: Test
testTunedFieldAffectsRuntime = TestCase $ withTunedFiles $ do
  fieldExists <- doesFileExist tunedFieldPath
  assertBool "tuned field file must exist during test" fieldExists
  let loaded = defaultFieldHeuristics
  assertEqual "tuned field heuristics must be loaded" tunedFieldHeuristics loaded
  assertBool "loaded field heuristics must differ from builtin"
             (loaded /= builtinFieldHeuristics)

-- | Sanity check that the cleanup really removes the files.  This keeps the
-- fixture honest if a previous test left them behind.
testCleanupRemovesFiles :: Test
testCleanupRemovesFiles = TestCase $ do
  beforeSalience <- doesFileExist tunedSaliencePath
  beforeField    <- doesFileExist tunedFieldPath
  when (beforeSalience || beforeField) $
    assertFailure "tuned files must not be present before cleanup test"
  withTunedFiles $ do
    duringSalience <- doesFileExist tunedSaliencePath
    duringField    <- doesFileExist tunedFieldPath
    assertBool "tuned files must exist during bracket" (duringSalience && duringField)
  afterSalience <- doesFileExist tunedSaliencePath
  afterField    <- doesFileExist tunedFieldPath
  assertBool "tuned salience file must be removed after bracket" (not afterSalience)
  assertBool "tuned field file must be removed after bracket"    (not afterField)

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

tuningRuntimeIntegrationTests :: [Test]
tuningRuntimeIntegrationTests =
  [ TestLabel "tuned salience weights affect runtime default" testTunedSalienceAffectsRuntime
  , TestLabel "tuned field heuristics affect runtime default" testTunedFieldAffectsRuntime
  , TestLabel "tuned file cleanup is hermetic"                testCleanupRemovesFiles
  ]
