# Pre-registration — P2 Conatus-consumer ablation (2026-11-18)

- **Status**: PRE-REGISTERED. Predictions below were written **before**
  the ablation arm was run. A miss is a finding and is reported as a
  miss; it is not patched in place.
- **Trigger**: the Conatus scalar (`ceScalar`) is the single quantity
  the self-layer computes every turn and threads through seven
  consumers. Its behavioural weight has never been measured. The
  self-divergence contour (A/C slices) also writes into it, so the
  question "how much does Conatus actually move the surface?" is a
  precondition for trusting any A/C-slice result.
- **Scope**: one env-gated ablation hook on the only continuous
  consumer, one equivalence-lock test, one 200-turn capture, one
  offline census. **No** constant, threshold, trace field, corpus
  lexicon, or crisis resource changes. No math-version bump (the
  ablation is a measurement hook, default-off and output-identical).
- **Owner decision**: 2026-11-18 — P2 corpus bar is "≥ 200 turns";
  the corpus was authored to exactly 200 (20 × 10).

## 1. What P2 asks

P2 asks one question:

> On a 200-turn authored corpus, does removing the Conatus scalar's
> contribution change anything a user or a downstream consumer can
> observe?

It is a **reachability + sensitivity** measurement, not a benchmark and
not a quality score.

## 2. Code census — every runtime consumer of `ceScalar`

Verified by reading the source on 2026-11-18 (HEAD `085d0b0`). The
table is the whole runtime surface; anything not listed here either
imports `ceScalar` without using it, or runs offline (calibration).

| # | Site | Kind | Threshold | Value | Fires when |
|---|---|---|---|---|---|
| 1 | `Self/Salience.hs:249` | gate | `conatusGateThreshold` (`:190`) | `0.0` | `ce < 0.0` |
| 2 | `Semantic/Stance.hs:156` | gate | `cpConatusFloor` (`Types/State/Stance.hs:194`) | `5.0` | `ce < 5.0` |
| 3 | `Core/TurnRouting/Cascade.hs:108` | gate | `lowEnergyThreshold` (`Self/Conatus.hs:213`, alias of `conatusLowEnergy`, `Types/Thresholds/Conatus.hs:34`) | `3.0` | `ce < 3.0` |
| 4 | `Core/PipelineIO/Internal.hs:58–59` | ladder | inline | `0.0`, `0.5` | `ce < 0`, `ce < 0.5` |
| 5 | `Core/FMAR.hs:120` → `Self/FamilyTargets.hs:230` | gate | `ftMinConatus` (`resources/config/family_targets.json`) | max `3.0` over 14 families | `ce < ftMinConatus` |
| 6 | `Self/Essence.hs:337–341` | gate | `emConatusStructuralFloor` (`:215`) | `7.0` | **all** of the last 8 witnesses `< 7.0` |
| 7 | `Route/Anomaly.hs:111` | gate | `anomalyAntiConatusEnergy` (`Types/Thresholds/Anomaly.hs:39`) | `5.0` | `ce < 5.0` |
| 8 | `Self/Perspective.hs:360` | **continuous** | — | — | always |

Non-consumers, verified so they are not counted as reach:

- `Semantic/Revision.hs:24` imports `ceScalar`, never uses it.
- `Learning/Need.hs:85,132` takes `conatusEnergy` and never reads it
  (the `detectLearningNeedWithPressure` parameter is dead).
- `Route/Render.hs:1320` renders the value into a trace string only.
- `Learning/CorpusExtract.hs:261`, `Learning/Loop.hs:307`,
  `Observability/TraceAnalysis.hs:277` are offline analysis/calibration.

Row 8 is the only consumer that reads the scalar **as a magnitude**
rather than comparing it to a floor:

```
csStability = clampUnit (fieldConf + min 0.25 (max 0.0 (ceScalar / 80.0)))
```

and it enters the score at `Self/Perspective.hs:574` with weight
`0.20` inside `computeNormativeAlignment`. Because the `ConatusSlice`
is built **per turn** (`assemblePerspectiveInput`, `:115`), that term
is a constant across all perspective candidates of the same turn: it
cannot reorder candidates. It can only move absolute thresholds.

Propagated sensitivity (hand-derived, `Self/Perspective.hs:129–133`):

- `∂na/∂ce = 0.20 / 80 = 0.0025` per energy unit, saturated at
  `0.20 × 0.25 = 0.05`.
- `∂conf/∂na = 0.25 − 0.20 × 0.45 = 0.16` (the `internalTension` term
  re-enters with weight `0.20` and slope `0.45`).
- hence `∂conf/∂ce = 0.0004` per energy unit, bounded by `0.008`.

## 3. Pre-measurement facts

Measured on the two existing captures (99 turns total) before this
pre-registration was written:

