# Calibration Report (QxFx0_v3) — Template

- **Status**: Active (closure-phase follow-up F-10, Package 11
  acceptance criteria §6)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/CALIBRATION_BACKLOG.md` §4
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/closure/METACOGNITION_CORPUS.md` (F-09)

## 0. What this report is

The closure plan's Package 11 requires a calibration report
that summarises each empirical calibration pass: which
parameters moved, by how much, against what corpus, with what
confidence intervals. This document is the **template** for
that report. The first pass fills it; subsequent passes
update it.

The report lives at `docs/closure/CALIBRATION_REPORT.md` and
is regenerated at every release.

## 1. Header

```markdown
# QxFx0_v3 — Calibration Report (vN)

- **report version**: vN (where N is the release number)
- **report date**: YYYY-MM-DD
- **calibration pass date**: YYYY-MM-DD
- **corpus used**: `data/metacognition_corpus/vM/` (per
  `METACOGNITION_CORPUS.md`); N labelled records
- **calibration method**: per-parameter grid search over the
  closed range; 80/20 train/hold-out split
- **summary**: [one-line summary of the pass]
```

## 2. Per-parameter results

The body of the report is a per-parameter table. Each row is
a parameter from `CALIBRATION_BACKLOG.md §2`.

```markdown
| Parameter | Old value | New value | Δ | Codomain check | Corpus hit | CI | Status |
|---|---|---|---|---|---|---|---|
| `SalienceWeights.weightResonance` | 0.4 | 0.42 | +0.02 | OK (in [0,1]) | 1024 | 0.4 ± 0.03 (95%) | empirically calibrated |
| `SalienceWeights.weightAtmosphere` | 0.3 | 0.3 | 0.0 | OK | 1024 | — | no change (hand-set) |
| ... |
```

The columns:

- **Parameter** — the fully-qualified name (e.g.
  `SalienceWeights.weightResonance`).
- **Old value** — the value before this calibration pass.
- **New value** — the value after this calibration pass.
- **Δ** — the change.
- **Codomain check** — `OK` if the new value is in the
  closed range; `WARNING: out of range` if not (this
  should not happen; the calibration pass is rejected if
  it would produce an out-of-range value).
- **Corpus hit** — the number of corpus records used in
  the calibration.
- **CI** — the 95% confidence interval on the new value
  (from the hold-out split).
- **Status** — one of:
  - `empirically calibrated` — the new value is justified
    by the corpus;
  - `no change (hand-set)` — the corpus did not support a
    change;
  - `deferred` — the corpus is insufficient (e.g. fewer
    than 100 records of the relevant type);
  - `rejected` — the calibration pass produced an
    out-of-range value or a value outside the
    confidence interval of the old value.

## 3. Per-package results

The parameters are grouped by the package that owns them
(per `CALIBRATION_BACKLOG.md §2`).

### 3.1 `Self.Salience` (P5 / ADR-0010)

| Parameter | Status | Notes |
|---|---|---|
| `weightResonance` | empirically calibrated | 0.4 → 0.42 |
| `weightAtmosphere` | no change | — |
| `weightConsolidation` | no change | — |
| `weightCounterfactual` | no change | — |
| `weightFieldConfidence` | no change | — |
| `conatusGateThreshold` | empirically calibrated | 0.85 → 0.80 (gate fires earlier) |
| `verdictThreshold` | no change | — |

### 3.2 `Self.Field` (P4 / ADR-0009)

| Parameter | Status | Notes |
|---|---|---|
| (5 component sourcing rules) | no change | corpus insufficient |

### 3.3 `Self.Essence` (P9-P10 / ADR-0012)

| Parameter | Status | Notes |
|---|---|---|
| `emConatusStructuralFloor` | already calibrated (ADR-0012 §15.1) | 0.5 → 7.0 (corrected; out of report scope) |
| `emConatusFloorWindow` | no change | corpus insufficient |
| `emAngstCommitmentThreshold` | deferred | synthetic corpus cannot produce `RuleHolisticAdvantage`/`RuleFormalAdvantage` with sufficient divergence (ADR-0012 §15.2) |
| (other angst-side) | deferred | same |

