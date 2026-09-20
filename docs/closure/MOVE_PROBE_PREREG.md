# Move-gate probe — pre-registration (2026-09-20)

## Doctrine under test (human-v1, unanimous 15/15)

A move should fire if and only if the turn degrades (rescue
semantics): all 4 unacceptable R5 turns deserved a move, all 11
acceptable ones did not — including the 3 where a move actually
fired (`mirror_state` on cal-1001/1013/1014).

## Current gate (frozen)

`moveDriftMargin = 0.10` + `negativeEvidenceEarned` (atm > 0.30 ∨
conf < 0.45) + negative ontological act. On the rated 15: 3 false
positives (fired on good turns), 4 false negatives (silent on bad
turns). F1 ≈ 0.00 as a degradation predictor (no true positives).

## Probe design

- Sample: 15 new inputs — 5 uncovered topics (abstain risk), 5
  OOV-heavy utterances (garbage risk), 5 fresh R5 distress forms.
  Fresh sessions, one turn each, traces recorded.
- Human rates `response_acceptable` (0/1) + `move_deserved` (0/1)
  blind to the trace (response text only).
- Analysis: gate's fired-vs-deserved confusion matrix on all 30
  (15 old + 15 new).

## Pre-registered decision rule

- If gate F1 < 0.50 as a degradation predictor: tighten —
  `moveDriftMargin` 0.10 → 0.20 AND require either affirm-gate
  passage or earned drift (no bare act-driven firing). Math bump
  per regime rule + full suite re-verification.
- Else: keep constants, record negative result.
- No other constant moves regardless of outcome (no fitting to
  the probe).
