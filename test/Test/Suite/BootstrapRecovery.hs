{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.BootstrapRecovery
Description : Unit tests for bootstrap blanket recovery helpers.

Tests exercise the pure fallback morphology and the IO recovery
function over constructed 'SystemState' values that violate the
initial self-blanket. No database or filesystem access is required.
-}
module Test.Suite.BootstrapRecovery
  ( bootstrapRecoveryTests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Test.HUnit (Test (..), (@?=), assertBool)
import Control.Exception (IOException, try)
import Control.Monad (forM, when)
import System.Directory (doesDirectoryExist, getSymbolicLinkTarget, listDirectory)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

import QxFx0.Runtime.Session
  ( generateFallbackSessionId
  , minimalMorphologyFallback
  , recoverBootstrapBlanket
  )
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Types (BlanketViolation (..))
import QxFx0.Types (MorphologyData (..), SystemState (..))
import QxFx0.Types.Domain.Atoms
  ( LexemeCase (..)
  , LexemeForm (..)
  , LexemeNumber (..)
  , SourceTier (..)
  )
import QxFx0.Runtime.StateDefaults (emptySystemState)
import qualified Test.Support.Runtime as Runtime
import Test.Support (withEnvVar, withRuntimeEnv)

-- | A morphology with at least one entry so that the baseline state
-- satisfies the blanket.
nonEmptyMorphology :: MorphologyData
nonEmptyMorphology = MorphologyData
  { mdPrepositional = Map.singleton "о" "о"
  , mdGenitive      = Map.empty
  , mdNominative    = Map.empty
  , mdFormsBySurface = Map.empty
  }

-- | A morphology whose total size is zero.
emptyMorphology :: MorphologyData
emptyMorphology = MorphologyData
  { mdPrepositional = Map.empty
  , mdGenitive      = Map.empty
  , mdNominative    = Map.empty
  , mdFormsBySurface = Map.empty
  }

-- | A valid baseline state with non-empty session id and morphology.
validState :: SystemState
validState = emptySystemState
  { ssSessionId  = "demo"
  , ssMorphology = nonEmptyMorphology
  }

-- | State with an empty session identifier.
emptySessionState :: SystemState
emptySessionState = validState { ssSessionId = "" }

-- | State with an empty morphology.
emptyMorphologyState :: SystemState
emptyMorphologyState = validState { ssMorphology = emptyMorphology }

-- | State where both recoverable violations occur at once.
bothViolationsState :: SystemState
bothViolationsState = emptySystemState
  { ssSessionId  = ""
  , ssMorphology = emptyMorphology
  }

-- | The fallback morphology must have total size > 0.
testFallbackMorphologyNonEmpty :: Test
testFallbackMorphologyNonEmpty = TestCase $ do
  let md = minimalMorphologyFallback
      totalSize = Map.size (mdPrepositional md)
                  + Map.size (mdGenitive md)
                  + Map.size (mdNominative md)
                  + Map.size (mdFormsBySurface md)
  assertBool "fallback morphology total size must be > 0" (totalSize > 0)

-- | Empty session id is repaired to a non-empty fallback id.
testEmptySessionRepaired :: Test
testEmptySessionRepaired = TestCase $ do
  (remaining, repaired, sessionIdOut) <-
    recoverBootstrapBlanket nonEmptyMorphology emptySessionState ""
  assertBool "session id should be repaired to non-empty"
    (not (T.null sessionIdOut))
  assertBool "session id should be reflected in repaired state"
    (ssSessionId repaired == sessionIdOut)
  assertBool "BlanketEmptySession should be removed"
    (BlanketEmptySession `notElem` remaining)

-- | Empty morphology is repaired to the non-empty fallback.
testEmptyMorphologyRepaired :: Test
testEmptyMorphologyRepaired = TestCase $ do
  (remaining, repaired, sessionIdOut) <-
    recoverBootstrapBlanket emptyMorphology emptyMorphologyState "demo"
  assertBool "session id should be unchanged"
    (sessionIdOut == "demo")
  assertBool "morphology should be repaired to non-empty"
    (not (Map.null (mdNominative (ssMorphology repaired))))
  assertBool "BlanketEmptyMorphology should be removed"
    (BlanketEmptyMorphology `notElem` remaining)

-- | Both violations repaired together leave no remaining violations.
testBothRepaired :: Test
testBothRepaired = TestCase $ do
  (remaining, repaired, sessionIdOut) <-
    recoverBootstrapBlanket emptyMorphology bothViolationsState ""
  assertBool "session id should be repaired to non-empty"
    (not (T.null sessionIdOut))
  assertBool "morphology should be repaired to non-empty"
    (not (Map.null (mdNominative (ssMorphology repaired))))
  assertBool "no blanket violations should remain"
    (null remaining)
  assertBool "repaired state must satisfy the initial blanket"
    (null (checkInitialBlanket (computeSelfBlanket repaired)))

-- | The fallback session id follows the documented prefix.
testFallbackSessionIdFormat :: Test
testFallbackSessionIdFormat = TestCase $ do
  sid <- generateFallbackSessionId
  assertBool "fallback session id must start with documented prefix"
    ("bootstrap-recovery-" `T.isPrefixOf` sid)

-- | A valid state requires no repairs and keeps the original session id.
testValidStateUnchanged :: Test
testValidStateUnchanged = TestCase $ do
  (remaining, repaired, sessionIdOut) <-
    recoverBootstrapBlanket nonEmptyMorphology validState "demo"
  remaining @?= []
  sessionIdOut @?= "demo"
  ssSessionId repaired @?= "demo"

-- A session owns a two-connection SQLite pool and an HTTP manager. Repeated
-- restart must release those resources deterministically rather than relying
-- on GC. /proc makes this assertion process-local and race-free on Linux.
testSessionLifecycleDescriptorBound :: Test
testSessionLifecycleDescriptorBound = TestCase $ do
  procAvailable <- doesDirectoryExist "/proc/self/fd"
  when procAvailable $
    withRuntimeEnv "qxfx0_test_session_fd_lifecycle.db" $
      withEnvVar "QXFX0_AUTONOMOUS_LEARNING" (Just "0") $ do
        Runtime.withBootstrappedSession True "fd-lifecycle" (const (pure ()))
        baseline <- descriptorCount
        baselineTargets <- descriptorTargets
        (activeTargets, dbPath) <- Runtime.withBootstrappedSession True "fd-lifecycle" $ \session -> do
          targets <- descriptorTargets
          pure (targets, Runtime.sessDbPath session)
        let ownedTargets = Map.keys (positiveDifference activeTargets baselineTargets)
        assertBool
          ("open session did not expose its owned SQLite descriptors: " <> show ownedTargets)
          (any (dbPath `isPrefixOf`) ownedTargets)
        samples <- forM [1 .. 16 :: Int] $ \_ -> do
          Runtime.withBootstrappedSession True "fd-lifecycle" (const (pure ()))
          descriptorCount
        let peakGrowth = maximum (baseline : samples) - baseline
            finalGrowth = last samples - baseline
        hPutStrLn stderr
          ("[fd-lifecycle] baseline=" <> show baseline
            <> " samples=" <> show samples
            <> " open_session_targets=" <> show ownedTargets)
        assertBool
          ("session lifecycle leaked descriptors: baseline=" <> show baseline
            <> ", samples=" <> show samples)
          (peakGrowth <= 3 && finalGrowth <= 2)
  where
    descriptorCount = length <$> listDirectory "/proc/self/fd"
    descriptorTargets = do
      descriptors <- listDirectory "/proc/self/fd"
      targets <- forM descriptors $ \descriptor -> do
        targetResult <- try (getSymbolicLinkTarget ("/proc/self/fd" </> descriptor))
          :: IO (Either IOException FilePath)
        pure (either (const Nothing) Just targetResult)
      pure (Map.fromListWith (+) [(target, 1 :: Int) | Just target <- targets])
    positiveDifference current previous =
      Map.differenceWith subtractCount current previous
    subtractCount current previous
      | current > previous = Just (current - previous)
      | otherwise = Nothing
    isPrefixOf prefix value = take (length prefix) value == prefix

bootstrapRecoveryTests :: [Test]
bootstrapRecoveryTests =
  [ TestLabel "fallback morphology is non-empty" testFallbackMorphologyNonEmpty
  , TestLabel "empty session id is repaired" testEmptySessionRepaired
  , TestLabel "empty morphology is repaired" testEmptyMorphologyRepaired
  , TestLabel "both violations repaired together" testBothRepaired
  , TestLabel "fallback session id format" testFallbackSessionIdFormat
  , TestLabel "valid state remains unchanged" testValidStateUnchanged
  , TestLabel "session restart keeps descriptor growth bounded" testSessionLifecycleDescriptorBound
  ]
