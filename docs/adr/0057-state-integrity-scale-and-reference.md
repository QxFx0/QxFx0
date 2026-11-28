# ADR-0057: State-integrity scale — unit and reference blanket

- **Status**: Proposed (owner decisions signed 2026-11-28: interpretation A
  and the reference definition in §3; implementation pending)
- **Date**: 2026-11-28
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0045 — Conatus Gate Integration](./0045-conatus-gate-integration.md)
- **Related**:
  - `QxFx0.Self.StateIntegrity` (the functional)
  - `QxFx0.Types.Self.StateIntegrity` (carriers, frozen wire keys)
  - `QxFx0.Types.Thresholds.StateIntegrity` (weights, low-energy line)
  - `docs/closure/P5_SCOPE_MEMO_2026-11-27.md` (measurement this ADR builds on)
  - `docs/closure/P4_STATE_INTEGRITY_RESULT_2026-11-25.md` (the rename that
    froze the wire keys)

## 1. Context

`siScalar` (wire key `ceScalar`, frozen by P4) is a weighted sum of three
`log1p` terms minus a discrete violation penalty
(`src/QxFx0/Self/StateIntegrity.hs:120–137`):

```
C = 1.00·log(1+m) + 0.50·log(1+c) + 0.25·log(1+t) − 10·|violations| + divergence
```

with weights `1.0 / 0.5 / 0.25 / 10.0`
(`src/QxFx0/Types/Thresholds/StateIntegrity.hs:17–30`). The number is
persisted, traced (`trcConatusEnergy`) and consumed by `csStability`
(weight 0.20) and seven floor checks. **It has no unit and no reference.**

The 2026-11-20 owner plan asks for an `EnergyScale`/reference-blanket ADR and
a math-version bump. No symbol named `EnergyScale` exists in the tree; the
subject of the plan is this scalar.

### 1.1 Measured scale (200 turns, P4 census)

| statistic | value |
|---|---|
| min | 14.0950 |
| median | 14.5201 |
| max | 14.6706 |
| distinct values | 10 |
| `ccMorphology` (constant) | 12.8960 |
| `ccIdentity` (constant) | 1.1989 |
| `ccPenalty` / `ccSelfDivergence` | 0.0000 |

Source: `reports/eval_runs/p4-contour-20261126/capture.db`, degraded mode,
probe corpus `spec/eval/p2_baseline_2026-11-18.tsv` (sha256 `49b6d6c3…444b7`).
It is a probe, not a sample.

### 1.2 The defect

- With no violation the healthy floor is `12.8960 + 1.1989 = 14.0949`; every
  threshold ≤ 7.0 is unreachable without a violation event.
- The comment above `lowEnergyThreshold`
  (`src/QxFx0/Self/StateIntegrity.hs:187–206`) calibrates `3.0` with an example
  of "moderate morphology (e.g., 20 entries)". The installed morphology is
  ~4·10⁵ entries (`log1p ≈ 12.9`), so the worked example is off by four orders
  of magnitude.
- The scalar is discrete: the components are step functions of integer blanket
  fields, so a reference is a point on a lattice, not a continuum.

P2 and P4 measured 0/200 reachability on all seven floors; §1.2 explains why
that is a property of the scale and the corpus, not evidence that the floors
are calibrated.

## 2. Decision

**Interpretation A (owner, 2026-11-27): fix the unit and the reference; change
no threshold, no consumer, no wire key.**

1. **Unit.** One unit is one weighted nat of the `log1p` functional. Each
   component's weight is its multiplier (1.0 / 0.5 / 0.25); the penalty is 10
   units per violated invariant. The scalar is therefore measured in weighted
   nats, not in "energy".
2. **Structural reference `R0`.** `R0(m,c) = log1p(m) + 0.5·log1p(c)` — the
   scalar of a healthy blanket at turn 0 with no violations and no divergence.
   It is a function of the installed resources, **not** a global constant.
   Measured on the 2026-11-27 runtime: `m ≈ 398 713`, `c = 10`,
   `R0 = 14.0949`.
3. **Operational reference `R*`.** The measured median of the 200-turn probe
   corpus: `14.5201`, with provenance (capture id, corpus sha256, mode). It is
   re-measured in strict mode and after any weight change; it is a reference,
   not a target.
4. **Band.** `[R0, R0 + 0.25·log1p(T)]` for `T` completed turns; at `T = 10`
   this is `14.0949–14.6944` (observed max `14.6706`).
5. **Dimensionless position** `(C − R0) / (R* − R0)` is documented for
   diagnostics only. **No consumer reads it in this ADR.**
6. **Math version.** `currentMathVersion` 6 → 7 with a
   `MATH_CHANGE_PROTOCOL.md` row marked *documentary*: no constant and no
   consumed value changes; the interpretation of the existing number is what
   becomes fixed.

## 3. Reference definition (signed 2026-11-28)

The owner signed §2.2–§2.4 as proposed on 2026-11-28. The questions that were
open are resolved as follows:

| id | question | signed answer |
|---|---|---|
| Q1 | structural only, measured only, or both? | both: `R0` anchors the unit, `R*` is the operational reference with provenance |
| Q2 | is `R0` parameterized by the installed `(m,c)`? | yes — a global constant would repeat the `3.0` defect at another magnitude |
| Q3 | does the reference depend on runtime mode? | no; `R0` is a function of `(m,c)` only. Measure both modes to confirm |
| Q4 | do the seven floors change? | no (interpretation A). They stay 0.0–7.0 and are documented as reachable only through violations |

## 4. Consequences

**Changes**: this ADR; a documentation comment on the functional stating the
unit and `R0`; `currentMathVersion` 6 → 7; one row in
`MATH_CHANGE_PROTOCOL.md`.

**Does not change**: the seven thresholds, `csStability`, `lowEnergyThreshold`,
`stateIntegrityGateThreshold`, `cpStateIntegrityFloor`,
`emStateIntegrityStructuralFloor`, any wire key (`ceScalar`, `ceComponents`,
`cc*`, `cw*`, `cg*`, `trcConatusEnergy`), any snapshot, any routing decision.

**Accepted cost**: the floors remain unreachable without violations, and the
`3.0` example remains wrong in spirit until interpretation B. This ADR makes
that state explicit and measurable instead of implicit.

## 5. Alternatives

- **B — re-anchor the thresholds to `R0`.** Changes which recovery/anomaly
  branches fire. Requires its own pre-registration with predicted crossings;
  the measured reference shows the floors fire only through violations, so a
  naive re-anchor would either never fire or fire every turn.
- **C — persist a dimensionless ratio.** Changes persisted values and the
  meaning of frozen keys; P2 measured one continuous consumer, which does not
  justify a wire migration.

## 6. Verification (to be pre-registered before the code change)

1. The 200-turn census reproduces §1.1 (min/median/max, 10 distinct values).
2. Reachability stays 0/200 on all seven floors.
3. Two captures differ only in `rrMathVersion` / `trcRegimeVersion`
   (`scripts/eval/trace_equivalence.py` with the version paths ignored).
4. `render_snapshots.py --check` 11/11.
5. Unit / fast / property / integration green; docs gate green.
6. Red check: a test pinning `R0` fails if `R0` is computed from a different
   `(m,c)`, so the "reference" cannot silently become a magic number.

## 7. Non-claims

This ADR does not calibrate the floors, does not claim the scalar is a
measured psychological quantity, and does not upgrade any M6-FELT, M7,
500-prompt or release claim. The 200-turn numbers are a degraded-mode probe.
