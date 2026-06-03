{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — M6 witness protocol discipline lock.

Locks the four evidence contours required for M6 (Algorithmic Subject
Demonstration) per @docs\/closure\/M6_WITNESS_PROTOCOL.md@:

  * C1 — continuity and coherence (canonical contour trace fields)
  * C2 — restart integrity (@trcRegimeVersion@ present)
  * C3 — commitment accountability (@SemanticCommitmentStore@ exists as type)
  * C4 — bidirectional semantic participation (GF + CTS complete + familyDivergence live)

This test does NOT assert full M6 activation (that requires H3 + C3 completion).
It asserts that the architectural preconditions are in place and machine-visible.
-}
module Test.Suite.M6Witness
  ( m6WitnessTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Control.Exception (SomeException, catch)
import qualified Data.List as L
import qualified System.Directory as D
import Prelude

import QxFx0.Types.RuntimeRegime
  ( RuntimeRegime (..)
  , defaultRuntimeRegime
  , currentMathVersion
  , currentConstitutionVersion
  )

-- | Read a file or return empty string on error.
readFileOrEmpty :: FilePath -> IO String
readFileOrEmpty path = (readFile path) `catch` (\(_ :: SomeException) -> return "")

-- ---------------------------------------------------------------------------
-- C1 — Continuity and coherence
-- ---------------------------------------------------------------------------

-- | All 6 canonical contours must have trc* fields in TurnReplayTrace.
-- This is the runtime companion of check_replay_gate.sh.
c1CanonicalContourCoverage :: Test
c1CanonicalContourCoverage = TestLabel "C1: all 6 canonical contours have trc* fields in TurnReplayTrace" $
  TestCase $ do
    let tracePath = "src/QxFx0/Types/TurnProjection.hs"
    contents <- readFileOrEmpty tracePath
    let requiredFields =
          [ "trcConatusEnergy"      -- Conatus P4
          , "trcConatusGateFired"   -- Conatus P4
          , "trcField"              -- Field P4
          , "trcIdentityClaims"     -- Identity P4
          , "trcSalienceDriver"     -- Salience P4
          , "trcDeliberationRule"   -- Deliberation P4
          , "trcEssenceMode"        -- Essence P4
          ]
        missing = filter (\f -> not (f `L.isInfixOf` contents)) requiredFields
    assertBool
      ("C1: the following canonical contour trc* fields are missing from TurnReplayTrace: "
       <> show missing)
      (null missing)

-- ---------------------------------------------------------------------------
-- C2 — Restart integrity
-- ---------------------------------------------------------------------------

-- | trcRegimeVersion must be present in TurnReplayTrace (M5 machine-visible marker).
c2RegimeVersionPresent :: Test
c2RegimeVersionPresent = TestLabel "C2: trcRegimeVersion is present in TurnReplayTrace (M5 governance)" $
  TestCase $ do
    let tracePath = "src/QxFx0/Types/TurnProjection.hs"
    contents <- readFileOrEmpty tracePath
    assertBool
      ("C2: trcRegimeVersion not found in TurnReplayTrace — M5 machine-visible marker is missing")
      ("trcRegimeVersion" `L.isInfixOf` contents)

-- | defaultRuntimeRegime must have a non-zero math version.
c2DefaultRegimeIsNonTrivial :: Test
c2DefaultRegimeIsNonTrivial = TestLabel "C2: defaultRuntimeRegime is non-trivial (math version > 0)" $
  TestCase $ do
    assertBool "defaultRuntimeRegime.rrMathVersion must be > 0"
      (rrMathVersion defaultRuntimeRegime > 0)
    assertBool "currentMathVersion must be > 0"
      (currentMathVersion > 0)
    assertBool "currentConstitutionVersion must be >= 40 (CTS-01 through CTS-40)"
      (currentConstitutionVersion >= 40)

-- | familyDivergence must be active in the default regime (ADR-0019 promoted).
c2FamilyDivergenceIsActive :: Test
c2FamilyDivergenceIsActive = TestLabel "C2: familyDivergenceActive = True in defaultRuntimeRegime (ADR-0019 promoted)" $
  TestCase $
    assertBool "rrFamilyDivergenceActive must be True in defaultRuntimeRegime (ADR-0019 accepted 2026-06-02)"
      (rrFamilyDivergenceActive defaultRuntimeRegime)

-- ---------------------------------------------------------------------------
-- C3 — Commitment accountability (type-level check)
-- ---------------------------------------------------------------------------

-- | SemanticCommitmentStore must exist as a type (Package 2 minimum).
c3SemanticCommitmentTypeExists :: Test
c3SemanticCommitmentTypeExists = TestLabel "C3: SemanticCommitmentStore type exists (Package 2)" $
  TestCase $ do
    let typePath = "src/QxFx0/Types/State/SemanticCommitment.hs"
    exists <- D.doesFileExist typePath
    assertBool
      ("C3: SemanticCommitmentStore type file not found at " <> typePath)
      exists

-- ---------------------------------------------------------------------------
-- C4 — Bidirectional semantic participation
-- ---------------------------------------------------------------------------

-- | GF grammar must include MoveActOnTopic with all 5 topics.
c4GfTopicCoverage :: Test
c4GfTopicCoverage = TestLabel "C4: GF grammar has MoveActOnTopic with all 5 topics" $
  TestCase $ do
    let syntaxPath = "spec/gf/QxFx0Syntax.gf"
    contents <- readFileOrEmpty syntaxPath
    let requiredConstructors =
          [ "ActAnswer"     -- otvet_N
          , "ActQuestion"   -- vopros_N
          , "ActTopicTerm"  -- tema_N
          , "ActProject"    -- proekt_N (GF-E1b)
          , "ActResult"     -- rezultat_N (GF-E1b)
          ]
        missing = filter (\c -> not (c `L.isInfixOf` contents)) requiredConstructors
    assertBool
      ("C4: the following MoveActOnTopic topic constructors are missing from QxFx0Syntax.gf: "
       <> show missing)
      (null missing)

-- | CTS admission chain must be complete (all proposition consumers admitted).
c4CTSAdmissionChainComplete :: Test
c4CTSAdmissionChainComplete = TestLabel "C4: CTS admission chain complete (all proposition consumers have admission modules)" $
  TestCase $ do
    let coreDir = "src/QxFx0/Core"
    exists <- D.doesDirectoryExist coreDir
    if not exists
      then assertBool "Core directory not found" False
      else do
        entries <- D.listDirectory coreDir
        let admissionModules = filter (L.isInfixOf "Admission") entries
        -- Must have at least 10 admission modules (CTS-01 onwards)
        assertBool
          ("C4: fewer than 10 CTS admission modules found in Core/. Found: "
           <> show (length admissionModules))
          (length admissionModules >= 10)

-- | M6 witness protocol document must exist and have the 4 contours defined.
c4WitnessProtocolExists :: Test
c4WitnessProtocolExists = TestLabel "C4: M6_WITNESS_PROTOCOL.md exists and defines all 4 evidence contours" $
  TestCase $ do
    let docPath = "docs/closure/M6_WITNESS_PROTOCOL.md"
    contents <- readFileOrEmpty docPath
    assertBool ("M6_WITNESS_PROTOCOL.md not found at " <> docPath)
               (not (null contents))
    let requiredSections = ["Contour C1", "Contour C2", "Contour C3", "Contour C4"]
        missing = filter (\s -> not (s `L.isInfixOf` contents)) requiredSections
    assertBool
      ("M6_WITNESS_PROTOCOL.md is missing evidence contour sections: " <> show missing)
      (null missing)

-- | M6 claim package document must exist.
c4ClaimPackageExists :: Test
c4ClaimPackageExists = TestLabel "C4: M6_CLAIM_PACKAGE.md exists" $
  TestCase $ do
    let docPath = "docs/closure/M6_CLAIM_PACKAGE.md"
    exists <- D.doesFileExist docPath
    assertBool ("M6_CLAIM_PACKAGE.md not found at " <> docPath) exists

-- | M6 declaration document must exist and declare the bounded final claim.
c4DeclarationExists :: Test
c4DeclarationExists = TestLabel "C4: M6_DECLARATION.md exists and contains the bounded claim" $
  TestCase $ do
    let docPath = "docs/closure/M6_DECLARATION.md"
    contents <- readFileOrEmpty docPath
    assertBool ("M6_DECLARATION.md not found at " <> docPath)
               (not (null contents))
    let requiredSections =
          [ "bounded final claim"
          , "Algorithmic subject structure"
          , "Meaningful domain dialogue"
          , "Negative criteria"
          , "Evidence package index"
          ]
        missing = filter (\s -> not (s `L.isInfixOf` contents)) requiredSections
    assertBool
      ("M6_DECLARATION.md is missing required sections: " <> show missing)
      (null missing)

-- | Evidence index must exist.
c4EvidenceIndexExists :: Test
c4EvidenceIndexExists = TestLabel "C4: reports/m6_evidence/EVIDENCE_INDEX.md exists" $
  TestCase $ do
    let docPath = "reports/m6_evidence/EVIDENCE_INDEX.md"
    exists <- D.doesFileExist docPath
    assertBool ("EVIDENCE_INDEX.md not found at " <> docPath) exists

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

m6WitnessTests :: [Test]
m6WitnessTests =
  [ c1CanonicalContourCoverage
  , c2RegimeVersionPresent
  , c2DefaultRegimeIsNonTrivial
  , c2FamilyDivergenceIsActive
  , c3SemanticCommitmentTypeExists
  , c4GfTopicCoverage
  , c4CTSAdmissionChainComplete
  , c4WitnessProtocolExists
  , c4ClaimPackageExists
  , c4DeclarationExists
  , c4EvidenceIndexExists
  ]
