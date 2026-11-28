# P5 — scope draft: energy scale and the reference blanket (DRAFT, 2026-11-27)

- **Status**: **DRAFT — not an ADR, not pre-registered.** On 2026-11-27 the
  owner chose **interpretation A** (§5): fix the unit and the reference, leave
  every threshold and consumer as they are. The reference definition itself
  (§4) still needs an owner signature before the ADR is written.
- **Why it exists**: P4 renamed the scalar to `StateIntegrity` and froze every
  wire key, but the number still has no unit and no reference. The 2026-11-20
  owner plan is not committed to the repository; this document reconstructs
  only the one line in the working record ("`EnergyScale`/reference blanket
  ADR, math-version bump, pre-registration") and measures what the number
  actually is.
- **Measurement basis**: the 200-turn P4 census capture
  (`reports/eval_runs/p4-contour-20261126/capture.db`, gitignored), which is
  the same corpus as the P2 baseline (`spec/eval/p2_baseline_2026-11-18.tsv`,
  sha256 `49b6d6c3…444b7`). Degraded mode, dirty tree — stated as such in the
  P4 result; it is a probe corpus, not a sample.

## 1. What the number is

`siScalar` (wire key `ceScalar`, frozen) is a weighted sum of three
`log1p` terms minus a discrete violation penalty
(`src/QxFx0/Self/StateIntegrity.hs:120–137`):

```
C = 1.00·log(1+m) + 0.50·log(1+c) + 0.25·log(1+t) − 10·|violations| + divergence
```

- `m` = `sbMorphologyTotalSize` (entries in the installed morphology resource)
- `c` = `sbIdentityClaimsCount`
- `t` = `sbTurnCount`
- weights: `src/QxFx0/Types/Thresholds/StateIntegrity.hs:17–30`
  (`1.0`, `0.5`, `0.25`, `10.0`)
- the fifth component `sicSelfDivergence` (≤ 0) is added by the prepare stage;
  the invariant `siScalar == sum of all five` holds
  (`src/QxFx0/Types/Self/StateIntegrity.hs:103–105`)

There is no unit: the three terms are weighted natural logarithms, so the
scalar is measured in **weighted nats**, and the penalty is a flat −10 per
violated invariant.

## 2. Measured distribution (200 turns, P4 census)

Extracted from `replay_trace_json` → `trace.trcConatusEnergy` (the wire key is
frozen; the Haskell field is `siScalar`):

| statistic | value |
|---|---|
| min | **14.0950** |
| q1 | 14.3696 |
| median | **14.5201** |
| q3 | 14.6148 |
| max | **14.6706** |
| mean | 14.4726 |
| distinct values | 10 |

Components (same 200 turns):

| component | min | median | max |
|---|---|---|---|
| `ccMorphology` | 12.8960 | 12.8960 | 12.8960 |
| `ccIdentity` | 1.1989 | 1.1989 | 1.1989 |
| `ccTurns` | 0.0000 | 0.4251 | 0.5756 |
| `ccPenalty` | 0.0000 | 0.0000 | 0.0000 |
| `ccSelfDivergence` | 0.0000 | 0.0000 | 0.0000 |

Two facts follow directly from the numbers:

1. **The healthy floor of the scale is not 0.** With zero violations, zero
   divergence and zero turns, the scalar is already
   `12.8960 + 1.1989 = 14.0949` — the measured minimum. The morphology term
   alone (`log1p(398 000) ≈ 12.896`) dominates the scale.
2. **The scalar is discrete.** The components are step functions of integer
   blanket fields, so the 200 turns produce 10 distinct values. A "reference"
   is therefore a point on a discrete lattice, not a continuum.

## 3. The defect the measurement exposes

The seven floor thresholds are `0.0`–`7.0`
(`Self/Salience.hs:190` gate `0.0`; `Types/State/Stance.hs:194` floor `5.0`;
`Self/Essence.hs:216` structural floor `7.0`; `Self/StateIntegrity.hs:208`
low-energy `3.0`). On the measured scale:

- **Without a violation**, every threshold ≤ 7.0 is unreachable: the healthy
  floor is 14.0949, which is twice the highest threshold. Reaching 7.0 would
  require the morphology term to fall below `7 − 1.1989 − 0.5995 ≈ 5.20`,
  i.e. fewer than ~181 morphology entries — four orders of magnitude below
  the installed resource.
- **With one violation** (−10) the scalar drops to 4.09, which is below the
  7.0 and 5.0 floors but still above the 3.0 low-energy line and the 0.0 gate;
  two violations (−20) reach −5.9 and cross all seven. So the floors are
  reachable only through violation events, and the 200-turn corpus produced
  **none** (`ccPenalty` = 0 on every turn). P2's and P4's
  "0/200 reachability" is therefore a property of the corpus as much as of the
  scale.

The code comment above `lowEnergyThreshold`
(`src/QxFx0/Self/StateIntegrity.hs:187–206`) calibrates 3.0 with an example of
"moderate morphology (e.g., 20 entries)": `log(21) ≈ 3.0`. The installed
morphology is ~4·10⁵ entries, so the worked example is off by four orders of
magnitude. This is the unit/reference defect P5 exists to name. **P5-A
documents it and does not change 3.0.**

## 4. Proposed unit and reference (needs signature)

| item | proposal |
|---|---|
| **unit** | one weighted nat of the `log1p` functional; each component's weight is the multiplier (1.0 / 0.5 / 0.25), the penalty is 10 units per violated invariant |
| **structural reference R0** | `C` of a healthy blanket at turn 0 with no violations and no divergence: `R0(m,c) = log1p(m) + 0.5·log1p(c)`. It is a function of the installed resources, **not** a global constant. Measured here: **14.0949** (`m ≈ 398 000`, `c = 10`) |
| **operational band** | `[R0, R0 + 0.25·log1p(T)]` for `T` completed turns; at `T = 10` the band is **14.0949–14.6944** (observed max 14.6706) |
| **reference point R\*** | measured median of the 200-turn corpus: **14.5201**; provenance = this capture, to be re-measured in strict mode and after any weight change |
| **dimensionless position** | `(C − R0) / (R* − R0)` — documented for diagnostics only, **no consumer reads it** in P5-A |

The reference is deliberately parameterized by `(m, c)`: a different install
(a smaller lexicon, a different identity-claim count) has a different R0, and
a global constant would repeat the 3.0 defect at a different magnitude.

## 5. Owner decision this implements (2026-11-27)

**Interpretation A**: fix the unit and the reference, leave the numeric
thresholds and every consumer as they are; `currentMathVersion` bumps because
the interpretation is now fixed, even though no consumed value changes.

Rejected for now:

- **B — re-anchor the thresholds.** The measured reference shows the floors
  fire only through violation events, so re-anchoring would change *which*
  recovery/anomaly branches fire; that is a behaviour change and needs its own
  pre-registration with predicted crossings.
- **C — dimensionless ratio as the persisted value.** Changes persisted values
  and the meaning of the frozen keys; P2 measured only one continuous
  consumer, which does not justify the migration.

## 6. Verification plan (to be pre-registered before the code change)

The change is documentary plus one version stamp, so the predictions are
strong and cheap to falsify:

1. **P1 — distribution unchanged**: the 200-turn census reproduces §2
   (min 14.0950, median 14.5201, max 14.6706, 10 distinct values).
2. **P2 — reachability unchanged**: 0/200 on all seven floors.
3. **P3 — trace identity modulo the version stamp**: two captures on the same
   corpus differ only in `rrMathVersion` / `trcRegimeVersion`; every other
   trace path is identical. The comparator is `scripts/eval/trace_equivalence.py`
   with the version paths on its explicit ignore list.
4. **P4 — snapshots unchanged**: `render_snapshots.py --check` 11/11.
5. **P5 — suites green**: unit / fast / property / integration, plus a
   docs-gate run.
6. **Red check**: pinning the new reference in a test must fail if R0 is
   computed from a different `(m, c)` — otherwise the "reference" is just a
   magic number.

Files touched by P5-A: one ADR (new), one row in `MATH_CHANGE_PROTOCOL.md`,
the `currentMathVersion` constant, and comments documenting R0/the unit. No
threshold, no consumer, no wire key, no snapshot.

## 7. Remaining open decisions

| id | question | recommendation |
|---|---|---|
| P5-Q2 | Is R0 (structural, parameterized) enough, or is R\* (measured median) also part of the ADR? | document both, use R0 as the unit anchor and R\* as the operational reference with provenance |
| P5-Q3 | Does the reference depend on runtime mode (strict/degraded)? | no: R0 is a function of `(m, c)` only; mode affects behaviour, not the scale. Measure both modes to confirm |
| P5-Q5 | What closes P5? | §6 P1–P5 green plus the ADR merged; no threshold change is claimed |
| P5-Q6 | Wire keys? | untouched; `ceScalar`/`ceComponents` stay frozen (P4-A) |

## 8. Non-claims

- This document does not define the scale until §4 is signed, chooses no
  threshold, and changes no behaviour.
- The 200-turn numbers are a degraded-mode probe corpus, not a sample and not
  production evidence.
- It does not upgrade any M6-FELT, M7, 500-prompt or release claim; the
  500-prompt gate stays **BLOCKED**.
