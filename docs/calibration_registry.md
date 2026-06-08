# Calibration Registry

Status: Active
Purpose: single index of uncalibrated / editorially-chosen numeric constants in
the runtime, with phase binding and rationale. A number belongs here if it
influences behaviour and its current value is provisional (placeholder, "pending
calibration", or an editorial judgement not yet validated against a corpus).

Calibration source of truth, when it exists, is the F-09/F-10 production-trace
corpus. Until then these values are **deliberate placeholders**, not tuned.

## How to use

- Before changing a number below, check its phase gate. Phase-7 numbers must not
  be tuned until corpus data exists.
- When a number graduates from placeholder to calibrated, move its row to the
  "Calibrated" section with the evidence reference.
- New magic numbers added to the runtime should be registered here or carry an
  inline rationale comment.

## Field heuristics — `Self/Field.hs:294` (`defaultFieldHeuristics`)

| Constant | Value | Phase | Rationale / status |
|----------|-------|-------|--------------------|
| `fhNarrativeWindowSize` | 5 | 7 | Window length for narrative-rate estimate. Editorial. |
| `fhDefaultNarrativeRate` | 0.2 | 7 | Prior narrative rate before evidence. Placeholder. |
| `fhTopicStabilityBoost` | 0.5 | 7 | Resonance boost on stable topic. Pending empirical tuning. |
| `fhEntropyEpsilon` | 1e-9 | — | Numerical guard (not a behavioural knob). Stable. |
| `fhHolisticStreakBoostRate` | 0.05 | 7 | Per-streak holistic boost. Pending empirical tuning. |
| `fhHolisticStreakBoostCap` | 0.2 | 7 | Cap on accumulated streak boost. Pending empirical tuning. |
| `fhLegitimacyMidpoint` | 0.5 | 7 | Sigmoid midpoint for legitimacy→field. Editorial. |
| `fhLegitimacyBonusScale` | 0.4 | 7 | Legitimacy bonus scale. Pending empirical tuning. |

> **Externalized** (EXTERNALIZE-CONFIG): values are loaded from `resources/config/field_heuristics.json` at runtime; builtin defaults above are the fallback.

Additional inline Field weights (same file):
- `arousal = 0.7 * inputIntensity + 0.3 * egoTension` — affect-decoupled arousal mix. Phase 7. No corpus justification yet.
- mood EMA learning rate `lr = 0.02` per turn — editorial smoothing constant. Phase 7.

## Salience weights — `Self/Salience.hs:261` (`defaultSalienceWeights`)

| Constant | Value | Phase | Rationale / status |
|----------|-------|-------|--------------------|
| `weightAtmosphere` | 0.5 | 7 | Field atmosphere weight in salience. Editorial. |
| `weightConsolidation` | 0.75 | 7 | Consolidation weight. Editorial. |
| `weightCounterfactual` | 0.75 | 7 | Counterfactual weight. Editorial. |
| `weightFieldConfidence` | 0.5 | 7 | Field-confidence weight. Editorial. |
| `weightContentSaliency` | 0.6 | II (WP-C) | Moderate weight, **explicitly pending Phase II calibration** (inline noted). |
| `conatusGateThreshold` | 0.0 | — | Gate trips when `ceScalar < 0`; documented design choice, not placeholder. |
| `verdictThreshold` | 0.05 | — | 5% dead band each side of 0.5. Documented design choice. |

> **Externalized** (EXTERNALIZE-CONFIG): values are loaded from `resources/config/salience_weights.json` at runtime; builtin defaults above are the fallback.

Salience modulation floors (`Self/Salience.hs:308`):
- `smModulationHolisticBiasFloor = 0.6`, `smEscalationConfidenceFloor = 0.7` — editorial floors, Phase 7.

## FMAR — `Self/FamilyTargets.hs`

| Constant | Value | Phase | Rationale / status |
|----------|-------|-------|--------------------|
| `fmarDistanceThreshold` | 0.3 | — | **Deliberate** conservative affective-only profile (ADR / 2026-06-05 decision). Documented as design, not placeholder. Do not tighten pre-corpus. |

> **Externalized** (EXTERNALIZE-CONFIG): the 14 `familyTargets` are loaded from `resources/config/family_targets.json` at runtime; builtin defaults above are the fallback.

## Conatus weights — `Self/Conatus.hs:121` (`defaultConatusWeights`)

| Constant | Value | Phase | Rationale / status |
|----------|-------|-------|--------------------|
| `cwMorphology` | 1.0 | — | Editorial judgement (documented at Conatus.hs:96). Stable. |
| `cwIdentity` | 0.5 | — | Editorial. Stable. |
| `cwTurns` | 0.25 | — | Editorial. Stable. |
| `cwViolation` | 10.0 | — | Heavy violation penalty by design. Stable. |

> **Externalized** (EXTERNALIZE-CONFIG): values are loaded from `resources/config/conatus_weights.json` at runtime; builtin defaults above are the fallback.

## Bayesian likelihoods — `Core/Bayesian.hs` (gated off: `userModelActive = False`)

The entire module is dormant (WP-A, ADR-0044). Its constants are doubly
provisional — placeholder values in a flag-off subsystem.

| Site | Value(s) | Phase | Rationale / status |
|------|----------|-------|--------------------|
| `simpleTextStress` | `dCount + 0.5*nCount + 0.3*defCount` | A (ADR-0044) | Placeholder stress proxy. Uncalibrated. |
| `textLikelihood` / `likelihood` (6 intents) | base 0.05–0.1 + 0.15–0.2 * count | A (ADR-0044) | 12+ magic tuples. Placeholders pending real intent data. |

## Provisional-atom accretion — `Types/Domain/Atoms.hs`

| Constant | Value | Phase | Rationale / status |
|----------|-------|-------|--------------------|
| `defaultProvisionalAtomTTL` | 20 | — | Decay window (turns). Editorial bound. |
| `defaultProvisionalAtomMinOccurrences` | 3 | — | Promotion threshold. Editorial. |
| `defaultProvisionalAtomMinTurnSpan` | 5 | — | Promotion span. Editorial. |

## Bounded-buffer caps (not placeholders — safety bounds)

| Constant | Value | File | Status |
|----------|-------|------|--------|
| `maxQuarantineEntries` | 500 | `Learning/Guardrails.hs` | Safety cap (P1-3). Stable. |
| `maxKnowledgeQuarantineSize` | 200 | `Learning/KnowledgeTree.hs` | Safety cap. Stable. |
| `maxProvisionalAtoms` | 1000 | `Core/TurnPipeline/Finalize/State.hs` | Safety cap. Stable. |

## Calibrated

(none yet — awaiting F-09/F-10 corpus)
