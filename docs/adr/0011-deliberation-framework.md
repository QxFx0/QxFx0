# ADR-0011: Deliberation Framework

- **Status**: Accepted (Phase 8, Package B)
- **Date**: 2026-05-18
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0008 — Left ⊣ Right adjunction as dual-mode backbone](./0008-left-right-adjunction.md)
  - [ADR-0009 — Right-hemisphere Field components](./0009-right-hemisphere-field.md)
  - [ADR-0010 — Salience Controller](./0010-salience-controller.md)
- **Related**:
  - `QxFx0.Self.Deliberation` (pure module)
  - `QxFx0.Core.TurnRouting` (M1 consumer)
  - `QxFx0.Core.TurnPipeline.Route.Render` (M3 consumer)
  - `QxFx0.Core.TurnPipeline.Finalize.State` (trace population)

## 1. Context

Phase 3 (ADR-0008) shipped the adjunction `Holistic ⊣ Formal`.  Phase 4
(ADR-0009) gave the right hemisphere its five-component `Field`.  Phase 5
(ADR-0010) added the salience controller that decides, per turn, which
hemisphere should *lead*.  All three phases are pure and self-contained.

What was missing was the *reconciliation* step: once the controller has
produced a verdict, and both hemispheres have produced a concrete *Plan*
(family, style, recovery cause, narrative tone, confidence), how does the
runtime merge the two proposals into a single outgoing decision while
keeping both visible for tracing and replay?

That missing step is the **deliberation framework**.  It is the last pure
module in the `Self.*` subtree and the bridge between the algebraic layers
(Phases 1–5) and the turn-pipeline call sites (`routeFamily`,
`buildLocalRecoveryPlan`, `buildTurnProjection`).

## 2. Decision

We introduce a single new module, `QxFx0.Self.Deliberation`, and a single
morphism:

```haskell
reconcile
  :: Salience            -- controller verdict for this turn
  -> HolisticProposal    -- right-hemispheric Plan (grounded in Field)
  -> FormalProposal      -- left-hemispheric Plan (probed at this Field)
  -> Field               -- the per-turn Field both proposals observe
  -> Deliberation        -- both proposals + reconciled Plan + trace
```

A `Plan` is a closed record of every output decision the dual-mode runtime
currently makes:

```haskell
data Plan = Plan
  { planFamily        :: !CanonicalMoveFamily
  , planRenderStyle   :: !RenderStyle
  , planRecoveryCause :: !(Maybe LocalRecoveryCause)
  , planNarrativeTone :: !NarrativeTone
  , planConfidence    :: !Double        -- in [0, 1]
  }
```

`Deliberation` carries *both* projected proposals, the reconciled outgoing
`Plan`, and a structured `DeliberationTrace`:

```haskell
data Deliberation = Deliberation
  { delibHolistic   :: !Plan
  , delibFormal     :: !Plan
  , delibReconciled :: !Plan          -- single-output discipline (§4)
  , delibTrace      :: !DeliberationTrace
  }

data DeliberationTrace = DeliberationTrace
  { dtAgreement      :: !Agreement      -- how the two proposals relate
  , dtDivergence     :: !Double         -- differing axes / 4, in [0, 1]
  , dtRule           :: !ReconcileRule  -- which rule produced the result
  , dtSalienceDriver :: !SalienceDriver -- echo of controller verdict
  }
```

The tag sets (`Agreement`, `ReconcileRule`, `NarrativeTone`) are closed and
JSON-schema-stable: any change is a breaking change to the replay trace.

## 3. Reconciliation rule (priority order)

Rules are tried in strict priority; the first match wins and becomes
`dtRule`.

| Priority | Rule | Trigger |
|----------|------|---------|
| 1 | `RuleConatusOverride` | `salienceDriver = DrivenByConatusGate` |
| 2 | `RuleAgreement` | Both proposals equal modulo `planConfidence` |
| 3 | `RuleSalienceLead` | `salienceConfidence > smEscalationConfidenceFloor` |
| 4 | `RuleHolisticAdvantage` / `RuleFormalAdvantage` | Exactly one non-recovery axis differs |
| 5 | `RuleTiedFallback` | All other cases |

