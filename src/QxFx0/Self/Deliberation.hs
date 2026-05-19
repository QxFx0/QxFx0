{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Deliberation
Description : Phase-8 deliberation framework — symbiotic reconciliation
              of two hemispheric proposals into one outgoing 'Plan'.

== What this module is

A pure, leaf-level realisation of the deliberation contract pinned
by ADR-0011 (forthcoming). It introduces a single composite
'Plan' record that carries every output decision the dual-mode
runtime currently makes (family / render-style / recovery cause /
narrative tone) plus a self-reported confidence, and a single
morphism

@
'reconcile' :: 'Salience' -> 'HolisticProposal' -> 'FormalProposal' -> 'Field' -> 'Deliberation'
@

that takes one proposal from each hemisphere (a 'Holistic' 'Plan'
on the right, a @'Field' -> 'Plan'@ strategy on the left, both
typed through the existing 'QxFx0.Self.Adjunction.Adjunction'
spine) and produces a reconciled 'Plan' together with a structured
'DeliberationTrace' that records /both/ proposals and the
reconciliation rule that was applied.

This replaces the previous \"priority switching\" pattern (where
the salience verdict picked one of two values to forward) with a
\"deliberation\" pattern (where both values are always materialised
and a typed reconciliation chooses the outgoing payload field by
field). The single-output discipline of ADR-0010 §5 is preserved:
the caller forwards exactly one 'Plan'; the trace carries both.

== What this module is /not/

This module is the algebraic /shape/ of deliberation. It does not
import from @QxFx0.Core.*@ and does not know anything about turn
pipelines, routing cascades, render strategies, or recovery sites.
The Phase-8 milestones (B.5.M1 / M2 / M3) are responsible for
constructing 'HolisticProposal' / 'FormalProposal' values from the
existing routing inputs and consuming the reconciled 'Plan' at the
three call sites currently using salience-based priority switching.

== Decision rule (overview)

Six rules apply in priority order; the first that matches becomes
'dtRule' on the returned trace:

1.  'RuleConatusOverride' — if @'salienceDriver' = 'DrivenByConatusGate'@
    the formal proposal is forced into a recovery shape regardless
    of the holistic proposal.
2.  'RuleAgreement' — if both proposals match field-for-field
    (modulo 'planConfidence'), the merged confidence is the max
    of the two.
3.  'RuleSalienceLead' — if 'salienceConfidence' exceeds
    'smEscalationConfidenceFloor', the verdict-side proposal wins
    wholesale.
4.  'RuleHolisticAdvantage' / 'RuleFormalAdvantage' — when exactly
    one of (family, style, tone) differs, the verdict side decides
    that single axis.
5.  'RuleTiedFallback' — formal proposal wins as the safe default
    (matches ADR-0010 §5).

In every non-Conatus rule, 'planRecoveryCause' is determined by
'pickHigherSeverity' across both proposals — recovery is never
silenced by a high-bias holistic proposal.

== Honest scope

