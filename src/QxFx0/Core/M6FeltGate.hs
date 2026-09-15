{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Core.M6FeltGate
Description : M6-FELT mechanical evidence gate (B3 Gates 1-5, governed).

Implements the /felt-evidence gate/ that M6_DECLARATION.md §6(4) requires
before Essence (or any structural runtime feature) may be counted as
M6-FELT (felt subjecthood) evidence:

> M6-FELT is proven means Gate 5 (precondition) ∧ Gate 1 ∧ Gate 2 ∧
> Gate 3 ∧ Gate 4 all pass under governed-evidence conditions
> (@QXFX0_GOVERNED_EVIDENCE=1@, guard Available, trace
> 'EvidenceGoverned'), mechanically checked, with the public seed
> corpus — conjunction across both layers, not average.

This module is the /mechanical checker/ over a session's replay traces.
It is pure and deterministic: given a list of 'TurnReplayTrace', it
returns a 'M6FeltVerdict' that names every gate that did not pass. The
gate is fail-closed by construction:

* an empty session is 'M6FeltNotProven' with all gates named;
* a session where any turn is not 'EvidenceGoverned' fails the
  governed-evidence precondition (SLICE-012) and therefore the whole
  gate (no averaging, no partial credit);
* a gate that cannot be mechanically established from the trace fields
  is reported as failed — the checker never manufactures evidence.

== Gate semantics (per docs/closure/B3_SEMANTIC_CORE_MVS_GATE.md)

1.  'FeltGateGovernedEvidence' — SLICE-012 precondition: every turn's
    'trcEvidenceAdmissibility' must be 'EvidenceGoverned'.
2.  'FeltGate5NonFallback' — Gate 5 precondition: for every turn the
    response comes from the semantic core path, not the fallback
    template path.  Mechanically: 'trcAuthorityClass' is
    'AuthorityCanonical' or 'AuthorityShim', 'trcFallbackReason' is
    'Nothing', 'trcLinearizationOk' is 'True', and 'trcContentSource'
    is a semantic source (@covered_exact@ / @covered_generic@).
3.  'FeltGate1Definition' — Gate 1: ≥2 substantive non-tautological
    predications.  Mechanically: the session contains at least two
    turns whose 'trcEmittedPredicates' is non-empty and whose rendered
    text ('trcRenderedAfterRebind') is non-empty.
4.  'FeltGate2Distinction' — Gate 2: the system distinguishes related
    concepts.  Mechanically: the session covers at least two distinct
    'trcDialogueFocus' values on semantic (non-fallback) turns.
5.  'FeltGate3Repair' — Gate 3: under challenge, at least one typed
    commitment-store operation fires.  Mechanically: some turn has
    'trcCommitmentEngaged' > 0 and either 'trcCommitmentContradicted'
    or 'trcCommitmentStoreDecision' /= 'CsaAdmitCanonical'.
6.  'FeltGate4Commitment' — Gate 4: session-level accountability:
    ≥10 turns, final 'trcSemanticCommitmentCount' ≥ 1, and the count
    never decreases without a typed retraction turn.

== What this module is not

This is not the B3 data-level substrate check
('Test.Suite.B3MechanicalGateExecution', which verifies the content
layer exists) and it does not run B2 human evaluation.  It is the
/runtime-level/ mechanical gate: it decides whether a specific
replay-visible session constitutes M6-FELT evidence under governed
conditions.
-}
module QxFx0.Core.M6FeltGate
  ( -- * Verdict
    FeltGate (..)
  , M6FeltVerdict (..)
  , M6FeltEvidence (..)
  , emptyFeltEvidence
    -- * The mechanical gate
  , evaluateM6FeltGate
    -- * Per-gate checks (exported for tests)
  , governedEvidenceHolds
  , gate5NonFallbackHolds
  , gate1DefinitionHolds
  , gate2DistinctionHolds
  , gate3RepairHolds
  , gate4CommitmentHolds
  ) where

import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Evidence (EvidenceAdmissibility(..))
import QxFx0.Types.Observability (AuthorityClass(..))
import QxFx0.Types.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import QxFx0.Types.TurnProjection (TurnReplayTrace(..))

-- ---------------------------------------------------------------------------
-- Verdict types
-- ---------------------------------------------------------------------------

-- | The six mechanical gates of the M6-FELT gate.  The first is the
-- SLICE-012 governed-evidence precondition; the remaining five are the
-- B3 gates.  A verdict names every gate that did not pass.
data FeltGate
  = FeltGateGovernedEvidence
  | FeltGate5NonFallback
  | FeltGate1Definition
  | FeltGate2Distinction
  | FeltGate3Repair
  | FeltGate4Commitment
  deriving stock (Eq, Show, Generic)

-- | Summary of a passing session, for the evidence package.
data M6FeltEvidence = M6FeltEvidence
  { feTurnCount            :: !Int
  , feFinalCommitmentCount :: !Int
  , feDistinctFocuses      :: !Int
  , feRepairTurns          :: !Int
  } deriving stock (Eq, Show, Generic)

-- | The verdict is fail-closed: 'M6FeltNotProven' names every gate
-- that failed.  Empty sessions fail all gates.
data M6FeltVerdict
  = M6FeltProven M6FeltEvidence
  | M6FeltNotProven [FeltGate]
  deriving stock (Eq, Show, Generic)

emptyFeltEvidence :: M6FeltEvidence
emptyFeltEvidence = M6FeltEvidence
  { feTurnCount = 0
  , feFinalCommitmentCount = 0
  , feDistinctFocuses = 0
  , feRepairTurns = 0
  }