**Recovery axis semantics.**  In every non-Conatus rule, the merged
`planRecoveryCause` is determined by `pickHigherSeverity` across both
proposals — recovery is **never silenced** by a high-bias holistic
proposal (§5.1).  `RuleConatusOverride` is the sole exception: it forces
`Just RecoveryConatusGate` wholesale, because the Conatus gate already
represents the highest-severity structural event.

**Why this order.**

- *Conatus override* is unambiguous safety: when the system is structurally
  at risk, no Field-derived signal may contest the formal-contract fallback.
- *Agreement* is the fast path for the common case where both hemispheres
  converge; it avoids the cost of axis-by-axis arbitration.
- *Salience lead* lets the controller assert a clear preference when its
  confidence is above the escalation floor.
- *Single-axis advantage* resolves the minimal disagreement: if only family
  or only style differs, the verdict side decides that single axis without
  touching the others.
- *Tied fallback* defaults to the formal proposal, preserving ADR-0010 §5
  (Formal is the safe default when no decisive signal exists).

## 4. Single-output discipline

ADR-0010 §5 established the anti-correlation discipline: the non-leading
mode listens but does not emit.  The deliberation framework extends that
discipline to the *merge* step:

1. **Exactly one Plan reaches downstream code.**  `delibReconciled` is the
   only value forwarded to `routeFamily`, `RenderEffects`, and recovery
   planning.  The two raw proposals exist only for trace and diagnostics.
2. **Recovery is never silenced.**  Even when the leading mode proposes
   `Nothing`, if the trailing mode proposes a higher-severity cause, the
   merged Plan carries it (§3).
3. **Trace fields are total.**  `dtAgreement`, `dtRule`, `dtDivergence`,
   and `dtSalienceDriver` are always present in `DeliberationTrace`; there
   is no "deliberation disabled" path that would leave them absent.

## 5. Safety invariants

These invariants are enforced by the implementation and verified by the
integration test suite.

### 5.1 Recovery never silenced

`pickHigherSeverity` defines a total order on `Maybe LocalRecoveryCause`:

```
Nothing                           = 0
RecoveryParserLowConfidence       = 20
RecoveryLowLegitimacy             = 30
RecoveryUnknownTopic              = 40
RecoveryShadowUnavailable         = 50
RecoveryShadowDivergence          = 60
RecoveryRuntimeDegraded           = 70
RecoveryRenderBlocked             = 80
RecoveryConatusGate               = 100
```

The merged recovery cause is always the *maximum* of the two proposals,
with ties favouring the left argument for stability under repeated calls.
`RuleConatusOverride` bypasses this merge because it unconditionally forces
`RecoveryConatusGate` (severity 100), which is already the ceiling.

### 5.2 Conatus override is total and deterministic

When `salienceDriver = DrivenByConatusGate`, `reconcile` *always* returns
`RuleConatusOverride` and a Plan with:

- `planRenderStyle = StyleRecovery`
- `planRecoveryCause = Just RecoveryConatusGate`
- `planNarrativeTone = NarrativeRecovery`
- `planConfidence = 1.0`

This is independent of the contents of either proposal; the Conatus gate is
a hard circuit-breaker, not a weighted vote.

### 5.3 Staged identical-proposal baseline

During Package B, both formal and holistic proposals are initialised to
the *same* existing final values (`adjustedFamily`, `salienceStyle`).  This
staged integration guarantees that `reconcile` yields `RuleAgreement` on
all pre-existing inputs, preventing behaviour drift while the plumbing is
proven stable.

Package C (2026-05-18) introduced **observability-grade divergence** on the
narrative-tone axis: the holistic proposal derives `planNarrativeTone` from
`fieldAtmosphere` (arousal/valence thresholds), while the formal proposal
stays `NarrativeNeutral`.  Family and style remain identical, so runtime
output is byte-for-byte unchanged; the divergence is visible only in
trace fields (`trcDeliberationAgreement`, `trcDeliberationNarrativeTone`).