| corpus | n | energy min / median / max | saturated (`ce ≥ 20`, i.e. `ce/80` clamped) | `conf < 0.825` |
|---|---|---|---|---|
| `user-regime-20261113` | 80 | 14.09 / 14.47 / 14.61 | **0/80** | 100 % |
| `user-regime-probe-20261114` | 19 | 14.09 / 14.37 / 14.64 | **0/19** | 100 % |

Consequences:

1. Every threshold in rows 1–7 is **two to four times below** the
   observed scalar. None is reachable on any captured turn.
2. The continuous channel is not saturated: `ce/80 ∈ [0.176, 0.183]`.
3. The dead-channel finding (recorded separately, `P2-prep`): on all
   99 turns `trcSelfDivergencePredictionActive = False`,
   `trcSelfDivergenceTotal` is null, and `trcSelfDivergenceWindowMean`
   is null, because `Effects.hs:713–718` needs a prior observation and
   `Finalize/State.hs:791–810` writes one only when a prediction
   exists. The A-slice penalty and the C-slice `RecoverySelfDivergence`
   branch are therefore **unreachable in production**.

## 4. Design, including the A2 deviation

### 4.1 A1 — live ablation of the only continuous consumer

New default-off env hook `QXFX0_ABLATE_CONATUS_STABILITY`, read through
the existing pipeline effect boundary (`TurnReqReadEnv`, the same
mechanism as `readControlAAblation` in `Route/Build.hs:348–359`).
When set, the `ceScalar / 80.0` term in `conatusSlice`
(`Self/Perspective.hs:360`) is replaced by `0.0`; everything else —
including the recorded `trcConatusEnergy` — is unchanged.

**Equivalence lock** (hard requirement): with the variable unset the
turn must be byte-identical to the pre-hook tree, surface and full
trace. The hook is a measurement instrument, not a behaviour change.

### 4.2 A2 — redesigned: reachability census instead of a live arm

The originally planned A2 arm was a live 200-turn ablation of the
self-divergence penalty. That arm is **a no-op by construction**:
§3.3 shows the penalty is already zero on every production turn, so a
0/200 diff would measure the dead channel, not the penalty's
magnitude. Running it and reporting "no difference" would be a true
statement about nothing.

A2 is therefore replaced by a **census with a falsifiable prediction**:
on the 200 new turns the same trace fields must again show
`PredictionActive = False`, null total, null window mean, and
`trcSelfDivergencePenalty = 0.0`. If that holds, no live arm can
measure the A/C slices and the dead channel is confirmed on a third,
independent corpus. If it **fails** — i.e. a prediction appears — that
is a much more interesting finding and is reported as such.

### 4.3 S4 — threshold-reachability census

For every captured turn, compare the recorded `trcConatusEnergy`
scalar against each of the seven thresholds in §2 and record
`reachable / not reachable`. This is exact, not a reconstruction: the
scalar and the thresholds are both known.

### 4.4 S3 — sensitivity of the continuous channel

The ablation arm is compared to the baseline arm on the trace-visible
perspective fields (`trcPerspectiveProjections`: `ppOrientation`,
`ppConfidenceBand`, `ppCautionLevel`, `ppContested`) and on the
persisted `PerspectiveRegistry` lineage (version ids, `epConfidence`).
The numeric `csStability` is a local of `conatusSlice` and is **not**
trace-visible; the measurement is therefore on the derived fields,
which is where a flip would become observable.

## 5. Corpus

`spec/eval/p2_baseline_2026-11-18.tsv` — 20 dialogues × 10 turns = 200
prompts, authored for this capture (not harvested).

- sha256 `49b6d6c395f0000875cb8c3e9db6ed0fba764b08e15b323944ba4945067444b7`
- 200 rows, 200 unique prompts, contiguous turn order per dialogue.
- Protocol A only. The generator parses the acute-marker lexicon out of
  `src/QxFx0/Safety/CrisisGuard.hs` at run time (72 infix + 2 exact)
  instead of transcribing it, applies the same normalization as
  `normalizeCrisisInput`, and refuses to emit a row that matches.
- No verbatim duplicate of the 2026-11-13 or 2026-11-14 corpora.
- Pin: `Test.Suite.CrisisGuard` — "P2 baseline corpus stays in
  Protocol A" (`test/Test/Suite/CrisisGuard.hs:287–308`).

