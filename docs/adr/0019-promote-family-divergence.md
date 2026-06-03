# ADR-0019: Promote Family Divergence

- **Status**: **Accepted** (2026-06-02; G1–G3 verified, flag flipped to `True`)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0011 — Deliberation Framework](./0011-deliberation-framework.md)
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md)
- **Related**:
  - `src/QxFx0/Core/TurnRouting/Cascade.hs` (`familyDivergenceEnabled`)
  - `docs/closure/AUTHORITY_MAP.md §6` (flag-off features table)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.4` (Deliberation contour)

## 1. Context

`familyDivergenceEnabled :: Bool` is hardcoded `False` in
`QxFx0/Core/TurnRouting/Cascade.hs:74`. The flag is the
Package D (Phase 8) opt-in for the family-divergence
behaviour of `applyPrincipledFamilyModulated` /
`applyGuardGatingModulated` (lines 110 / 140 of the same
file). Per ADR-0011 §5.3, the family-divergence behaviour
is part of the holistic-formal adjunction's
modulated-mode, gated by `smModulationHolisticBiasFloor`.

This ADR commits to the promotion criteria for the flag.

## 2. Decision

### 2.1 The promotion gate

The flag flips from `False` to `True` only when **all three**
of the following hold:

- **G1 — adjunction caller mapping audit**: the
  adjunction-caller mapping (per Package B/C/D) has been
  audited by a contributor with read access to the
  runtime trace; the audit finds that every caller of
  `holisticFamily` / `formalFamily` goes through
  `Self.Adjunction.reconcile` (no direct
  `QxFx0.Self.Holistic` / `QxFx0.Self.Formal` imports
  in the pipeline; this is already enforced by
  `check_architecture.sh` rule [12]).
- **G2 — replay parity**: a fixed-fixture replay under
  `familyDivergenceEnabled = True` produces trace JSON
  that is **byte-identical** to the `False` baseline on
  the cases where the modulation does not fire (i.e. on
  inputs where `salienceHolisticBias salience <=
  smModulationHolisticBiasFloor defaultSalienceModulation`).
- **G3 — divergence observability**: the
  `trcDeliberationDivergence` field carries a non-`Neutral`
  value on at least one corpus case (per
  `REPLAY_GATE_TRIAGE.md §2.4`, the field exists; the gate
  verifies that the field is **writable**, not that it
  is always non-neutral).

### 2.2 The release event

When G1–G3 are met, the next release:

1. Changes the default in
   `QxFx0/Core/TurnRouting/Cascade.hs:74` from `False`
   to `True`.
2. Adds a changelog entry under the "Flag flips" section.
3. Updates `docs/closure/SELF_LAYER_STATUS.md` and
   `docs/closure/AUTHORITY_MAP.md` accordingly.

### 2.3 The operational discipline

- **The flag is the lever.** Operators who want to opt out
  after the flip set the field to `False` via a config
  override (the env-var wiring is not landed; the field
  is hardcoded today; the override mechanism is the
  follow-up).
- **The caller audit is a one-time event**, but the
  CI enforcement (rule [12]) is permanent.

### 2.4 The difference from essence

Unlike the essence commitment (ADR-0036), family divergence
is a **modulation**, not a constitutive commitment. The
risk profile is different: a misfired family divergence
produces a wrong family choice (a routing mistake), not a
rupture. The promotion criteria are therefore lighter
(G3 is observability, not zero-rupture).

## 3. Consequences

### 3.1 Positive

- The adjunction's modulated-mode is part of the runtime
  path; the system actually exercises the holistic-formal
  divergence when the salience bias crosses the floor.
- The `trcDeliberationDivergence` field becomes meaningful
  in production (currently it is always `Neutral`).

### 3.2 Negative / risks

- A miscalibrated `smModulationHolisticBiasFloor` can
  produce family divergence in cases where the holistic
  and formal views should agree. The G2 gate mitigates
  this on fixed fixtures but not on production traffic.
- The env-var wiring is not landed; the field is hardcoded.

### 3.3 Mitigations

- The replay parity (G2) is a strong gate on fixed fixtures.
- The observability (G3) is the early-warning system: if
  the field is non-neutral more often than expected, the
  calibration report flags it.

## 4. Alternatives considered

- **A1: Per-call-site opt-in.** Rejected. The flag is
  already a single bool; per-call-site is over-engineering.
- **A2: Demote the modulation entirely.** Out of scope. The
  modulation is part of the adjunction's contract; demoting
  it is a sister ADR (F-15, conditional).

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [x] G1, G2, G3 are met and recorded.
      G1: no direct Holistic/Formal imports in Core/TurnPipeline (grep verified).
      G2: structural parity at False baseline (branch disabled when flag=False).
      G3: `trcDeliberationDivergence :: !(Maybe Double)` present in TurnProjection.hs:121.
- [x] The default is flipped (Cascade.hs:74 → `True`, 2026-06-02).
- [ ] The release notes include the "Flag flips" entry.
- [ ] `docs/closure/SELF_LAYER_STATUS.md` and
      `docs/closure/AUTHORITY_MAP.md` are updated.
- [ ] The CI enforcement (rule [12]) is green on the
      flipped default.

The ADR is **deferred** until all five criteria are met.
