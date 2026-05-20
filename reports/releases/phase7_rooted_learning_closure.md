# Release Report: Phase 7 — Rooted Learning Closure

**Date:** 2026-05-20  
**HEAD:** `489a1c3` (plus working-tree changes)  
**Branch:** `main`  
**Status:** CLOSED (Phase 7 / Rooted Learning)  
**Scope:** Endogenous Learning Architecture — WP1–WP5 + Phase-7 structural calibration infrastructure: `KnowledgeTree`, `CalibrationSignal`, dynamic tool reliability, and persistence integration.

---

## Executive Summary

Phase 7 completes the structural calibration infrastructure that was
left as residual risk in Phase 1.  The system now maintains a bounded,
inspectable `KnowledgeTree`, emits an explainable `CalibrationSignal`
instead of a hardcoded zero, and dynamically penalises external tools
that produce rejected proposals.

All changes are pure, additive, and do not weaken any existing
threshold, gate, or commitment-law contract.

**Fast tests:** 527/527 PASS (+12 from Phase-1 baseline 515)  
**Full tests:** 654/654 PASS (+12 from Phase-1 baseline 642)  
**Architecture gate:** 12/12 invariants PASS  
**GF quality gate:** 0 errors, 0 warnings PASS  
**Agda typecheck:** 6/6 modules PASS

---

## What Was Delivered

### `KnowledgeTree` — bounded epistemic structure

- `src/QxFx0/Learning/KnowledgeTree.hs`
- `KnowledgeTree` with branches, quarantine, and monotonic counters.
- `KnowledgeFruit` carries `source`, `validated`, `conatusDelta`,
  `predictiveDelta`, and turn timestamps.
- Lifecycle: `graftFruit` → `quarantineFruit` →
  `promoteFromQuarantine` → `pruneFruits` → `pruneBranches`.
- Health model: branch health drops by 0.05 per pruned fruit; branches
  below −0.5 after 3 turns are removed.
- `branchHealthTrend` exposes average health for the calibration signal.

### `CalibrationSignal` — bounded composite adaptation pressure

- `src/QxFx0/Learning/Signal.hs`
- Replaces the hardcoded `signal = 0.0` in `buildNextSystemState`.
- Four components with fixed, explainable weights:
  - Conatus trend (30 %)
  - Uncertainty trend (30 %)
  - Loop risk (20 %)
  - Inverted branch-health trend (20 %)
- All components normalised to `[-1, 1]` before weighting; final signal
  clamped to `[-1, 1]`.

### Tool reliability feedback loop

- `src/QxFx0/Learning/Tool.hs` extended with `selectToolWithReliability`
  and `updateToolReliability`.
- Dynamic reliability map overlays static `etReliability` at selection
  time; static profiles are never mutated.
- Acceptance: +0.05 (cap 1.0).  Rejection: −0.10 (floor 0.0).
- Three consecutive rejections drop a 1.0 tool to 0.70, below the
  attractiveness threshold of a fresh alternative.

### Persistence integration

- `SystemState` now carries `ssKnowledgeTree` and `ssToolReliability`
  alongside existing `ssGuardrailState` and `ssCalibrationLog`.
- All four fields have `FromJSON`/`ToJSON` with `.!=` backward-compatible
  defaults and JSON round-trip verification.
- `buildNextSystemState` wires signal computation, tree root sync,
  and pruning at the end of every turn.

### Test coverage

- `test/Test/Suite/LearningLoop.hs` — 12 new tests:
  - Graft / quarantine / promote / prune lifecycle (5 tests)
  - Calibration signal boundedness and clamping (2 tests)
  - Tool reliability rise / fall / selection override (3 tests)
  - JSON round-trip and backward compatibility (2 tests)
- Wired into `TestMain.hs`, `TestMainUnit.hs`, and `TestMainFast.hs`.
- Exported `selectToolWithReliability` and `updateToolReliability` from
  `QxFx0.Learning.Tool` to satisfy test imports.

---

## Gate Results

| Gate | Exit | Verdict | Evidence |
|------|------|---------|----------|
| `cabal build all` | 0 | PASS | 242 modules, 0 errors |
| `cabal test qxfx0-test-fast` | 0 | PASS | 527/527, 0 errors, 0 failures |
| `cabal test qxfx0-test` | 0 | PASS | 654/654, 0 errors, 0 failures |
| `check_architecture.sh` | 0 | PASS | 12 invariants OK |
| `gf_quality_gate.sh` | 0 | PASS | 0 errors, 0 warnings |
| `nix run .#typecheck-agda` | 0 | PASS | 6/6 modules |
| `check_gf_render_path.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_en_render_path.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_generated_artifacts.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_lexicon.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `ci_gate_contract.sh` aggregate | — | INFRA-DEFERRED | multi-suite orchestration exceeds local envelope |
| `release-smoke.sh` | — | INFRA-DEFERRED | extended corpus replay exceeds local envelope |
| `nix flake check` | 1 | INFRA | upstream `pgf2` broken in nixpkgs (non-blocking) |

---

## Residual Risks & Next Steps

1. ~~**Hardcoded calibration signal** — replaced by `computeCalibrationSignal`
   with bounded, explainable components.~~ **COMPLETED**.
2. **Empirical weight tuning** — the four component weights (30/30/20/20)
   are fixed for interpretability.  Production telemetry may justify
   adaptive weighting or corpus-specific tuning; deferred until trace
   corpora are available.
3. **Tool Runtime Integration** — `selectToolWithReliability` is pure;
   no actual HTTP/API call to external tools exists.  A bridge module
   (similar to `PipelineIO` for shadow/embedding) will be needed
   when a tool backend is provisioned.
4. **Simulation Substance** — `simulateProposal` is currently a stub
   that always succeeds.  Real trace-replay simulation requires
   historical turn corpora and a deterministic replay harness.
5. **Extended Contract** — `qxfx0-test-slow` and `release-smoke.sh`
   remain INFRA-DEFERRED pending a >=32 GB RAM runner.

---

## Compliance Checklist

- [x] No commitment-law contracts weakened  
- [x] No auto-patching of runtime code  
- [x] Calibration signal clamped to `[-1, 1]`  
- [x] Tool reliability capped at 1.0 and floored at 0.0  
- [x] JSON round-trip preserved for `SystemState` (backward compatible defaults)  
- [x] Architecture gate 12/12 PASS  
- [x] No bare `head`/`tail`/`init`/`last` in new source (safe alternatives used)  
- [x] `selectToolWithReliability` and `updateToolReliability` exported for tests  
- [x] `NeedTrend(..)` exported for test visibility  
- [x] `NeedNone` is the default for absent learning-need state  

---

*Report generated by release engineer.  See
`reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` for
ground-truth evidence paths.*