### 5.4 Determinism

`reconcile` is a pure, total function.  Identical inputs produce identical
`Deliberation` values, including the discrete `dtRule` and `dtAgreement`
tags.  This property is checked by `Test.Suite.SelfDeliberation` and
by the integration locks in `Test.Suite.CoreBehavior`.

## 6. Runtime integration (M1 / M2 / M3)

The framework is consumed at three pipeline sites, all in the current
Package B rollout.

### 6.1 M1 — `routeFamily` (TurnRouting)

`routeFamily` now constructs a `Plan` for each hemisphere, calls
`reconcile`, and stores `Just deliberation` in the returned
`RoutingDecision`:

```haskell
routingSalience = salienceFromConatusEnergy conatusEnergy preparedField
cascade = runFamilyCascade phase ss nextUserState frame atomSet
            history input mNarrative intuitPosterior isNixBlocked routingSalience
FamilyCascade{..} = cascade

-- Package D: family divergence is feature-flagged (default False)
-- so baseline behaviour is preserved while the adjunction mapping
-- is corrected.
familyDivergenceEnabled = False
formalFamily   = fcFinalFamily
holisticFamily = if familyDivergenceEnabled
                   then nearestHolistic fcFinalFamily
                   else fcFinalFamily

baseStyle =
  let styleIdentitySignal = buildIdentitySignalSimple ... fcFinalFamily ...
      styleSemanticInput  = buildSemanticInputSimple  ... fcFinalFamily ...
      styleSemanticAnchor = deriveSemanticAnchor ... styleSemanticInput ...
   in renderStyleFromDecision renderStrategy ... styleIdentitySignal ...
salienceStyle = applySalienceToStyle routingSalience preparedField baseStyle

formalPlan = defaultPlan
  { planFamily      = formalFamily
  , planRenderStyle = salienceStyle
  }

holisticPlan = defaultPlan
  { planFamily      = holisticFamily
  , planRenderStyle = salienceStyle
  , planNarrativeTone =
      let a  = fieldAtmosphere preparedField
          dm = defaultDeliberationModulation
       in if atmosphereArousal a > dmToneArousalFloor dm &&
            atmosphereValence a >= dmToneValenceNeutral dm
           then NarrativeWarm
         else if atmosphereArousal a > dmToneArousalFloor dm &&
                 atmosphereValence a < dmToneValenceNeutral dm
           then NarrativeTerse
           else NarrativeNeutral
  , planConfidence  = salienceConfidence routingSalience
  }

-- Package D: formal hemisphere probes the field; holistic hemisphere
-- carries atmosphere-derived tone already baked into the Plan, so the
-- wrapper is field-independent (emptyField).
deliberation = reconcile routingSalience
                       (holisticProposal holisticPlan emptyField)
                       (formalProposal (\_fd -> formalPlan))
                       preparedField

reconciledPlan = delibReconciled deliberation
```

Downstream values (`newEgo`, `identitySignal`, `semanticInput`,
`semanticAnchor`) are recomputed from the reconciled family and style if
they diverge from the cascade candidate.  This keeps all call sites
consistent with the single-output discipline.

**Package D changes in this section:**
- `applySalienceEscalation` (the second salience modulation layer) has
  been removed; `runFamilyCascade` already receives `routingSalience`
  and is the single pre-deliberation family source.
- The pre-mirror block (`preEgo`, `preIdentitySignal`, `preGuardReport`,
  `preSemanticInput`, `preSemanticAnchor`) has been inlined into the
  `baseStyle` computation to remove redundant let-bindings.
- The adjunction caller mapping is now orthodox: `formalProposal` receives
  the field probe, `holisticProposal` is paired with `emptyField`.

### 6.2 M2 — `buildRouteTurnPlan` (Route/Build)

`buildRouteTurnPlan` forwards `rdDeliberation` from the
`RoutingDecision` into `TurnPlan.tpDeliberation`, making the
`Deliberation` available to the render and finalize phases.