### 3.4 `Self.Deliberation` (P8 / ADR-0011)

| Parameter | Status | Notes |
|---|---|---|
| `dmToneArousalFloor` | no change | — |
| `dmToneValenceNeutral` | no change | — |

### 3.5 `Self.Conatus` (P2 / ADR-0007)

| Parameter | Status | Notes |
|---|---|---|
| `ConatusWeights.w_m` | no change | — |
| `ConatusWeights.w_c` | no change | — |
| `ConatusWeights.w_t` | no change | — |
| `ConatusWeights.λ` | no change | — |

### 3.6 `Memory.Episodic` (P7)

| Parameter | Status | Notes |
|---|---|---|
| `episodicCapacity` | no change | default 1000 |
| `episodicWindow` | no change | default 50 turns |

### 3.7 `Learning.*` (P8)

| Parameter | Status | Notes |
|---|---|---|
| Per-turn rate | no change | default 1 |
| Per-session rate | no change | default 10 |
| Rollback window | no change | default 3 |

### 3.8 `Metacognition.*` (P9)

| Parameter | Status | Notes |
|---|---|---|
| Calibration precision target | no change | default 0.85 |
| Calibration recall target | no change | default 0.70 |
| Calibration interval | no change | default 100 turns |

## 4. Per-contour results

The report also includes per-contour results from the
replay gate (Package 3):

| Contour | P1 (Serializable) | P2 (Replayable) | P3 (Reconstructable) | P4 (Trace-explainable) |
|---|---|---|---|---|
| Semantic commitments | OK | OK | OK (snapshot 12 KB) | OK |
| Episodic memory | OK | OK | OK (snapshot 64 KB) | OK |
| Learning | OK | OK | OK (snapshot 8 KB) | OK |
| Calibration | OK | OK | OK (snapshot 4 KB) | OK |
| Metacognition | OK | OK | OK (snapshot 2 KB) | OK |

## 5. The status table

At the end of the report, a status table summarises the
calibration status of every parameter in the backlog:

| Status | Count | % |
|---|---|---|
| `empirically calibrated` | 2 | 5% |
| `no change (hand-set)` | 18 | 49% |
| `deferred` | 7 | 19% |
| `rejected` | 0 | 0% |
| `already calibrated (out of scope)` | 1 | 3% |
| (parameters not yet in the backlog) | 9 | 24% |

The total is the number of parameters in
`CALIBRATION_BACKLOG.md §2` plus any new parameters added
since the backlog was last updated.

## 6. The discipline

The discipline of this report is:

- **Every parameter in the backlog gets a row.** A
  parameter that is "not yet calibrated" is in the
  `no change (hand-set)` row, not omitted.
- **The CI is the gate.** A new value is accepted only if
  the hold-out 95% CI does not include the old value.
  Otherwise, the new value is `rejected` and the old
  value stays.
- **The codomain check is the prerequisite.** A new value
  that is out of range is rejected before the CI is
  computed.
- **The status table is the summary.** The number of
  `empirically calibrated` parameters is the metric.
  Target: ≥ 50% by the third release.

## 7. The first-pass expectations

The first calibration pass is expected to:

- Move a small number of parameters (likely 1-3) from
  hand-set to empirically calibrated.
- Defer a larger number of parameters (the angst side
  per ADR-0012 §15.2 is a known deferral).
- Confirm the codomain check for every parameter (per
  ADR-0012 §15.3).
- Verify the replay gate for every contour (per Package 3).

A pass that moves zero parameters is a **flag**, not a
success: it means the corpus is insufficient or the
calibration method is not finding the structure.

## 8. Acceptance criteria for F-10

F-10 is closed when:

- [ ] The report template (this file) is merged.
- [ ] The first pass is filled (v1 of the report).
- [ ] The status table of §5 is non-empty.
- [ ] The codomain check is performed for every parameter.
- [ ] The replay gate verification (§4) is part of the
      report.

The report is **regenerated** at every release; the
template is the spec, the first pass is the baseline.