| arc | dialogues | turns | purpose |
|---|---|---|---|
| calm | 6 | 60 | definitional chains, topic continuity |
| negative | 4 | 40 | sustained negative atmosphere (atmosphere channel, not the hard gate) |
| decoy | 2 | 20 | pessimism / quotation — must stay Protocol A |
| oscillation | 2 | 20 | alternating valence, residual-window pressure |
| pileup | 1 | 10 | marker pile-up inside the contour |
| challenge | 1 | 10 | contradiction and repair path |
| practical | 1 | 10 | decision-shaped prompts |
| recovery | 1 | 10 | negative → calm trajectory |
| terse | 1 | 10 | short inputs, weak acknowledgement phrases |
| move | 1 | 10 | negative act + addressed question |

## 6. Predictions (written before measurement)

**P1 — surface identity.** 200/200 turns render a byte-identical
surface under the ablation. *Reason*: no threshold is reachable (§3.1)
and the continuous channel moves confidence by at most `0.0056`
(`0.16 × 0.20 × 14.09/80`), far below any boundary it could cross.

**P2 — perspective projection identity.** 200/200 turns have identical
`trcPerspectiveProjections`. *Reason*: the nearest boundaries are
`ppConfidenceBand` at `0.40/0.60/0.80` and admissibility at
`na < 0.25`, `conf < 0.30`, `conf ≥ 0.62 ∧ na ≥ 0.55`. A flip needs a
candidate within `0.0056` (confidence) or `0.0352` (`na`) of one of
them. The baseline corpus was not authored around those boundaries, so
the expected count is 0. **If any flip appears, it is reported with
the exact turn, candidate, field, before/after value and margin** —
that would be a genuine sensitivity datum and the headline of P2.

**P3 — routing identity.** 200/200 turns have identical
`trcFamilyDerivationChain`, `trcRecoveryCause`, `trcRecoveryStrategy`
and final family. *Reason*: rows 3, 4, 5 of §2 are `ce < 3.0` /
`ce < 0.5` / `ce < 3.0` and the observed scalar is `≈ 14`.

**P4 — registry identity.** The persisted `PerspectiveRegistry` is
identical (same version ids, same `epConfidence`) on 200/200 turns.
*Reason*: a promotion decision would have to flip first, which P2
predicts does not happen.

**P5 — full-trace identity.** With the recorded clock normalized, the
full `replay_trace_json` is identical on 200/200 turns. *Reason*:
`csStability` is not serialized, and `trcConatusEnergy` records the
true scalar in both arms by construction (§4.1).

**P6 — dead channel on a third corpus.** 200/200 turns have
`trcSelfDivergencePredictionActive = False`,
`trcSelfDivergenceTotal = null`, `trcSelfDivergenceWindowMean = null`,
`trcSelfDivergencePenalty = 0.0`. *Reason*: the channel is dead by
construction (§3.3), independent of the corpus.

**P7 — threshold census.** 0/200 turns reach any of the seven
thresholds; the minimum observed scalar stays above `7.0` (the highest
threshold, `emConatusStructuralFloor`). *Reason*: §3.1.

**P8 — baseline arm reproduces the known regime shape.** The baseline
arm shows no hard-trigger Protocol B, and any Protocol B present is a
contour exit. *Reason*: the corpus is Protocol A by pin and the encoder
is unchanged.

## 7. Bars

| bar | condition |
|---|---|
| B1 | corpus hash and row count as in §5; CrisisGuard pin green |
| B2 | equivalence lock: 12-turn leg byte-identical (surface + full trace, clock normalized) between the pre-hook tree and the flag-unset tree |
| B3 | P1: 200/200 surface identity |
| B4 | P2–P5: 200/200 identity on the listed fields |
| B5 | P6: 200/200 dead-channel census |
| B6 | P7: 0/200 threshold reachability |
| B7 | landing matrix green on the tree (unit / fast / property / integration / main runtime+http / slow groups), tree byte-identical start→end |

A bar that fails is reported as a miss with the measured values. B2 is
the only bar that must pass for the measurement to mean anything: if
the equivalence lock fails, the ablation is not an ablation and P2 is
re-run after the hook is fixed.

## 8. What P2 does not establish

- It does not show that Conatus is unimportant **in general**. It shows
  that on 200 authored turns of a local-deterministic runtime whose
  scalar sits at `≈ 14`, no threshold is reachable and the one
  continuous channel is bounded by `0.05` of one sub-score.
- It does not validate the A/C slices (self-divergence, recovery). It
  shows they are unreachable, which is the opposite of validation.
- It does not measure the effect of the scalar on the offline
  calibration path (`Learning/*`), which is not on the turn surface.
- It does not unblock the 500-prompt gate, M6-FELT, or release
  readiness.

## 9. Follow-up created by this pre-registration

The dead self-divergence channel is a real defect: a landed A/C-slice
contour cannot fire in production. Fixing it changes outputs and needs
its own pre-registration (the fix makes the penalty and the
`RecoverySelfDivergence` branch reachable, so it must predict what
changes). It is **out of P2 scope** and is recorded here so it is not
lost.
