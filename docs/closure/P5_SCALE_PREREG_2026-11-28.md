# Pre-registration — P5-A: state-integrity scale, unit and reference (2026-11-28)

- **Status**: PRE-REGISTERED. Predictions below are written **before** the
  code change. A miss is a finding and is reported as a miss; it is not
  patched in place.
- **Owner decisions**:
  - 2026-11-27: interpretation **A** — fix the unit and the reference; change
    no threshold, no consumer, no wire key.
  - 2026-11-28: the reference definition is signed as proposed in ADR-0057 §3
    (`R0(m,c) = log1p(m) + 0.5·log1p(c)` parameterized by the installed
    resources; `R*` = measured median with provenance; no mode dependence; the
    seven floors unchanged).
- **ADR**: `docs/adr/0057-state-integrity-scale-and-reference.md`.
- **Measurement basis**: the 200-turn P4 census (degraded) and the P1 strict
  capture `p1-strict-20261128` (200 turns, strict, same corpus).

## 1. Scope of the change

| file | change |
|---|---|
| `src/QxFx0/Self/StateIntegrity.hs` | pure, total `referenceStateIntegrity :: Int -> Int -> Double` implementing `R0(m,c)`; a Haddock block stating the unit (weighted nat) and the reference |
| `src/QxFx0/Types/RuntimeRegime.hs` | `currentMathVersion` 6 → 7 with a version-7 comment marked **documentary** |
| `test/Test/Suite/SelfStateIntegrity.hs` | pins: `R0(398713,10) = 14.0949…`, `R0(0,0) = 0`, monotonicity in `m` and `c`, and a negative case proving a different `(m,c)` gives a different `R0` |
| `docs/closure/MATH_CHANGE_PROTOCOL.md` | row 7, evidence = this pre-registration + the equivalence lock |
| `docs/adr/0057-state-integrity-scale-and-reference.md` | Status Proposed → Accepted (implementation landed) |

**Not touched**: the seven thresholds, `csStability`, `lowEnergyThreshold`,
`stateIntegrityGateThreshold`, `cpStateIntegrityFloor`,
`emStateIntegrityStructuralFloor`, every wire key (`ceScalar`,
`ceComponents`, `cc*`, `cw*`, `cg*`, `trcConatusEnergy`), every snapshot, every
routing decision.

## 2. Predictions (written before the code change)

**P1 — reference arithmetic.** `referenceStateIntegrity 398713 10` equals
`14.0949` to 1e-4 (`log1p(398713) + 0.5·log1p(10)`), and
`referenceStateIntegrity 0 0 = 0`. *Reason*: the formula is the first two
terms of the functional at zero turns, zero violations, zero divergence.

**P2 — no behaviour change.** A 12-turn equivalence lock (same corpus rows,
same session ids, fresh DB per arm) produces **identical traces modulo the
per-run ignores and the version stamp**: the comparator's default ignores
(`trcRequestId`, `trcSessionId`, `trcReplayEnvelope`, `trcConatusContour`,
`trcEffectSnapshot.esCurrentTime`) plus `trcRegimeVersion`, and byte-identical
surfaces. *Reason*: the only runtime change is a constant that no branch
reads; the new function has no caller.

**P3 — the reference is not a magic number.** Changing the `(m,c)` arguments
changes `R0`; a pin computed with the wrong `m` fails. This is the red check of
ADR-0057 §6.

**P4 — the measured distribution still matches the definition.** On the P1
strict capture (pre-P5), the first turn of each dialogue has
`ccTurns = 0`, so `siScalar` equals `R0(m,c)` exactly; the 200-turn range stays
within `[R0, R0 + 0.25·log1p(10)]`. *Reason*: the functional is untouched.

**P5 — snapshots and suites.** `render_snapshots.py --check` 11/11; unit /
fast / property / integration green; docs gate green; `check_architecture.sh`
green.

## 3. Bars

| bar | condition |
|---|---|
| B1 | build green with `-Werror`, no new warnings |
| B2 | P1 arithmetic pins green, red check fails exactly the wrong-`(m,c)` pin |
| B3 | 12-turn equivalence: 0 differing trace paths outside `trcRegimeVersion` + the comparator's default per-run ignores; 12/12 surfaces identical |
| B4 | P4 distribution check green on `p1-strict-20261128` |
| B5 | snapshots 11/11; unit / fast / property / integration green |
| B6 | matrix 10/10 exit 0, tree byte-identical start→end |

## 4. Expected cost

- Code + pins: small.
- Equivalence lock: 12 turns × 2 arms × ~70 s ≈ **30 min**.
- Full matrix: the standard 10-step run (~5–6 h, detached).

## 5. Non-claims

P5-A does not calibrate the floors, does not make them reachable, and does not
claim the scalar is a measured psychological quantity. It fixes the unit and
the reference so that interpretation B can be pre-registered against a defined
scale. The 200-turn numbers are probe corpora, not samples.
