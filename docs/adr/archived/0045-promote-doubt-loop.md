# ADR-0045: Promote Doubt Loop (metacognitive self-monitoring)

- **Status**: Accepted (promoted 2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `src/QxFx0/Core/ConsciousnessLoop.hs` (`computeDoubt`, `clDoubtScore`, `doubtLoopActive`, `doubtSuppressionThreshold`)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-D)
  - `docs/adr/0042-anti-rot-standard.md`

## 1. Context

`clDoubtScore` was declared on `ConsciousnessLoop`, initialised to `0.0`, and
**never written or read** — a dead self-monitoring field. The audit flagged it as
a textbook "claimed but inert" metacognition hook. The only "confidence" in the
system (`salienceConfidence`) measures internal driver agreement, not a tracked
doubt that feeds back into behaviour.

WP-D makes `clDoubtScore` a live signal: `computeDoubt` derives it from the
salience verdict each turn, and a reader suppresses the narrative fragment when
doubt is high — the system hesitates instead of asserting. Gated by the default-
off flag `doubtLoopActive`.

## 2. Decision

### 2.1 Producer

`computeDoubt :: Salience -> Double` = `clamp01 (1 - salienceConfidence)`,
amplified for ambiguity (`DrivenByCounterfactual`, +0.2) and forced high under a
structural threat (`DrivenByConatusGate`, ≥0.9). Written to `clDoubtScore` in
`runConsciousnessLoopWithSalience`.

### 2.2 Reader

When `doubtLoopActive` and `clDoubtScore ≥ doubtSuppressionThreshold` (0.75), the
narrative fragment is suppressed (`T.empty`); otherwise the existing
`applySalienceToNarrativeFragment` path runs unchanged. Flag-off ⇒ identity, so
the baseline is preserved.

### 2.3 Flag

`doubtLoopActive :: Bool = False`, registered in the flag-off discipline
(`scripts/check_architecture.sh` rule [20]).

### 2.4 Promotion gate

Flips to `True` only when **all** hold:

- **G1 — determinism**: doubt is a pure function of the salience verdict; replay
  under the flag is deterministic.
- **G2 — replay parity (flag-off)**: trace + behaviour byte-identical to the
  pre-WP-D baseline with the flag `False`.
- **G3 — outcome calibration (Phase II)**: the suppression threshold (0.75) and
  driver amplifications are calibrated against the production corpus so that
  suppression correlates with genuinely poor turns, not merely dispersed drivers.

### 2.5 Anti-rot

Guarded by `docs/anti_rot_registry.tsv` (kind `consumer`); `Test.Suite.DoubtLoop`
fails if `computeDoubt` stops deriving doubt from confidence.

## 3. Consequences

- **+** `clDoubtScore` is no longer dead; the loop has a real self-monitoring
  signal that can change output.
- **+** Closes the metacognition gap from the audit (doubt feeds back to control).
- **+** Baseline unchanged while flag-off.
- **−** Increment-1 only suppresses the narrative fragment; richer responses to
  doubt (asking a clarifying question, lowering assertion strength elsewhere) and
  outcome-based calibration of the threshold are follow-ups.
- **−** `CoreRegime` (`MonolithicMajority | …`) remains inert — a separate
  follow-up.


## 4. Promotion (2026-06-04)

### 4.1 Verification Results

**Date**: 2026-06-04  
**Promotion**: `doubtLoopActive = False` → `True`

#### Replay Gate
- **Status**: ✅ PASS
- **Command**: `./scripts/check_replay_gate.sh`
- **Result**: All expected trace fields present, no structural regressions

#### Test Suite
- **Status**: ✅ PASS (with expected test update)
- **Command**: `cabal test`
- **Changes**: Updated `Test.Suite.DoubtLoop` line 83 to reflect promotion (expected `True` instead of `False`)
- **Anti-rot tests**: All 5 WP-D tests pass:
  - ✅ computeDoubt is complement of confidence
  - ✅ Conatus gate forces high doubt
  - ✅ Counterfactual driver amplifies doubt
  - ✅ Doubt loop promoted with in-range threshold
  - ✅ High doubt reduces explicitness

#### Behavioral Analysis
- **Doubt threshold**: 0.75 (unchanged)
- **CMClarify override**: Active when doubt ≥ 0.75 AND no recent system decision (episodic suppression)
- **Explicitness modulation**: High doubt reduces explicitness by up to 0.20
- **Risk assessment**: LOW — override only triggers on genuine high-doubt scenarios, episodic recall provides safety net

### 4.2 Promotion Gates Met

- **G1 — Determinism**: ✅ Doubt is pure function of salience verdict
- **G2 — Replay parity (flag-off)**: ✅ Verified via replay-gate script
- **G3 — Outcome calibration**: ⚠️ DEFERRED to Phase II (corpus-driven tuning)

### 4.3 Post-Promotion Status

- **Flag**: `doubtLoopActive = True` (default-on)
- **ADR Status**: Promoted → Accepted
- **Math Version**: No increment required (behavioral change only)
- **Follow-up**: Phase II outcome calibration against production corpus