### 6.3 M3 — `buildLocalRecoveryPlan` and `buildTurnArtifacts` (Route/Render)

`buildLocalRecoveryPlan` already computes a recovery cause from local
signals (parser confidence, legitimacy, runtime mode).  In Package B,
`buildTurnArtifacts` overlays the deliberation recovery cause on top of
that local computation:

```haskell
delibRecoveryCause = tpDeliberation tp >>= planRecoveryCause . delibReconciled
finalRecoveryCause = case delibRecoveryCause of
  Just c  -> Just c
  Nothing -> recoveryCause          -- local plan fallback
```

This is the *runtime realisation* of §5.1: when `reconcile` has already
merged a recovery cause into the reconciled Plan, the artifact trace
must preserve it even if the local recovery planner would not have
produced one.

### 6.4 M4 — `buildTurnProjection` (Finalize/State)

`buildTurnProjection` populates the four new nullable fields in
`TurnReplayTrace` from `tpDeliberation`:

```haskell
trcDeliberationRule           = renderReconcileRule     <$> dtRule trace
trcDeliberationAgreement      = renderAgreement           <$> dtAgreement trace
trcDeliberationDivergence     = Just (dtDivergence trace)
trcDeliberationNarrativeTone  = renderNarrativeTone     <$> planNarrativeTone reconciled
```

When `tpDeliberation = Nothing` (should never happen after M2), the fields
remain `Nothing` for backward compatibility with pre-Package B traces.

## 7. Trace rendering

All deliberation tags are rendered to stable snake_case `Text` for JSON:

| Type | Constructor | Rendered tag |
|------|-------------|--------------|
| `Agreement` | `Agree` | `"agree"` |
| `Agreement` | `DivergeOnFamily` | `"diverge_on_family"` |
| `Agreement` | `DivergeOnStyle` | `"diverge_on_style"` |
| `Agreement` | `DivergeOnRecovery` | `"diverge_on_recovery"` |
| `Agreement` | `DivergeOnTone` | `"diverge_on_tone"` |
| `Agreement` | `DivergeMultiple` | `"diverge_multiple"` |
| `ReconcileRule` | `RuleAgreement` | `"agreement"` |
| `ReconcileRule` | `RuleConatusOverride` | `"conatus_override"` |
| `ReconcileRule` | `RuleSalienceLead` | `"salience_lead"` |
| `ReconcileRule` | `RuleHolisticAdvantage` | `"holistic_advantage"` |
| `ReconcileRule` | `RuleFormalAdvantage` | `"formal_advantage"` |
| `ReconcileRule` | `RuleTiedFallback` | `"tied_fallback"` |
| `NarrativeTone` | `NarrativeNeutral` | `"neutral"` |
| `NarrativeTone` | `NarrativeWarm` | `"warm"` |
| `NarrativeTone` | `NarrativeFormal` | `"formal"` |
| `NarrativeTone` | `NarrativeTerse` | `"terse"` |
| `NarrativeTone` | `NarrativeRecovery` | `"recovery"` |

## 8. Acceptance criteria

### Package B

1. `cabal build lib:qxfx0` compiles with the new fields in
   `RoutingDecision`, `TurnPlan`, and `TurnReplayTrace`.
2. `Test.Suite.SelfDeliberation` passes: conatus override,
   agreement idempotence, recovery preservation, tied fallback,
   divergence boundedness, determinism, and render totality.
3. `Test.Suite.CoreBehavior` passes the three new deliberation
   integration locks:
   - `testRouteFamilyDeliberationPopulated` — `rdDeliberation` is
     `Just`, `dtRule = RuleAgreement`, divergence = 0.0 on baseline.
   - `testRouteFamilyConatusOverrideDeliberation` — forced Conatus
     gate yields `RuleConatusOverride`, `StyleRecovery`,
     `RecoveryConatusGate`, `NarrativeRecovery`.
   - `testRouteFamilyAgreementIdempotence` — identical inputs
     produce identical `Deliberation` values.
