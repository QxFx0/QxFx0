# Canonical Contour Index

**Status:** drafted 2026-06-02 (post-§11 follow-up pass)
**Purpose:** single source of truth for the 6 canonical
contours: where they live, what they compute, what
their replay-trace fields are, and what P1-P4
properties they satisfy.

This is the **complement** of `TRACE_SCHEMA.md`:

- `TRACE_SCHEMA.md` answers: "what `trc*` field
  should each contour have?"
- `CONTOUR_INDEX.md` answers: "what is each
  contour, where is it computed, and what
  property status does it have?"

The two documents cross-reference each other.

---

## 1. The 6 canonical contours

A **canonical contour** is a unit of the
`QxFx0.Self.*` runtime that participates in
replay/P1-P4 discipline. Six are currently canonical;
see `TRACE_SCHEMA.md §1` for the table.

The contours are:

| # | Contour | Self module | Replay trace | P4 status |
|---|---------|-------------|--------------|-----------|
| 1 | Conatus | `QxFx0.Self.Conatus` | (GAP) | GAP |
| 2 | Field | `QxFx0.Self.Field` | (GAP) | GAP |
| 3 | Salience | `QxFx0.Self.Salience` | 3 fields | OK |
| 4 | Deliberation | `QxFx0.Self.Deliberation` | 4 fields | OK |
| 5 | Essence | `QxFx0.Self.Essence` | 4 fields | OK |
| 6 | Identity | `QxFx0.Types.State.Identity` | (GAP) | GAP |

The 3 GAPs (Conatus, Field, Identity) are
**Package 3 work** per
`docs/closure/REPLAY_GATE_TRIAGE.md §3`.

---

## 2. Conatus

**Module:** `QxFx0.Self.Conatus`
**Type:** `ConatusEnergy` (data) and
  `ConatusComponents` (data, in `Conatus.hs`)
**Compute function:**
  `computeConatusEnergy :: TurnInput -> ConatusEnergy`
  (in `QxFx0.Core.TurnPipeline.Prepare.Build`)
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `ConatusEnergy` itself
  (P3; the data type is its own snapshot)
**trc\* fields:** (GAP) — see `TRACE_SCHEMA.md §2`
**Codomain:** `[~5, ~20+]` in production
**Calibration:** `emConatusStructuralFloor` 0.5 → 7.0
  (per ADR-0012 §15.1)
**P4 status:** GAP (3 fields expected:
  `trcConatusEnergy`, `trcConatusGateFired`,
  and 1 more for the structural floor; see
  `TRACE_SCHEMA.md §2` for the proposal)

### Why Conatus is canonical

Conatus is the aggregate of the system's "drive"
across 4 weights (`cwMorphology`, `cwIdentity`,
`cwTurns`, `cwViolation`; see
`src/QxFx0/Self/Conatus.hs:118`). It gates the
salience controller via `tiConatusGateFired`. A
turn where Conatus is below the structural floor
must be visible in the replay, otherwise
replay-driven analysis cannot reconstruct the
salience decision.

### Adjacent: the Conatus gate

`tiConatusGateFired` is a `Bool` that is `True`
when the structural floor triggers. The recovery
plan (`buildLocalRecoveryPlan` in
`Route/Render.hs`) reads this directly. It is
the only Conatus value that is currently in the
runtime path's control flow.

---

## 3. Field

**Module:** `QxFx0.Self.Field`
**Type:** `Field` (record with 5 components:
  `Resonance`, `Atmosphere`, `FieldConfidence`,
  `Consolidation`, `Counterfactual`)
**Compute function:** `combineField :: ... -> Field`
  (in `QxFx0.Core.TurnPipeline.Prepare.Build`,
  Phase 5.5d / Phase 7)
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `Field` itself
**trc\* fields:** (GAP) — see `TRACE_SCHEMA.md §3`
**P4 status:** GAP (1 field expected:
  `trcField :: !Field`)

### Why Field is canonical