-- ---------------------------------------------------------------------------
-- The mechanical gate
-- ---------------------------------------------------------------------------

-- | Evaluate the M6-FELT gate over a session's replay traces.
--
-- Conjunction across all six gates, no averaging: the verdict is
-- 'M6FeltProven' only when every gate holds, otherwise
-- 'M6FeltNotProven' lists the failed gates.
evaluateM6FeltGate :: [TurnReplayTrace] -> M6FeltVerdict
evaluateM6FeltGate traces
  | null traces = M6FeltNotProven [FeltGateGovernedEvidence, FeltGate5NonFallback
                                  , FeltGate1Definition, FeltGate2Distinction
                                  , FeltGate3Repair, FeltGate4Commitment]
  | otherwise =
      let failed =
            [ FeltGateGovernedEvidence | not (governedEvidenceHolds traces) ]
            <> [ FeltGate5NonFallback | not (gate5NonFallbackHolds traces) ]
            <> [ FeltGate1Definition | not (gate1DefinitionHolds traces) ]
            <> [ FeltGate2Distinction | not (gate2DistinctionHolds traces) ]
            <> [ FeltGate3Repair | not (gate3RepairHolds traces) ]
            <> [ FeltGate4Commitment | not (gate4CommitmentHolds traces) ]
      in case failed of
           [] -> M6FeltProven (summarize traces)
           _  -> M6FeltNotProven failed

-- ---------------------------------------------------------------------------
-- Per-gate checks
-- ---------------------------------------------------------------------------

-- | SLICE-012 precondition: every turn's evidence is governed.
governedEvidenceHolds :: [TurnReplayTrace] -> Bool
governedEvidenceHolds = all ((== EvidenceGoverned) . trcEvidenceAdmissibility)

-- | Gate 5 (non-fallback): every turn reaches the semantic core path.
-- A turn fails if its authority class is not canonical/shim, if a
-- fallback reason is recorded, if linearization failed, or if the
-- content source is not a semantic source.
gate5NonFallbackHolds :: [TurnReplayTrace] -> Bool
gate5NonFallbackHolds = all turnNonFallback
  where
    turnNonFallback t =
      authorityOk t
        && trcFallbackReason t == Nothing
        && trcLinearizationOk t
        && semanticSource (trcContentSource t)

    authorityOk t = case trcAuthorityClass t of
      Just AuthorityCanonical -> True
      Just AuthorityShim      -> True
      _                       -> False

-- | A semantic content source is one of the semantic-first
-- classifications recorded by the M4 phase-C cutover.
semanticSource :: Maybe Text -> Bool
semanticSource = \case
  Just s | s `elem` ["covered_exact", "covered_generic"] -> True
  _ -> False

-- | Gate 1 (definition): at least two turns emit substantive
-- predications with non-empty rendered text.
gate1DefinitionHolds :: [TurnReplayTrace] -> Bool
gate1DefinitionHolds traces =
  length (filter substantive traces) >= 2
  where
    substantive t =
      not (null (trcEmittedPredicates t))
        && not (T.null (trcRenderedAfterRebind t))

-- | Gate 2 (distinction): the session engages at least two distinct
-- dialogue focuses on semantic turns.
gate2DistinctionHolds :: [TurnReplayTrace] -> Bool
gate2DistinctionHolds traces =
  length (nub [ trcDialogueFocus t
              | t <- traces
              , semanticSource (trcContentSource t) ]) >= 2

-- | Gate 3 (repair): at least one challenge turn fires a typed
-- commitment-store operation (revise / retract / contradict /
-- quarantine).
gate3RepairHolds :: [TurnReplayTrace] -> Bool
gate3RepairHolds traces =
  any repairTurn traces
  where
    repairTurn t =
      trcCommitmentEngaged t > 0
        && ( trcCommitmentContradicted t
             || trcCommitmentStoreDecision t /= CsaAdmitCanonical )

-- | Gate 4 (commitment accountability): a ≥10-turn session where the
-- final commitment count is ≥1 and the count never decreases without
-- a typed retraction turn (the turn immediately preceding the drop
-- must have fired a non-admit store decision).
gate4CommitmentHolds :: [TurnReplayTrace] -> Bool
gate4CommitmentHolds traces
  | length traces < 10 = False
  | otherwise =
      let counts = map trcSemanticCommitmentCount traces
      in case reverse counts of
           (lastCount:_) ->
             lastCount >= 1 && monotoneOrRetracted counts traces
           [] -> False
  where
    monotoneOrRetracted (c0 : c1 : rest) (t0 : t1 : tRest)
      | c1 < c0 = trcCommitmentStoreDecision t1 /= CsaAdmitCanonical
                  && monotoneOrRetracted (c1 : rest) (t1 : tRest)
      | otherwise = monotoneOrRetracted (c1 : rest) (t1 : tRest)
    monotoneOrRetracted _ _ = True

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

-- | Structural summary of a passing session.
summarize :: [TurnReplayTrace] -> M6FeltEvidence
summarize traces = M6FeltEvidence
  { feTurnCount = length traces
  , feFinalCommitmentCount =
      case reverse traces of
        (t:_) -> trcSemanticCommitmentCount t
        []    -> 0
  , feDistinctFocuses = length (nub (map trcDialogueFocus traces))
  , feRepairTurns = length (filter repairTurn traces)
  }
  where
    repairTurn t =
      trcCommitmentEngaged t > 0
        && ( trcCommitmentContradicted t
             || trcCommitmentStoreDecision t /= CsaAdmitCanonical )
