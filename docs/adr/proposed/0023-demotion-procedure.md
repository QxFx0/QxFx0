# ADR-0023 (proposed): Demotion Procedure (F-15)

- **Status**: Proposed (closure-phase follow-up F-15, Package 10
  acceptance criteria §8 alternative path)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md) §3
    (boundary rules)
  - [ADR-0036 — Promote Essence Commitment](./0036-promote-essence-commitment.md)
    (and the four sister promotion ADRs 0019–0022)
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md §3` (demotion criteria)
  - `docs/closure/AUTHORITY_MAP.md §6` (flag-off features table)
  - `docs/closure/PROMOTION_PLAYBOOK.md` (sister doc; the
    promotion counterpart)

## 1. Context

The closure plan's Package 10 requires that every flag-off
feature has **either** a promotion ADR (per F-14, the ADRs
0018–0022) **or** a demotion ADR (per F-15, this ADR's
siblings). As of 2026-06-02, no feature is being demoted; the
five promotion ADRs each reference this ADR as the
"alternative path".

A demotion is the **retirement** of a feature: the modules
that implement the feature are removed from the runtime, the
tests are retired, and the docs are updated. A demotion is
**not** the same as a flag-off default; a demotion is the
**end of the feature's life** in the project.

This ADR specifies the **procedure** for writing a
demotion ADR, plus the conditions under which a demotion
is preferred to a promotion.

## 2. Decision

### 2.1 The template

A demotion ADR has the same structure as a promotion ADR
(per ADR-0036 §1–§5), with the following differences:

1. **Title**: `00NN-demote-<feature>.md` (not `promote`).
2. **Status**: `Proposed` (same as promotion ADRs).
3. **§1 Context**: the reason for demotion, not promotion.
   The "alternatives considered" is a promotion; the
   "decision" is a demotion.
4. **§2 Decision**: the retirement plan. The plan must
   enumerate the modules to be removed, the tests to be
   retired, and the docs to be updated.
5. **§3 Consequences**: the negative side is now the
   **dominant** side (the feature is gone); the positive
   side is the architectural simplification.
6. **§4 Alternatives considered**: the promotion ADR is
   the alternative; the demotion is the chosen path.
7. **§5 Acceptance criteria**: the demotion is **closed**
   when (a) the modules are removed, (b) the tests are
   retired, (c) the docs are updated, (d) the regression
   lock is green.

### 2.2 The conditions for demotion

A demotion is preferred to a promotion when **at least
one** of the following holds:

- **D1 — no observable outcome**: the feature has no
  observable outcome in the trace, no replay-relevant
  artifact, and no production-trace evidence of use.
- **D2 — superseded**: a successor feature has replaced
  the feature; the old feature is now dead code.
- **D3 — architectural mismatch**: the feature's design
  has drifted from the architecture; the cost of bringing
  it back in line exceeds the cost of removing it.
- **D4 — empirical failure**: the promotion gate's
  criteria (G1–G4 of the relevant promotion ADR) have
  been tried and have failed repeatedly.

### 2.3 The retirement plan

A demotion ADR's retirement plan must enumerate:

1. **Modules to remove**: the source files that implement
   the feature (e.g. `Self.Essence.hs` for the essence
   demotion).
2. **Tests to retire**: the test suites that exercise the
   feature (e.g. `Test.Suite.SelfEssence` for the essence
   demotion).
3. **Trace fields to remove**: the `trcEssence*` fields
   in `TurnReplayTrace` (or analogous fields for other
   features).
4. **State fields to remove**: the `ssEssence :: Essence`
   field in `SystemState` (or analogous fields).
5. **Trace JSON compatibility**: the trace JSON must
   still be parseable; removed fields are read as `null`
   for at least one release cycle, then dropped.
6. **Architecture check rules**: any `check_architecture.sh`
   rules that were added for the feature (per F-12) are
   removed or updated.
7. **Docs to update**: `SELF_LAYER_STATUS.md`,
   `AUTHORITY_MAP.md`, `CALIBRATION_BACKLOG.md`,
   `REPLAY_GATE_TRIAGE.md`, and the relevant ADR
   (the promotion ADR's status becomes "superseded by
   demotion ADR 00NN").

### 2.4 The release event

A demotion is a release event (per the promotion ADRs'
"release event" pattern). The release notes' "Demotions"
section replaces the "Flag flips" section. The default
removal is the visible change; the env var (if any) is
**removed**, not preserved.

## 3. Consequences

### 3.1 Positive

- The architecture is simplified; dead code is gone.
- The flag-off features table (`AUTHORITY_MAP.md §6`) is
  smaller; the closure plan's "promoted or demoted"
  criterion is met for the demoted features.

### 3.2 Negative / risks

- A demotion is **irreversible** (within a release cycle);
  re-introducing a demoted feature requires a new
  design ADR, not just a flag flip.
- The trace JSON compatibility window (§2.3 item 5) is a
  one-release burden; downstream consumers must update
  within that window.

### 3.3 Mitigations

- The conditions for demotion (§2.2) are conservative; a
  feature that does not meet **at least one** of D1–D4
  should be promoted, not demoted.
- The architecture check rules (§2.3 item 6) keep the
  discipline visible; a feature that is demoted but still
  referenced is a violation that CI catches.

## 4. Alternatives considered

- **A1: Promote the feature instead.** This is the
  alternative for **every** demotion ADR. The promotion
  ADRs (0018–0022) are the cross-references.
- **A2: Keep the feature flag-off indefinitely.** This
  is the closure plan's "design complete, not executed"
  state; it is not a long-term solution because the
  flag-off features table is bounded by the
  `canonical-flag-off` class's discipline (per
  `AUTHORITY_MAP.md §2`).
- **A3: Defer the decision.** This is the default for
  features that do not yet have a promotion ADR. The
  deferral is a non-action; it is not a demotion.

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [ ] The template (§2.1) is referenced by at least one
      concrete demotion ADR (i.e. a feature is actually
      demoted using this procedure).
- [ ] The conditions for demotion (§2.2) are referenced
      in `SELF_LAYER_STATUS.md §3` and `AUTHORITY_MAP.md
      §6` as the demotion criteria.
- [ ] The retirement plan (§2.3) is referenced by the
      demotion ADR's `## 2 Decision` section.

The ADR is **deferred** until at least one of the
three criteria is met. Until then, the procedure is
**documented but unused**; the demotion path is a
**plan**, not a **practice**.

## 6. The first demotion (if any)

The first demotion candidate (if any) would be a feature
that:

- Has a promotion ADR (0018–0022) that has not closed.
- Meets one of D1–D4.

A review of the five promotion ADRs as of 2026-06-02:

| ADR | D1 | D2 | D3 | D4 | Verdict |
|---|---|---|---|---|---|
| 0018 (essence) | no | no | no | not tried | not eligible for demotion |
| 0019 (family divergence) | no | no | no | not tried | not eligible for demotion |
| 0020 (perspective operator) | no | no | no | not tried | not eligible for demotion |
| 0021 (external LLM) | no | no | no | not tried | not eligible for demotion |
| 0022 (adaptive mutation) | no | no | no | not tried | not eligible for demotion |

**No feature is eligible for demotion as of this pass.**
The demotion procedure is documented for the future.