Field is the right-hemispheric input to the
salience controller (per ADR-0009, ADR-0010).
Salience's `salienceHolisticBias` depends on
`fieldAtmosphere` and `fieldConsolidation`. A
replay that cannot see the Field cannot explain
the salience decision.

### Adjacent: FieldHeuristics

`QxFx0.Self.Field.FieldHeuristics` is a
**calibration struct** that lives in `Self/Field.hs`
but is not a canonical contour. The compute
functions (`computeResonance`, `computeAtmosphere`,
etc.) are pure and shown in `TRACE_SCHEMA.md §3`'s
cross-references; they are not themselves
contours.

---

## 4. Salience

**Module:** `QxFx0.Self.Salience`
**Type:** `Salience` (record with
  `SalienceDriver`, `salienceHolisticBias`,
  `salienceConfidence`)
**Compute function:** `computeSalience :: ... -> Salience`
  (in `QxFx0.Self.Salience`)
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `Salience` itself
**trc\* fields:** 3 — `trcSalienceDriver`,
  `trcSalienceHolisticBias`,
  `trcSalienceConfidence` (Phase 5.5e)
**P4 status:** OK

### Why Salience is canonical

Salience is the controller. It is the only contour
that emits the routing-family choice. Without a
`trc*` field, replay cannot explain *which* family
the system routed to.

### Calibration infrastructure

`FieldHeuristics` was extracted from Phase-5.5d
inline constants in Phase 7 (per AGENTS.md P7
section). `defaultSalienceWeights` property tests
landed in `Test.Suite.SelfField` and
`Test.Suite.SelfSalience` (2026-05-18).

---

## 5. Deliberation

**Module:** `QxFx0.Self.Deliberation`
**Type:** `DeliberationTrace` (record with
  `dtRule`, `dtAgreement`, `dtDivergence`) and
  `ReconciledPlan` (with `planNarrativeTone`)
**Compute function:** `reconcile :: ... -> ReconciledPlan`
  (in `QxFx0.Self.Deliberation`; replaces
  priority-switching in routing per ADR-0011,
  Phase 8 Package A)
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `DeliberationTrace` itself
**trc\* fields:** 4 — `trcDeliberationRule`,
  `trcDeliberationAgreement`,
  `trcDeliberationDivergence`,
  `trcDeliberationNarrativeTone` (Phase 8 Package B)
**P4 status:** OK

### Why Deliberation is canonical

Deliberation is the **adjunction caller** (per
AGENTS.md P8 Package D, corrected the caller
mapping). It is `Maybe` in the trace because
`familyDivergenceEnabled` (default `False`) is
the promotion flag — when off, deliberation is
**not in the runtime path** and the trace fields
are all `Nothing`.

### Promotion candidate

Per `docs/closure/PROMOTION_PLAYBOOK.md`, the
first candidate for promotion is **ADR-0019
(Family Divergence)**: flipping
`familyDivergenceEnabled = True` literal at
`src/QxFx0/Core/TurnRouting/Cascade.hs:74` is
the S-sized change.

---

## 6. Essence

**Module:** `QxFx0.Self.Essence`
**Type:** `Essence` (Σ-type:
  `EssenceUncommitted EssenceTrajectory`
  | `EssenceCommitted EssenceTrajectory EssenceCommitment`)
**Compute functions:** `witness`,
  `shouldCommit`, `extractMode`, `commit`
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `Essence` itself
**trc\* fields:** 4 — `trcEssenceMode`,
  `trcEssenceCommitted`, `trcEssenceAngstLevel`,
  `trcEssenceTrigger` (Phase 9-10, 2026-05-19)
**P4 status:** OK

### Why Essence is canonical

Essence is the post-turn "what mode was the
system in?" record. It is the basis for the
**Angst calibration** (per ADR-0012 §15.2,
synthetic corpora deferred to P11 backlog).

### Promotion flag

