# Self-Layer Production Status (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 10)
- **Date**: 2026-06-02
- **Refines**: AGENTS.md, ADRs 0007–0012
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md`
  - `docs/adr/proposed/0034-self-core-role-split.md`

## 0. Why this document exists

The closure plan's Package 10 requires that "feature flags and
documentation match, and inactive contours are not presented as a
working cognitive core". This document is the per-module status
sheet for every `Self/*.hs` module, every `Self/Perspective/*.hs`
submodule, and the closely-related `Core/Consciousness/*` supplier
modules that produce the content `Self/*` regulates.

For each module the table below records:
- **Phase** — the AGENTS.md phase that landed it.
- **Status** — one of `production`, `production-flag-off`,
  `experimental`, `observability-only`, `legacy`.
- **Last integration date** — when the module was last touched on
  the canonical path.
- **Replay-visible** — does the module's output appear in the
  `TurnReplayTrace`?
- **Calibration status** — bikeshed / hand-set / empirically
  calibrated.
- **Promotion or demotion criterion** — what would move it to
  another status.

## 1. Status legend

| Status | Meaning |
|---|---|
| `production` | Default-on, in the runtime path, regression-locked. |
| `production-flag-off` | Landed, fully tested, but gated by a feature flag defaulted to `False`. Not in the runtime path today. |
| `experimental` | Landed but not promotion-ready (missing corpus validation, missing replay discipline, or has known issues). |
| `observability-only` | Reads canonical state, emits only into trace. Not in the runtime decision path. |
| `legacy` | Compatibility residue. Not on the canonical path. |

## 2. Self/*.hs canonical modules

| Module | Phase | Status | Last touched | Replay-visible | Calibration | Promotion / demotion criterion |
|---|---|---|---|---|---|---|
| `Self.Adjunction` | 3 | `production` | 2026-05-17 (ADR-0008 addendum) | indirectly via `Deliberation` | hand-set (algebra, not tunable) | n/a — algebraic backbone |
| `Self.Blanket` | 1 | `production` | Phase 1, see commits `62d0338`, `a5fad49` | yes (`IdentityRupture` trace) | n/a (predicate, not tunable) | n/a |
| `Self.Conatus` | 2 | `production` (canonical signal source) | 2026-05-17 (M6 single-source-of-truth) | yes (`trcSalienceDriver` etc.) | weights in `ConatusWeights` are hand-set; ADR-0012 §15.1 corrected `emConatusStructuralFloor` to 7.0 | promotion: n/a. demotion: never (gate priority). |
| `Self.Deliberation` | 8 | `production` | 2026-05-18 (Packages A–D) | yes (`trcDeliberationRule`, `trcDeliberationAgreement`, `trcDeliberationDivergence`, `trcDeliberationNarrativeTone`) | severity ladder is pinned, not calibrated (ADR-0011 §9) | promotion: n/a. demotion: never (reconcile is the merge point). |
| `Self.Field` | 4 | `production` | 2026-05-17 (Phase 5.5d wiring) | indirectly via Salience | 5 components are hand-set; field per-component sourcing calibrated in ADR-0009 addendum 2026-05-17 | promotion: n/a. demotion: would regress Salience. |
| `Self.Invariants` | (continuous) | `production` | current | n/a (pure property assertions) | n/a | n/a |
| `Self.Salience` | 5 | `production` | 2026-05-17 (Phase 5.5e trace) | yes (`trcSalienceDriver`, `trcSalienceHolisticBias`, `trcSalienceConfidence`) | `defaultSalienceWeights` are hand-set; bikeshed-eligible; Phase 7 calibration completed in skeleton (AGENTS.md) but empirical tuning deferred | promotion: n/a. demotion: would regress the salience-gated narrative path. |
| `Self.Types` | (continuous) | `production` | current | n/a (type-only) | n/a | n/a |

## 3. Self/*.hs canonical-flag-off modules

| Module | Phase | Status | Flag | Last touched | Replay-visible | Promotion / demotion criterion |
|---|---|---|---|---|---|---|
| `Self.Essence` | 9–10 | `production-flag-off` | `essenceCommitmentEnabled :: Bool` default `False` (AGENTS.md, ADR-0012) | 2026-05-19 (Phase 10 closure) | yes (`trcEssenceMode`, `trcEssenceCommitted`, `trcEssenceAngstLevel`, `trcEssenceTrigger`) | **promotion** requires (a) corpus replay with 0 `EssenceRupture` events on production trace (>1k turns), (b) angst-dynamics verification against real `Deliberation` data (ADR-0012 §15.2 notes synthetic corpora cannot do this), (c) `extractMode` coherence locks (E1–E5 in ADR-0012 §9). **demotion** would mean retiring the entire layer; an explicit demotion ADR is required. |
| `Self.Perspective` (file) | 4-P4 | `production-flag-off` | per AGENTS.md P4 — `PerspectiveRegistry` is canonical lineage, `PerspectiveOperator` is the operator, both gated; `PerspectiveProjection` is what replay/render may consume. **No explicit feature flag in code today — flag is implicit in "replay/render must consume only PerspectiveProjection".** | P4 work | yes via projection | **promotion** requires an explicit `QXFX0_PERSPECTIVE_OPERATOR_ENABLED` flag + a promote-ADR; **clarification** requires AGENTS.md update to name the flag. |
| `Self.Perspective` family divergence (in `routeFamily`) | 8-D | `production-flag-off` | `familyDivergenceEnabled :: Bool` default `False` (ADR-0011 §5.3, Package D) | 2026-05-18 (Package D) | yes (when enabled) | **promotion** requires Package B/C/D stabilisation; **demotion** is the current default. |

## 4. Core/Consciousness/* supplier modules

These are the modules that produce the **content** `Self/*` decides
about. Per ADR-0034 they are suppliers, not canonical writers of
cognitive state. Their calibration status is the closure plan's
Package 2 / 11 work.

| Module | Status | Replay-visible | Notes |
|---|---|---|---|
| `Core.Consciousness` | `production` (supplier) | yes (narrative fragment, gated by Salience) | The `ConsciousnessModel` Σ-type. The `runConsciousnessLoop` runs it. Output is gated by `applySalienceToNarrativeFragment` (in `ConsciousnessLoop.hs`) before reaching the prompt. |
| `Core.ConsciousnessLoop` | `production` (canonical-orchestrator) | yes | Hosts the salience gate. |
| `Core.BackgroundProcess` | `production` (supplier) | via trace | `runBackgroundCycle`, `SurfacingEvent`. |
| `Core.Consciousness.Kernel` | `production` (supplier) | indirectly via narrative | The kernel with desires/skills/ontology. The closure plan's Package 2 will rewrite the keyword-conditional `kernelPulse` to read typed semantic observations. |
| `Core.Consciousness.Kernel.Init` | `production` (supplier) | n/a | Initial kernel state. |
| `Core.Consciousness.Kernel.Pulse` | `production` (supplier) | via narrative | The keyword-conditional pulse. The closure plan's Package 2 reduces this to a thin typed-observation emitter. **Caveat:** if Package 2 fails to land, this module is the largest **observability-only** risk in the runtime — it produces text-shaped output that is not typed. |
| `Core.DreamDynamics` | `observability-only` | yes (trace-only) | Reads kernel + Field, runs offline dream dynamics. Per `AGENTS.md` and ADR-0011, observer status is enforced operationally. |
| `Core.MeaningGraph` | `production` (supplier) | yes (in trace) | `MeaningGraph` populated by `TurnPipeline.Effects`. Read by Kernel and Trace. |

## 5. Calibration status (the Phase 7 work)

Per AGENTS.md, **Phase 7 (structural calibration infrastructure) completed 2026-05-18**: `FieldHeuristics` + 3 compute functions extracted from Phase-5.5d inline constants; `defaultSalienceWeights` lifeness property tests landed in `Test.Suite.SelfField` and `Test.Suite.SelfSalience`. **Empirical tuning against production trace corpora remains deferred.**

This means the closure plan's Package 11 (calibration of the surviving
substrate) is not "do calibration" — it is "produce the first
empirically-justified calibration of the existing parameters,
against a production trace corpus that does not yet exist in
quantity". The Package 11 backlog is the precondition for any
honest "calibrated" claim.

Specifically the modules whose parameters are **hand-set** today
and would benefit from empirical calibration:

- `Self.Salience.SalienceWeights` (5 weights + 2 thresholds).
- `Self.Field.Heuristics` (5 component sourcing rules).
- `Self.Essence.EssenceModulation` (6 fields, partially calibrated; angst side deferred per ADR-0012 §15.2).
- `Self.Deliberation.DeliberationModulation` (tone arousal/valence thresholds; centralised in Package C).

The closure plan's Package 11 must not pretend any of these are
"calibrated" until a production-trace corpus pass has run. Until
then, the status column reads `hand-set (not calibrated)`.

## 6. Per-Self-module production-status verdict (binary)

For each `Self/*` module, the closure plan's Package 10 requires a
binary answer to: **is this module a "core runtime logic" claim today?**
The table below says yes only if the module is in the runtime path
under default flags.

| Module | "core runtime" today? | Why |
|---|---|---|
| `Self.Adjunction` | yes | consumed by `Self.Deliberation`, which is in the runtime path. |
| `Self.Blanket` | yes | guard for `IdentityRupture`. |
| `Self.Conatus` | yes | gate in `Route/Render.buildLocalRecoveryPlan`. |
| `Self.Deliberation` | yes | reconcile is the merge point. |
| `Self.Essence` | **no** | `essenceCommitmentEnabled = False` default. |
| `Self.Field` | yes | consumed by Salience. |
| `Self.Invariants` | yes (test-only assertion) | properties run on every CI. |
| `Self.Perspective` (file) | **partial** | `PerspectiveRegistry` is canonical lineage; `PerspectiveOperator` is flag-off. Replay/render reads `PerspectiveProjection` only. |
| `Self.Salience` | yes | gates narrative. |
| `Self.Types` | yes (type-only) | used everywhere. |

**This is the table that matters for Package 10 closure.** Any
documentation, README, or marketing claim that lists
`Self.Essence` or `Self.Perspective.Operator` as "core runtime
logic" is wrong.

## 7. Open items for the closure plan

1. **AGENTS.md update for `Self.Perspective` flag.** Per §3,
   `Self.Perspective` has no explicit feature flag in code today.
   The closure plan should add `QXFX0_PERSPECTIVE_OPERATOR_ENABLED`
   (or similar) so the operator's status is binary rather than
   implicit. This is a 1-line code change + AGENTS.md edit.
2. **Empirical calibration corpus.** Phase 7 completed the
   *infrastructure*; empirical calibration is unblocked only by
   a production trace corpus. Package 11 is the project to produce
   this corpus (see `CALIBRATION_BACKLOG.md`).
3. **Phase 9–10 corpus replay report.** The 25-session integration
   corpus (ADR-0012 §14) showed 0 ruptures. The closure plan's
   Package 10 verdict on Essence should be "landed, validated on
   25 sessions, awaiting 1k+ sessions promotion gate".

## 8. Acceptance criteria for Package 10 closure

- [ ] `docs/closure/SELF_LAYER_STATUS.md` (this file) is merged.
- [ ] AGENTS.md is updated to name the `Self.Perspective.Operator`
      feature flag explicitly.
- [ ] `scripts/check_architecture.sh` enforces that any new
      `Self/*` module declares its role in its module Haddock.
- [ ] The "core runtime logic" column §6 matches the actual
      runtime behaviour under default flags (i.e. CI confirms
      Essence / Family Divergence / Perspective.Operator are not
      loaded by default).
- [ ] The closure plan's Package 2 produces the typed semantic
      observation API that replaces `Core/Consciousness/Kernel/Pulse.hs`
      keyword heuristic.
