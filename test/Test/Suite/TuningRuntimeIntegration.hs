{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.TuningRuntimeIntegration
Description : Phase II corpus tuning output reaches explicit bootstrap state.

Verifies that explicit runtime loading and injection carry tuned values into
session state without ambient Self-layer IO.

The test is hermetic: it writes deliberately distinct JSON payloads to the
runtime tuned paths, forces the top-level default values, asserts the tuned
payloads are loaded, and removes the files in a 'bracket' cleanup.
-}
module Test.Suite.TuningRuntimeIntegration
  ( tuningRuntimeIntegrationTests
  ) where

import Control.Exception (bracket_)
import Control.Monad (when)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Aeson.KeyMap as KeyMap
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , withCurrentDirectory
  )
import System.FilePath ((</>))
import Test.HUnit

import QxFx0.Self.Field
  ( FieldHeuristics(..)
  , defaultFieldHeuristics
  )
import QxFx0.Self.Salience
  ( SalienceWeights(..)
  , defaultSalienceWeights
  )
import QxFx0.Self.Conatus (ConatusWeights(..), defaultConatusWeights)
import QxFx0.Self.FamilyTargets (FamilyTarget, familyTargets)
import QxFx0.Runtime.Session.SelfConfig
  ( SelfBootstrapConfig(..)
  , applySelfBootstrapConfig
  , bootstrapSelfState
  , loadSelfBootstrapConfig
  , loadTunedOrDefaultIO
  )
import QxFx0.Runtime.StateDefaults (emptySelfState)
import QxFx0.Types.State.SelfState
  ( selfConatusWeights
  , selfFamilyTargets
  , selfFieldHeuristics
  , selfSalienceWeights
  )

import Test.Support
  ( freshTestPath
  , removeDirIfExists
  , removeIfExists
  , withEnvVar
  )

-- ---------------------------------------------------------------------------
-- Paths used by the runtime loaders.
-- ---------------------------------------------------------------------------

tunedSaliencePath :: FilePath
tunedSaliencePath = "/tmp/qxfx0_test_tuned_salience_weights.json"

tunedFieldPath :: FilePath
tunedFieldPath = "/tmp/qxfx0_test_tuned_field_heuristics.json"

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
-- ---------------------------------------------------------------------------

withTunedFiles :: IO a -> IO a
withTunedFiles action = bracket_
  (do
    BL.writeFile tunedSaliencePath (Aeson.encode tunedSalienceWeights)
    BL.writeFile tunedFieldPath    (Aeson.encode tunedFieldHeuristics))
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
  loaded <- loadTunedOrDefaultIO tunedSaliencePath
    "resources/config/salience_weights.json" defaultSalienceWeights
  assertEqual "tuned salience weights must be loaded" tunedSalienceWeights loaded
  assertBool "loaded salience weights must differ from builtin"
             (loaded /= builtinSalienceWeights)

testTunedFieldAffectsRuntime :: Test
testTunedFieldAffectsRuntime = TestCase $ withTunedFiles $ do
  fieldExists <- doesFileExist tunedFieldPath
  assertBool "tuned field file must exist during test" fieldExists
  loaded <- loadTunedOrDefaultIO tunedFieldPath
    "resources/config/field_heuristics.json" defaultFieldHeuristics
  assertEqual "tuned field heuristics must be loaded" tunedFieldHeuristics loaded
  assertBool "loaded field heuristics must differ from builtin"
             (loaded /= builtinFieldHeuristics)

testLoadedTunablesInjectIntoState :: Test
testLoadedTunablesInjectIntoState = TestCase $ do
  let tunedConatus = defaultConatusWeights { cwMorphology = 1.5 }
      tunedTargets :: [FamilyTarget]
      tunedTargets = take 3 familyTargets
      config = SelfBootstrapConfig
        { sbcSalienceWeights = tunedSalienceWeights
        , sbcFieldHeuristics = tunedFieldHeuristics
        , sbcConatusWeights = tunedConatus
        , sbcFamilyTargets = tunedTargets
        }
      injected = applySelfBootstrapConfig config emptySelfState
  assertEqual "salience injected" tunedSalienceWeights (selfSalienceWeights injected)
  assertEqual "field injected" tunedFieldHeuristics (selfFieldHeuristics injected)
  assertEqual "conatus injected" tunedConatus (selfConatusWeights injected)
  assertEqual "family targets injected" tunedTargets (selfFamilyTargets injected)