`essenceCommitmentEnabled` (default `False`).
When the flag flips, the `trcEssenceTrigger`
field becomes meaningful (in Phase 9 it is
always `Nothing`; in Phase 10 it fires on the
commitment turn).

### Calibration deferred

The `trcEssenceAngstLevel` codomain
(`[0, 1]` per the Haddock) is the calibration
target for the Angst surface. Per ADR-0012 §15.2,
calibration requires production-trace corpora;
F-09 (data) and F-10 (data) are the gating
follow-ups.

---

## 7. Identity

**Module:** `QxFx0.Types.State.Identity`
**Type:** `IdentityState` (record with
  `idsEgo`, `idsIdentityClaims`,
  `idsOrbitalMemory`, `idsLastGuardReport`)
**Compute function:** `validateClaim :: IdentityClaimRef -> IdentityState -> IdentityGuardReport`
  (in `QxFx0.Core.IdentityGuard` /
  `QxFx0.Types.IdentityGuard`)
**Pure:** yes (P2)
**Show:** yes (P1)
**Snapshot type:** `IdentityState` itself
**trc\* fields:** (GAP) — see `TRACE_SCHEMA.md §7`
**P4 status:** GAP (1 field expected:
  `trcIdentityClaims :: ![IdentityClaimRef]`)

### Why Identity is canonical

Identity claims are the substrate for
self-reference. The `ssIdentityClaims` accessor
on `SystemState` exposes the list. A replay that
cannot see which claims were active cannot
explain identity-driven decisions (e.g. the
ego-orbital memory reference in
`buildActivePerspectiveProjections`).

### Adjacent: IdentityGuard

`QxFx0.Core.IdentityGuard` is a **supplier**,
not a canonical contour. The compute function
`validateClaim` is pure (P2) and Show-deriving
(P1), but IdentityGuard is not itself canonical
because it is in the `Core/` subtree (per
ADR-0034 §3 Rule 1: `Self/*` is canonical-only).

The **Identity** contour refers to the
`IdentityState` data, not to IdentityGuard
the supplier.

---

## 8. Cross-references

- `docs/closure/TRACE_SCHEMA.md` — the schema
  reference (companion document).
- `docs/closure/REPLAY_GATE_TRIAGE.md` — the
  original triage of 13 contours; this document
  is the post-triage index for the 6 canonical.
- `docs/closure/PROMOTION_PLAYBOOK.md` — when
  a non-canonical contour (e.g. Family Divergence
  in ADR-0019) becomes canonical, the steps in
  `TRACE_SCHEMA.md §9` must be applied.
- `docs/closure/ENFORCEMENT_MATRIX.md` — the
  matrix that maps the role-split rules to
  enforcement.
- `docs/closure/AUTHORITY_MAP.md` — the
  per-module role classification (§6 has the
  flag-off table for the 5 canonical-flag-off
  features).
- `audit-round3-final.md §3.1` — the original
  Conatus codomain finding.

---

## 9. Honest limits

- This document was authored in a **read-only
  session** (no `cabal build`, no `cabal test`).
  All §N-§N.7 source references were checked
  manually. The contour list was cross-checked
  against `TRACE_SCHEMA.md §1`.
- The 3 GAPs are **real code gaps**, not
  documentation gaps. Closing them requires
  modifying `TurnReplayTrace` and updating
  3 call sites (see `TRACE_SCHEMA.md §2`, §3, §7).
- "Canonical" is defined per `ADR-0034 §3 Rule 1`
  ("`Self/*` is canonical-only"). A contour in
  `Core/` (e.g. `IdentityGuard`) is **not**
  canonical even if its compute function is
  pure; the canonical contour refers to the
  data it operates on.
- The 6 contours do **not** exhaust the Self/*
  subtree. There are 11 Self/* modules
  (Conatus, Field, Salience, Deliberation,
  Essence, Blanket, Adjunction, Perspective,
  ConatusEnergy, FieldHeuristics, Trajectory).
  The non-canonical 5 are documented in their
  respective module docs.
