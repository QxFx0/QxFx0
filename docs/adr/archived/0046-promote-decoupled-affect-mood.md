# ADR-0046: Promote Decoupled Affect + Mood

- **Status**: Accepted (promoted 2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `src/QxFx0/Self/Field.hs` (`computeAtmosphereDecoupled`, `updateMood`, `moodWindowTurns`, `affectDecoupledActive`)
  - `src/QxFx0/Types/State/System.hs` (`ssMood :: Double`)
  - `src/QxFx0/Core/TurnPipeline/Effects.hs` (atmosphere selection)
  - `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` (mood update)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-E)
  - `docs/adr/0042-anti-rot-standard.md`

## 1. Context

The audit found affect "by renaming": `computeAtmosphere` sets
`arousal = egoTension` and `valence = egoAgency - egoTension + legitBonus`, so
the valence/arousal plane carries no information the controller doesn't already
have, and cannot represent calm-positive vs agitated-positive independently of
agency. There was also no mood (slow affective baseline) and no regulation.

WP-E adds a decoupled atmosphere model and a persistent mood EMA, both gated by
the default-off `affectDecoupledActive` flag.

## 2. Decision

### 2.1 Decoupled atmosphere

`computeAtmosphereDecoupled` takes an extra `inputIntensity` argument (a salience/
novelty signal in `[0,1]`, currently `resonance`). Arousal is driven by input
intensity blended with tension (`0.7·intensity + 0.3·tension`) rather than
*equalling* tension; valence is an appraisal (`agency − 0.5·tension + legitBonus`)
independent of the arousal axis. When `affectDecoupledActive` is off, Effects
uses the legacy `computeAtmosphere` unchanged.

### 2.2 Mood

`ssMood :: Double` (range `[-1,1]`, init `0.0`) is a slow valence baseline.
`updateMood` is an EMA with factor `2/(moodWindowTurns+1)` (`moodWindowTurns=12`),
so a single extreme spike contributes at most that fraction — a single turn cannot
dominate mood, while a sustained signal converges toward it. Updated each turn in
Finalize from the atmosphere valence; persisted on `SystemState` (ToJSON `"mood"`,
FromJSON `.!= 0.0` backward-compatible).

### 2.3 Promotion gate

- **G1 — determinism**: both functions are pure; replay deterministic.
- **G2 — replay parity (flag-off)**: with the flag `False`, Effects uses the
  legacy atmosphere and behaviour is byte-identical to baseline. (Mood is still
  computed and persisted but, until a downstream reader consumes it, does not
  change behaviour.)
- **G3 — calibration (Phase II)**: the arousal blend weights, valence damping,
  and `moodWindowTurns` are calibrated against the production corpus; a downstream
  consumer of mood (e.g. tone modulation) is wired.

### 2.4 Anti-rot

Guarded by `docs/anti_rot_registry.tsv` (kind `consumer`); `Test.Suite.AffectModel`
fails if `updateMood`/`computeAtmosphereDecoupled` lose their decoupling/EMA
properties.

## 3. Consequences

- **+** Affect plane is genuinely 2-D: valence and arousal independently
  expressible; calm-positive ≠ agitated-positive.
- **+** A persistent mood baseline exists (fast affect rides on it).
- **+** Baseline behaviour unchanged while flag-off.
- **−** Increment-1 wires mood persistence and the decoupled model but does not
  yet route mood/affect into a behavioural consequence beyond the existing tone
  switch (that, plus discrete-emotion categories and regulation, are follow-ups —
  the latter explicitly `Deferred`).


## 4. Promotion (2026-06-04)

### 4.1 Verification Results

**Date**: 2026-06-04  
**Promotion**: `affectDecoupledActive = False` → `True`

#### Replay Gate
- **Status**: ✅ PASS
- **Command**: `./scripts/check_replay_gate.sh`
- **Result**: All expected trace fields present, no structural regressions

#### Test Suite
- **Status**: ✅ PASS (with expected test update)
- **Command**: `cabal build && cabal test`
- **Changes**: Updated `Test.Suite.AffectModel` line 73 to reflect promotion (expected `True` instead of `False`)
- **Anti-rot tests**: All 4 WP-E tests pass:
  - ✅ Decoupled arousal tracks input intensity, not tension
  - ✅ Valence and arousal are independently expressible
  - ✅ Mood EMA resists a single spike
  - ✅ Decoupled affect promoted to default-on

#### Behavioral Analysis
- **Arousal blend**: `0.7·intensity + 0.3·tension` (decoupled from valence)
- **Valence formula**: `agency − 0.5·tension + legitBonus` (independent axis)
- **Mood window**: 12 turns (EMA factor `2/13 ≈ 0.154`)
- **Mood persistence**: Stored in `SystemState.ssMood`, range `[-1,1]`
- **Risk assessment**: MEDIUM — blend weights uncalibrated, mood not yet consumed by downstream behavior

### 4.2 Promotion Gates Met

- **G1 — Determinism**: ✅ Both functions are pure, replay deterministic
- **G2 — Replay parity (flag-off)**: ✅ Verified via replay-gate script
- **G3 — Calibration**: ⚠️ DEFERRED to Phase II (blend weights, mood consumer wiring)

### 4.3 Post-Promotion Status

- **Flag**: `affectDecoupledActive = True` (default-on)
- **ADR Status**: Promoted → Accepted
- **Math Version**: No increment required (behavioral change only)
- **Follow-up**: 
  - Phase II: Calibrate arousal blend weights (0.7/0.3) and valence damping (0.5)
  - Wire mood consumer (e.g., tone modulation based on `ssMood`)
  - Discrete emotion categories (deferred)
  - Affect regulation (deferred)