4. `Test.Suite.TurnPipelineProtocol` passes
   `testDeliberationRecoveryNotSilenced` — a deliberation carrying
   `RecoveryConatusGate` survives into `taLocalRecoveryCause` even
   when `buildLocalRecoveryPlan` returns `Nothing`.
5. `qxfx0-test` (aggregate suite) reports 0 errors, 0 failures.
6. `scripts/check_architecture.sh` reports no new boundary violations.

### Package C (observability-grade divergence)

7. `Test.Suite.CoreBehavior` passes
   `testRouteFamilyHolisticFieldDeliberationDivergence` — when
   `fieldAtmosphere` carries high arousal and positive valence,
   `reconcile` yields `DivergeOnTone`, `RuleSalienceLead`, and
   the reconciled Plan carries `NarrativeWarm`.
8. `qxfx0-test` aggregate suite reports 0 errors, 0 failures with
   the new test included.
9. No downstream rendering or family-selection behaviour changes
   for any existing test fixture (byte-for-byte output preservation).

## 9. Honest limits

- **Package C divergence is observability-only.**  The holistic
  proposal now derives `planNarrativeTone` from `fieldAtmosphere`,
  producing trace-visible `DivergeOnTone`, but the reconciled tone
  is **not yet read** downstream for rendering or family selection.
  Runtime output is byte-for-byte identical to Package B; the
  divergence exists only in `DeliberationTrace` and
  `TurnReplayTrace`.  Full routing of tone into render style is
  deferred to a future package.
- **Severity ladder is pinned, not calibrated.**  The numeric spacing
  of `recoveryCauseSeverity` is designed to allow future insertion
  without renumbering, but the ordering itself is a design choice,
  not an empirical finding.
- **Narrative tone is partially exercised.**  `NarrativeNeutral` and
  `NarrativeRecovery` are active in the runtime.  `NarrativeWarm`
  and `NarrativeTerse` are produced by the holistic proposal under
  specific atmosphere thresholds but are not yet routed into the
  rendered surface.  `NarrativeFormal` is reserved for future
  render-style expansion.
- **No static guarantee of single-output.**  The discipline is
  enforced operationally (the caller uses `delibReconciled`), not
  by the type system.  A future refactor could wrap the two raw
  proposals in an opaque `DeliberationPair` ADT.
- ~~Adjunction is currently inverted in the caller.~~  **Resolved
  in Package D (2026-05-18).**  The orthodox ADR-0008 mapping is
  now restored: formal receives the field probe, holistic carries a
  pre-baked Plan paired with `emptyField`.

## 10. Addendum (2026-05-18, Package B completion)

All Package B acceptance criteria (§8.1–6) have been met.  The
aggregate suite `qxfx0-test` passed `552 / 552` cases.

## 11. Addendum (2026-05-18, Package C completion)

Package C acceptance criteria (§8.7–9) have been met.  The
aggregate suite `qxfx0-test` passes `553 / 553` cases.
The `DeliberationModulation` / `defaultDeliberationModulation`
record centralises the tone arousal/valence thresholds that were
previously hardcoded at `0.5` and `0.0` in `routeFamily`.

## 12. Addendum (2026-05-18, Package D completion)

Package D acceptance criteria have been met:

1. Adjunction caller mapping corrected (§6.1): formal probes field,
   holistic is field-independent.
2. `applySalienceEscalation` removed; `nearestHolistic` retained as a
   local helper behind the `familyDivergenceEnabled = False` feature
   flag.  Cascade modulation (`runFamilyCascade`) is now the single
   pre-deliberation family source.
3. Pre-mirror block (`preEgo`, `preIdentitySignal`, `preGuardReport`,
   `preSemanticInput`, `preSemanticAnchor`) inlined into `baseStyle`
   computation, removing redundant let-bindings.
4. F1 regression locks retargeted from the removed `adjustedFamily`
   intermediate to observable contract (`rdFamily` /
   `delibReconciled.planFamily`).
5. Aggregate suite `qxfx0-test` passes `553 / 553` cases with zero
   new warnings.