The default 'NarrativeNeutral' tone, the 'recoveryCauseSeverity'
ordering, and the per-axis differs/equal classification are pinned
to make the property tests pass and the operational mapping
(ADR-0011) plausible. Calibration of the severity ladder against
empirical recovery preferences is Phase-7 (lifeness gates) work.
-}
module QxFx0.Self.Deliberation
  (     -- * Plan: hemispheric proposal payload
    Plan (..)
  , NarrativeTone (..)
  , defaultPlan
    -- * Tunable tone modulation thresholds
  , DeliberationModulation (..)
  , defaultDeliberationModulation
    -- * Proposals over the @Holistic ⊣ Formal@ adjunction
  , HolisticProposal
  , FormalProposal
  , holisticProposal
  , formalProposal
    -- * Deliberation result
  , Deliberation (..)
  , DeliberationTrace (..)
  , Agreement (..)
  , ReconcileRule (..)
    -- * Severity helper for recovery causes
  , recoveryCauseSeverity
  , pickHigherSeverity
    -- * The deliberation morphism
  , reconcile
     -- * Trace rendering (Phase-8 observability)
   , renderAgreement
   , renderReconcileRule
   , renderNarrativeTone
     -- * Default fallback (Phase-9 witness ingestion)
   , defaultDeliberation
   ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Self.Adjunction
  ( Field
  , Formal (..)
  , Holistic (..)
  , groundIn
  , probe
  )
import QxFx0.Self.Salience
  ( Salience (..)
  , SalienceDriver (..)
  , SalienceModulation (..)
  , SalienceVerdict (..)
  , defaultSalienceModulation
  , defaultSalienceWeights
  , salienceVerdict
  )
import QxFx0.Types.Decision.Enums.Render (RenderStyle (..))
import QxFx0.Types.Domain (CanonicalMoveFamily (..))
import QxFx0.Types.Recovery (LocalRecoveryCause (..))

-- ---------------------------------------------------------------------------
-- Narrative tone
-- ---------------------------------------------------------------------------

-- | Closed enumeration of narrative tones the dual-mode pipeline
-- can request. Distinct from
-- 'QxFx0.Types.Decision.Enums.Render.EmotionalTone' (which is a
-- post-render artefact tag) — this is a /pre/-render commitment
-- attached to the 'Plan' so each hemisphere can express tone
-- without having to bake it into the render style.
--
-- Constructors are prefixed @Narrative*@ to keep the namespace
-- distinct from the existing 'EmotionalTone' tags exported by
-- 'QxFx0.Types.Decision.Enums.Render'.
data NarrativeTone
  = NarrativeNeutral
  | NarrativeWarm
  | NarrativeFormal
  | NarrativeTerse
  | NarrativeRecovery
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Plan: hemispheric proposal payload
-- ---------------------------------------------------------------------------

-- | A composite proposal from one hemisphere for a single turn.
--
-- Aggregates every output decision currently scattered across
-- routing, render-style, and recovery so that two proposals can
-- be compared field-for-field by 'reconcile'.
--
-- Invariants:
--
--   * @0 \\<= 'planConfidence' \\<= 1@.
--   * 'planRecoveryCause' = 'Just' /c/ implies the proposing
--     hemisphere asserts a recovery condition; 'Nothing' means it
--     does not. Whether the merged plan emits recovery is decided
--     by 'pickHigherSeverity' across both sides, not by either
--     side alone.
data Plan = Plan
  { planFamily        :: !CanonicalMoveFamily
    -- ^ The proposed canonical move family for the turn.
  , planRenderStyle   :: !RenderStyle
    -- ^ The proposed render style.
  , planRecoveryCause :: !(Maybe LocalRecoveryCause)
    -- ^ A proposed recovery cause, or 'Nothing' to abstain.
    --   Recovery is never silenced by 'reconcile' — see
    --   'pickHigherSeverity' / 'RuleConatusOverride'.
  , planNarrativeTone :: !NarrativeTone
    -- ^ The proposed narrative tone.
  , planConfidence    :: !Double
    -- ^ How confident the proposing hemisphere is in this 'Plan',
    --   in @[0, 1]@.
  }
  deriving stock (Eq, Show)

-- | The neutral 'Plan' used as a safe fallback by callers
-- bootstrapping a hemispheric projection without strong signals.
--
-- Not consumed by 'reconcile' itself; provided so that downstream
-- helpers in the Phase-8 milestones (B.5.M1 / M2 / M3) have a
-- reproducible neutral starting point.
defaultPlan :: Plan
defaultPlan = Plan
  { planFamily        = CMReflect
  , planRenderStyle   = StyleStandard
  , planRecoveryCause = Nothing
  , planNarrativeTone = NarrativeNeutral
  , planConfidence    = 0.5
  }

-- ---------------------------------------------------------------------------
-- Tunable tone modulation thresholds
-- ---------------------------------------------------------------------------

-- | Thresholds for deriving the holistic 'NarrativeTone' from the
-- per-turn 'Field'.  Like 'SalienceModulation' in 'Self.Salience',
-- these are pinned to make integration tests pass and are
-- candidates for Phase-7 calibration.
data DeliberationModulation = DeliberationModulation
  { dmToneArousalFloor   :: !Double
    -- ^ 'atmosphereArousal' above this triggers a non-neutral tone.
    --   Default: 0.5.
  , dmToneValenceNeutral :: !Double
    -- ^ Valence at or above this (when arousal is above the floor)
    --   yields 'NarrativeWarm'; below yields 'NarrativeTerse'.
    --   Default: 0.0.
  }
  deriving stock (Eq, Show)

-- | Phase-8 default tone thresholds.  Values are bikeshed-eligible
-- but frozen for test stability.
defaultDeliberationModulation :: DeliberationModulation
defaultDeliberationModulation = DeliberationModulation
  { dmToneArousalFloor   = 0.5
  , dmToneValenceNeutral = 0.0
  }

-- ---------------------------------------------------------------------------
-- Proposals
-- ---------------------------------------------------------------------------

-- | Right-hemispheric proposal: a 'Plan' perceived /with/ the
-- 'Field' the proposing hemisphere read.
--
-- Type alias over the existing 'Holistic' functor from
-- @QxFx0.Self.Adjunction@; no new structure, just a documented
-- specialisation at @a = 'Plan'@.
type HolisticProposal = Holistic Plan

-- | Left-hemispheric proposal: a /strategy/ producing a 'Plan'
-- when given any 'Field', not committed to a particular ground.
--
-- Type alias over the existing 'Formal' functor from
-- @QxFx0.Self.Adjunction@; no new structure.
type FormalProposal = Formal Plan

-- | Smart constructor for 'HolisticProposal'. Pairs a 'Plan' with
-- the 'Field' it was perceived in.
holisticProposal :: Plan -> Field -> HolisticProposal
holisticProposal plan fd = Holistic (plan, fd)

-- | Smart constructor for 'FormalProposal'. Wraps a strategy in
-- the 'Formal' functor.
formalProposal :: (Field -> Plan) -> FormalProposal
formalProposal = Formal

-- ---------------------------------------------------------------------------
-- Deliberation result
-- ---------------------------------------------------------------------------

-- | Closed enumeration of how the two hemispheric proposals
-- relate per turn. Used in 'DeliberationTrace' for observability
-- and in 'Test.Suite.SelfDeliberation' for property checks.
--
-- Tag set is closed and trace-stable: any change is a breaking
-- change to the replay-trace JSON schema.
data Agreement
  = Agree
  | DivergeOnFamily
  | DivergeOnStyle
  | DivergeOnRecovery
  | DivergeOnTone
  | DivergeMultiple
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Closed enumeration of the rule that produced the reconciled
-- 'Plan'. Exactly one is chosen per call to 'reconcile'; rules
-- are tried in priority order (see module-level overview).
--
-- Tag set is closed and trace-stable.
data ReconcileRule
  = RuleAgreement
  | RuleConatusOverride
  | RuleSalienceLead
  | RuleHolisticAdvantage
  | RuleFormalAdvantage
  | RuleTiedFallback
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Per-turn observability record produced by 'reconcile'. Carried
-- alongside the reconciled 'Plan' in 'Deliberation'; intended to
-- be projected into 'QxFx0.Types.TurnProjection.TurnReplayTrace'
-- by the B.7 milestone.
data DeliberationTrace = DeliberationTrace
  { dtAgreement      :: !Agreement
    -- ^ How the two proposals related, classified by axes.
  , dtDivergence     :: !Double
    -- ^ Number of differing axes among
    --   @{family, style, recovery, tone}@ divided by @4@; in
    --   @[0, 1]@.
  , dtRule           :: !ReconcileRule
    -- ^ Which rule produced 'delibReconciled'.
  , dtSalienceDriver :: !SalienceDriver
    -- ^ Echo of 'salienceDriver' for compactness in the trace —
    --   so 'TurnReplayTrace' consumers do not have to join two
    --   records.
  }
  deriving stock (Eq, Show)

-- | The result of one deliberation. Carries both proposals in
-- their projected (value-level) form and the reconciled 'Plan'.
--
-- Single-output discipline (ADR-0010 §5): 'delibReconciled' is
-- the value the caller forwards downstream; 'delibHolistic' and
-- 'delibFormal' exist for trace and for diagnostics.
data Deliberation = Deliberation
  { delibHolistic    :: !Plan
    -- ^ 'groundIn' projection of the right-hemispheric proposal.
  , delibFormal      :: !Plan
    -- ^ 'probe' projection of the left-hemispheric proposal at
    --   the per-turn 'Field'.
  , delibReconciled  :: !Plan
    -- ^ The reconciled outgoing 'Plan'. Always exactly one of
    --   the four reconciliation paths.
  , delibTrace       :: !DeliberationTrace
    -- ^ Structured per-turn audit record.
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Recovery severity ladder
-- ---------------------------------------------------------------------------

-- | Total order on 'LocalRecoveryCause' used to merge two
-- proposals\' 'planRecoveryCause' fields.
--
-- 'Nothing' is the floor (severity @0@); a structural-Conatus
-- event is the ceiling. This ordering is the single source of
-- truth for B.3.5 (\"recovery is never silenced\"): the proposal
-- with higher severity wins on the recovery axis regardless of
-- the salience verdict.
--
-- Numbers are deliberately spaced so future variants slot in
-- without renumbering the existing ladder.
recoveryCauseSeverity :: Maybe LocalRecoveryCause -> Int
recoveryCauseSeverity Nothing                          = 0
recoveryCauseSeverity (Just RecoveryParserLowConfidence) = 20
recoveryCauseSeverity (Just RecoveryLowLegitimacy)       = 30
recoveryCauseSeverity (Just RecoveryUnknownTopic)        = 40
recoveryCauseSeverity (Just RecoveryShadowUnavailable)   = 50
recoveryCauseSeverity (Just RecoveryShadowDivergence)    = 60
recoveryCauseSeverity (Just RecoveryRuntimeDegraded)     = 70
recoveryCauseSeverity (Just RecoveryRenderBlocked)       = 80
recoveryCauseSeverity (Just RecoveryConatusGate)         = 100

-- | Pick the higher-severity recovery proposal per
-- 'recoveryCauseSeverity'. Ties favour the left argument so the
-- function is stable under repeated calls.
pickHigherSeverity
  :: Maybe LocalRecoveryCause
  -> Maybe LocalRecoveryCause
  -> Maybe LocalRecoveryCause
pickHigherSeverity a b
  | recoveryCauseSeverity a >= recoveryCauseSeverity b = a
  | otherwise = b

-- ---------------------------------------------------------------------------
-- Default fallback (Phase-9 witness ingestion)
-- ---------------------------------------------------------------------------

-- | A placeholder 'Deliberation' used when a turn did not run
-- 'reconcile' (e.g. Conatus-gated early exit).  Fields are chosen
-- to have minimal impact on the 'EssenceTrajectory': agreement
-- with zero divergence, neutral tone, and a stable driver so that
-- 'witness' does not accrue or decay angst artificially.
defaultDeliberation :: Deliberation
defaultDeliberation = Deliberation
  { delibHolistic   = defaultPlan
  , delibFormal     = defaultPlan
  , delibReconciled = defaultPlan
  , delibTrace      = DeliberationTrace
      { dtAgreement      = Agree
      , dtDivergence     = 0.0
      , dtRule           = RuleSalienceLead
      , dtSalienceDriver = DrivenByDefault
      }
  }

-- ---------------------------------------------------------------------------
-- The deliberation morphism
-- ---------------------------------------------------------------------------

-- | Reconcile a holistic and a formal proposal under a salience
-- verdict, producing a 'Deliberation' record that includes both
-- projected proposals, the reconciled 'Plan', and a per-turn
-- 'DeliberationTrace'.
--
-- Total, deterministic, pure. Identical inputs produce identical
-- 'Deliberation' values, including 'dtRule' and 'dtAgreement'.
--
-- Rule priority (first match wins; see module-level overview for
-- the rationale):
--
--   1.  'RuleConatusOverride' on @'salienceDriver' = 'DrivenByConatusGate'@.
--   2.  'RuleAgreement' on field-for-field equality (modulo
--       'planConfidence').
--   3.  'RuleSalienceLead' when @'salienceConfidence' >
--       'smEscalationConfidenceFloor' 'defaultSalienceModulation'@.
--   4.  'RuleHolisticAdvantage' / 'RuleFormalAdvantage' on
--       single-axis disagreement (excluding the recovery axis).
--   5.  'RuleTiedFallback' otherwise — formal proposal wins as
--       the safe default (ADR-0010 §5).
--
-- The recovery axis is always merged via 'pickHigherSeverity',
-- regardless of which rule fires (except 'RuleConatusOverride',
-- which forces 'Just' 'RecoveryConatusGate' wholesale).
reconcile
  :: Maybe (Plan -> Bool)   -- ^ Phase 10: optional courtesy predicate.
                              -- When 'RuleTiedFallback' fires and this is
                              -- 'Just p', the tie-break prefers the
                              -- proposal that satisfies @p@, but only
                              -- if exactly one does.  Never widens the
                              -- admissible set.
  -> Salience
  -> HolisticProposal
  -> FormalProposal
  -> Field
  -> Deliberation
reconcile mCourtesy salience hp fp fd =
  let hPlan          = groundIn hp
      fPlan          = probe fp fd
      driver         = salienceDriver salience
      agreement      = classifyAgreement hPlan fPlan
      divergence     = computeDivergence hPlan fPlan
      mergedRecovery = pickHigherSeverity (planRecoveryCause hPlan) (planRecoveryCause fPlan)
      mkTrace rule = DeliberationTrace
        { dtAgreement      = agreement
        , dtDivergence     = divergence
        , dtRule           = rule
        , dtSalienceDriver = driver
        }
      mkResult plan rule = Deliberation
        { delibHolistic   = hPlan
        , delibFormal     = fPlan
        , delibReconciled = plan
        , delibTrace      = mkTrace rule
        }
   in case driver of
        DrivenByConatusGate ->
          let conatusPlan = fPlan
                { planRenderStyle   = StyleRecovery
                , planRecoveryCause = Just RecoveryConatusGate
                , planNarrativeTone = NarrativeRecovery
                , planConfidence    = 1.0
                }
           in mkResult conatusPlan RuleConatusOverride

        _ | plansEqualModConfidence hPlan fPlan ->
              let agreedPlan = hPlan
                    { planConfidence    = max (planConfidence hPlan) (planConfidence fPlan)
                    , planRecoveryCause = mergedRecovery
                    }
               in mkResult agreedPlan RuleAgreement

        _ | salienceConfidence salience > smEscalationConfidenceFloor defaultSalienceModulation ->
              let chosen = case salienceVerdict defaultSalienceWeights salience of
                    PreferHolistic _ -> hPlan
                    PreferFormal   _ -> fPlan
                    Tied             -> fPlan
                  withRecovery = chosen { planRecoveryCause = mergedRecovery }
               in mkResult withRecovery RuleSalienceLead

        _ | singleNonRecoveryAxisDiffers hPlan fPlan ->
              let (rule, base) = case salienceVerdict defaultSalienceWeights salience of
                    PreferHolistic _ -> (RuleHolisticAdvantage, hPlan)
                    PreferFormal   _ -> (RuleFormalAdvantage,   fPlan)
                    Tied             -> (RuleFormalAdvantage,   fPlan)
                  withRecovery = base { planRecoveryCause = mergedRecovery }
               in mkResult withRecovery rule

        _ ->
              let baseFallback = fPlan { planRecoveryCause = mergedRecovery }
                  fallback = case mCourtesy of
                    Nothing -> baseFallback
                    Just pred ->
                      case (pred hPlan, pred fPlan) of
                        (True, False) -> hPlan { planRecoveryCause = mergedRecovery }
                        _             -> baseFallback
               in mkResult fallback RuleTiedFallback

-- ---------------------------------------------------------------------------
-- Trace rendering
-- ---------------------------------------------------------------------------

-- | Render an 'Agreement' to a stable @snake_case@ tag. Closed
-- set; any change is a breaking change to the replay-trace JSON
-- schema.
renderAgreement :: Agreement -> Text
renderAgreement Agree             = "agree"
renderAgreement DivergeOnFamily   = "diverge_on_family"
renderAgreement DivergeOnStyle    = "diverge_on_style"
renderAgreement DivergeOnRecovery = "diverge_on_recovery"
renderAgreement DivergeOnTone     = "diverge_on_tone"
renderAgreement DivergeMultiple   = "diverge_multiple"

-- | Render a 'ReconcileRule' to a stable @snake_case@ tag. Closed
-- set; trace-stable.
renderReconcileRule :: ReconcileRule -> Text
renderReconcileRule RuleAgreement         = "agreement"
renderReconcileRule RuleConatusOverride   = "conatus_override"
renderReconcileRule RuleSalienceLead      = "salience_lead"
renderReconcileRule RuleHolisticAdvantage = "holistic_advantage"
renderReconcileRule RuleFormalAdvantage   = "formal_advantage"
renderReconcileRule RuleTiedFallback      = "tied_fallback"

-- | Render a 'NarrativeTone' to a stable @snake_case@ tag. Closed
-- set; trace-stable.
renderNarrativeTone :: NarrativeTone -> Text
renderNarrativeTone NarrativeNeutral  = "neutral"
renderNarrativeTone NarrativeWarm     = "warm"
renderNarrativeTone NarrativeFormal   = "formal"
renderNarrativeTone NarrativeTerse    = "terse"
renderNarrativeTone NarrativeRecovery = "recovery"

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

-- | Field-for-field equality on 'Plan' that ignores
-- 'planConfidence'. Used by 'RuleAgreement'.
plansEqualModConfidence :: Plan -> Plan -> Bool
plansEqualModConfidence a b =
     planFamily        a == planFamily        b
  && planRenderStyle   a == planRenderStyle   b
  && planRecoveryCause a == planRecoveryCause b
  && planNarrativeTone a == planNarrativeTone b

-- | Classify how the two plans differ across the four axes.
classifyAgreement :: Plan -> Plan -> Agreement
classifyAgreement a b =
  let famDiff = planFamily        a /= planFamily        b
      styDiff = planRenderStyle   a /= planRenderStyle   b
      recDiff = planRecoveryCause a /= planRecoveryCause b
      tonDiff = planNarrativeTone a /= planNarrativeTone b
      diffs   = [famDiff, styDiff, recDiff, tonDiff]
      n       = length (filter id diffs)
   in case n of
        0 -> Agree
        1
          | famDiff -> DivergeOnFamily
          | styDiff -> DivergeOnStyle
          | recDiff -> DivergeOnRecovery
          | tonDiff -> DivergeOnTone
          | otherwise -> Agree
        _ -> DivergeMultiple

-- | Number of differing axes / 4. Always in @[0, 1]@.
computeDivergence :: Plan -> Plan -> Double
computeDivergence a b =
  let count = length . filter id $
        [ planFamily        a /= planFamily        b
        , planRenderStyle   a /= planRenderStyle   b
        , planRecoveryCause a /= planRecoveryCause b
        , planNarrativeTone a /= planNarrativeTone b
        ]
   in fromIntegral count / 4.0

-- | Predicate: do the two plans differ on exactly one of
-- @{family, style, tone}@? The recovery axis is excluded because
-- it is always merged separately via 'pickHigherSeverity'.
singleNonRecoveryAxisDiffers :: Plan -> Plan -> Bool
singleNonRecoveryAxisDiffers a b =
  let diffs =
        [ planFamily        a /= planFamily        b
        , planRenderStyle   a /= planRenderStyle   b
        , planNarrativeTone a /= planNarrativeTone b
        ]
   in length (filter id diffs) == 1