testInstalledDataBootstrapLoad :: Test
testInstalledDataBootstrapLoad = TestCase $ do
  dataRoot <- freshTestPath "qxfx0-self-config-data"
  isolatedCwd <- freshTestPath "qxfx0-self-config-cwd"
  let configDir = dataRoot </> "resources" </> "config"
      tunedConatus = defaultConatusWeights { cwMorphology = 1.75 }
      tunedTargets = take 4 familyTargets
      cleanup = do
        removeDirIfExists isolatedCwd
        removeDirIfExists dataRoot
  bracket_
    (do
      createDirectoryIfMissing True configDir
      createDirectoryIfMissing True isolatedCwd
      BL.writeFile (configDir </> "tuned_salience_weights.json")
        (Aeson.encode tunedSalienceWeights)
      BL.writeFile (configDir </> "tuned_field_heuristics.json") "not json"
      BL.writeFile (configDir </> "field_heuristics.json")
        (Aeson.encode tunedFieldHeuristics)
      BL.writeFile (configDir </> "conatus_weights.json")
        (Aeson.encode tunedConatus)
      BL.writeFile (configDir </> "family_targets.json")
        (Aeson.encode tunedTargets))
    cleanup
    (withEnvVar "qxfx0_datadir" (Just dataRoot) $
      withCurrentDirectory isolatedCwd $ do
        loaded <- loadSelfBootstrapConfig
        assertEqual "installed tuned salience loaded"
          tunedSalienceWeights (sbcSalienceWeights loaded)
        assertEqual "malformed installed tuned field falls back to installed base"
          tunedFieldHeuristics (sbcFieldHeuristics loaded)
        assertEqual "installed conatus loaded"
          tunedConatus (sbcConatusWeights loaded)
        assertEqual "installed family targets loaded"
          tunedTargets (sbcFamilyTargets loaded))

testFreshAndRestoredSelfStateSemantics :: Test
testFreshAndRestoredSelfStateSemantics = TestCase $ do
  let loadedConatus = defaultConatusWeights { cwMorphology = 1.5 }
      persistedConatus = defaultConatusWeights { cwMorphology = 2.5 }
      config = SelfBootstrapConfig
        { sbcSalienceWeights = tunedSalienceWeights
        , sbcFieldHeuristics = tunedFieldHeuristics
        , sbcConatusWeights = loadedConatus
        , sbcFamilyTargets = take 3 familyTargets
        }
      persisted = emptySelfState
        { selfConatusWeights = persistedConatus
        , selfFamilyTargets = take 2 familyTargets
        }
      fresh = bootstrapSelfState config Nothing
      restored = bootstrapSelfState config (Just persisted)
  assertEqual "fresh state receives explicit bootstrap configuration"
    (applySelfBootstrapConfig config emptySelfState) fresh
  assertEqual "restored state preserves persisted governing configuration"
    persisted restored

testSelfStateJsonCompatibility :: Test
testSelfStateJsonCompatibility = TestCase $ do
  let custom = emptySelfState
        { selfConatusWeights = defaultConatusWeights { cwMorphology = 1.5 }
        , selfFamilyTargets = take 3 familyTargets
        }
  case Aeson.eitherDecode (Aeson.encode custom) of
    Left err -> assertFailure ("new SelfState JSON failed to decode: " <> err)
    Right decoded -> assertEqual "new SelfState fields round-trip" custom decoded
  let legacyValue = case Aeson.toJSON custom of
        Aeson.Object fields -> Aeson.Object
          (KeyMap.delete "selfFamilyTargets" (KeyMap.delete "selfConatusWeights" fields))
        other -> other
  case Aeson.fromJSON legacyValue of
    Aeson.Error err -> assertFailure ("legacy SelfState JSON failed to decode: " <> err)
    Aeson.Success decoded -> do
      assertEqual "legacy JSON defaults conatus" defaultConatusWeights
        (selfConatusWeights decoded)
      assertEqual "legacy JSON defaults family targets" familyTargets
        (selfFamilyTargets decoded)

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
  , TestLabel "loaded tunables inject into session state" testLoadedTunablesInjectIntoState
  , TestLabel "installed data files feed explicit bootstrap" testInstalledDataBootstrapLoad
  , TestLabel "fresh injects while restored preserves Self config" testFreshAndRestoredSelfStateSemantics
  , TestLabel "SelfState JSON remains backward compatible" testSelfStateJsonCompatibility
  , TestLabel "tuned file cleanup is hermetic"                testCleanupRemovesFiles
  ]
