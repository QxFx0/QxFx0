{-# LANGUAGE OverloadedStrings #-}

{-|
Description : canonical — evidence admissibility classification pins (SLICE-012).

Pins the table in @QxFx0.Core.EvidenceAdmissibility@ and the one place that
used to lie about it: the prepare-stage fallback for a nix guard that was
never consulted (@QxFx0.Core.EvidenceAdmissibility.missingGuardRequestStatus@,
used by @QxFx0.Core.TurnPipeline.Prepare.Resolve@).

Policy under test (module docstring of @EvidenceAdmissibility@): an
@Unavailable@ guard is allowed runtime degradation but forbidden proof
substrate — degraded evidence in normal mode, inadmissible (fail-closed) in
governed-evidence mode.

Pre-registration: @docs\/closure\/PREPARE_FALLBACK_PREREG_2026-11-12.md@.
-}
module Test.Suite.EvidenceAdmissibility
  ( evidenceAdmissibilityTests
  ) where

import Test.HUnit (Test (..), assertEqual)

import QxFx0.Core.EvidenceAdmissibility
  ( classifyEvidence
  , missingGuardRequestStatus
  )
import QxFx0.Types.Domain (NixGuardStatus(..))
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))

evidenceAdmissibilityTests :: [Test]
evidenceAdmissibilityTests =
  [ TestLabel "Evidence allowed guard is governed" testAllowedIsGoverned
  , TestLabel "Evidence blocked guard is governed" testBlockedIsGoverned
  , TestLabel "Evidence unavailable guard degrades in normal mode" testUnavailableDegrades
  , TestLabel "Evidence unavailable guard is inadmissible in governed mode" testUnavailableInadmissibleInGovernedMode
  , TestLabel "Evidence missing nix request does not claim governance" testMissingNixRequestIsNotGoverned
  , TestLabel "Evidence missing nix request keeps its reason string" testMissingNixRequestReason
  ]

-- | A guard that was present and allowed the concept.
testAllowedIsGoverned :: Test
testAllowedIsGoverned = TestCase $
  assertEqual "Allowed must classify as governed evidence"
    EvidenceGoverned (classifyEvidence False Allowed)

-- | A guard that was present and refused the concept: the refusal itself is a
-- governed decision, so this must stay 'EvidenceGoverned' in both modes.
testBlockedIsGoverned :: Test
testBlockedIsGoverned = TestCase $ do
  assertEqual "Blocked must classify as governed evidence (normal mode)"
    EvidenceGoverned (classifyEvidence False (Blocked "concept_not_allowed"))
  assertEqual "Blocked must classify as governed evidence (governed mode)"
    EvidenceGoverned (classifyEvidence True (Blocked "concept_not_allowed"))

-- | A guard that could not be consulted: runtime continues, evidence is marked.
testUnavailableDegrades :: Test
testUnavailableDegrades = TestCase $
  assertEqual "Unavailable must degrade, not govern, in normal mode"
    EvidenceDegradedGuardUnavailable
    (classifyEvidence False (Unavailable "nix_store_missing"))

-- | Same guard under governed-evidence mode: the caller fail-closes.
testUnavailableInadmissibleInGovernedMode :: Test
testUnavailableInadmissibleInGovernedMode = TestCase $
  assertEqual "Unavailable must be inadmissible in governed-evidence mode"
    EvidenceInadmissible
    (classifyEvidence True (Unavailable "nix_store_missing"))

-- | The prepare-stage fallback: nothing consulted the guard, so the turn must
-- not be stamped as governed evidence. This is the pin that fails if the
-- fallback goes back to @Blocked "nix_guard_missing_request"@.
testMissingNixRequestIsNotGoverned :: Test
testMissingNixRequestIsNotGoverned = TestCase $ do
  assertEqual "a missing nix request must degrade in normal mode"
    EvidenceDegradedGuardUnavailable (classifyEvidence False missingGuardRequestStatus)
  assertEqual "a missing nix request must be inadmissible in governed mode"
    EvidenceInadmissible (classifyEvidence True missingGuardRequestStatus)

-- | The reason string is greppable in logs and traces; keep it stable. It is
-- also the marker that separates "never consulted" from a real refusal.
testMissingNixRequestReason :: Test
testMissingNixRequestReason = TestCase $ do
  assertEqual "the fallback reason must stay greppable"
    (Unavailable "nix_guard_missing_request") missingGuardRequestStatus
  assertEqual "the fallback must not impersonate a refusal"
    False (case missingGuardRequestStatus of Blocked _ -> True; _ -> False)
