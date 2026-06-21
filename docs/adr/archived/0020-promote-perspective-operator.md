# ADR-0020 (proposed): Promote Perspective Operator

- **Status**: Proposed (closure-phase follow-up F-14, Package 10
  acceptance criteria §3)
- **Date**: 2026-06-02
- **Refines**:
  - ADR-0009 addendum (Perspective cognition as
    `OpinionCore / PerspectiveOperator` rather than a raw
    store; documented in AGENTS.md P4)
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md)
- **Related**:
  - `src/QxFx0/Self/Perspective.hs` (`PerspectiveRegistry` /
    `PerspectiveOperator` / `PerspectiveProjection`)
  - `docs/closure/SELF_LAYER_STATUS.md §4` (the flag gap)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.7` (Perspective
    contour gap)

## 1. Context

Per AGENTS.md P4, `Self.Perspective` carries:

- `PerspectiveRegistry` — the canonical versioned lineage.
- `PerspectiveOperator` — the mutation logic.
- `PerspectiveProjection` — what replay/render may consume.

The split is **already in the code**; replay/render consume
only `PerspectiveProjection`. The gap is that there is **no
explicit feature flag** (`QXFX0_PERSPECTIVE_OPERATOR_ENABLED`
does not exist). The implicit "flag" is the discipline that
replay/render consume only the projection.

This ADR has two parts:

1. **Land the flag** (`QXFX0_PERSPECTIVE_OPERATOR_ENABLED`,
   default `False`).
2. **Promote the flag** to `True` once the promotion
   criteria (G1–G3 below) are met.

## 2. Decision

### 2.1 Part 1: land the flag

A new field `perspectiveOperatorEnabled :: Bool` is added
to `QxFx0.Core.TurnPipeline.PrepareStatic` (or equivalent
parser location), with a corresponding env-var
`QXFX0_PERSPECTIVE_OPERATOR_ENABLED` (default `False`,
parsed in the same location as
`familyDivergenceEnabled` / `essenceCommitmentEnabled`).

The flag gates the **only** call site of
`PerspectiveOperator` (i.e. the call site that mutates
`PerspectiveRegistry`); the registry is append-only and
always written under the flag, but the `Operator` is
called only when the flag is on. The `Projection` is
always derived; it does not require the flag.

### 2.2 Part 2: the promotion gate

The flag flips from `False` to `True` only when **all
three** of the following hold:

- **G1 — registry lineage audit**: the
  `PerspectiveRegistry` lineage has been audited; the
  audit confirms that the registry is append-only and
  that every mutation goes through `PerspectiveOperator`
  (i.e. no direct registry writes).
- **G2 — projection coherence**: every `PerspectiveProjection`
  in the trace is derivable from the registry at snapshot
  time (the `reconstructProjection` function is total).
- **G3 — replay parity**: a fixed-fixture replay under
  `perspectiveOperatorEnabled = True` produces trace JSON
  that is **byte-identical** to the `False` baseline on
  the cases where the operator does not fire (i.e. on
  inputs that do not cross the operator's trigger).

### 2.3 The release event

When G1–G3 are met, the next release:

1. Changes the default from `False` to `True`.
2. Adds a changelog entry under the "Flag flips" section.
3. Updates `docs/closure/SELF_LAYER_STATUS.md §4` to
   remove the "no explicit feature flag" gap and to
   mark `Self.Perspective` as `production-flag-on`.
4. Updates `docs/closure/AUTHORITY_MAP.md` to mark
   `Self.Perspective` as `canonical`.

### 2.4 The follow-ups

- The `PerspectiveRegistrySnapshot` Σ-type (per
  `REPLAY_GATE_TRIAGE.md §3.2`) is part of the
  pre-promotion work, not the promotion itself. The
  promotion gate (G1–G3) is on top of the snapshot.
- The CI enforcement of "no direct
  `PerspectiveRegistry` reads in replay/render" is
  added to `check_architecture.sh` (per ADR-0034
  Rule 4).

## 3. Consequences

### 3.1 Positive

- The implicit discipline ("replay/render consume only
  the projection") becomes explicit; the flag is the
  visible lever.
- The `PerspectiveRegistry` lineage is preserved across
  flips; the projection is always derivable.

### 3.2 Negative / risks

- A misfire in `PerspectiveOperator` can corrupt the
  registry (since the registry is the canonical lineage).
  The G1 gate mitigates this but does not eliminate it.
- The `PerspectiveRegistrySnapshot` (the pre-promotion
  work) is a separate ADR; the promotion depends on it.

### 3.3 Mitigations

- The replay parity (G3) is a strong gate on fixed fixtures.
- The projection coherence (G2) is the safety net: if
  the registry is corrupt, the projection will not be
  derivable, and the gate will fail.

## 4. Alternatives considered

- **A1: Promote without the snapshot.** Rejected. The
  snapshot is the replay gate's input; without it, the
  gate cannot run.
- **A2: Demote the operator entirely.** Out of scope.
  The operator is part of the perspective cognition's
  contract; demoting it is a sister ADR (F-15, conditional).

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [ ] Part 1 is done: the flag is landed (per §2.1);
      the env-var is parsed; the only call site is gated.
- [ ] Part 2 prerequisites are done: the snapshot
      (`PerspectiveRegistrySnapshot`) is landed.
- [ ] G1, G2, G3 are met and recorded.
- [ ] The default is flipped (per §2.3).
- [ ] The release notes include the "Flag flips" entry.
- [ ] `docs/closure/SELF_LAYER_STATUS.md` and
      `docs/closure/AUTHORITY_MAP.md` are updated.
- [ ] `check_architecture.sh` rule [4-extension] is
      landed and green.

The ADR is **deferred** until all seven criteria are met.
