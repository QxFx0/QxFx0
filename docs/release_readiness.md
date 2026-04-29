# QxFx0 Release Readiness (Go/No-Go)

## Scope
This checklist is the mandatory gate before any external announcement or open launch.
It focuses on production behavior, not only local green tests.

## Release Modes
- `demo`: controlled scripted demo only.
- `closed_beta`: limited external users with operator monitoring.
- `open_public`: unrestricted public access.

## Hard Blocking Gates
All items below are required for `open_public`.

1. Build/Test Gates
- `cabal test qxfx0-test -v0` passes with `Failures: 0`.
- `bash scripts/verify.sh` passes.
- `bash scripts/release-smoke.sh` passes.

2. Runtime/Environment Gates
- Strict runtime readiness is green in target environment:
  - `cabal run -v0 qxfx0-main -- --runtime-ready`
  - status must be `ok` in production profile.
- If strict is unavailable, release is limited to `closed_beta` with explicit degraded policy.

3. Dialogue Quality Gates (Russian)
- Run fixed eval set of 500 prompts + regression pack from real logs:
  - `reports/dialogue_eval_500_prompts.tsv`
  - `reports/dialogue_eval_regression_prompts.tsv`
  - one-shot gate: `bash scripts/run_release_dialogue_gate.sh`
- `intent_fit_rate >= 0.85`.
- `fallback_or_template_drift_rate <= 0.05`.
- `reflect_escape_rate <= 0.10`.
- `critical_mismatch_rate <= 0.05`.
- Zero malformed morphology in sampled outputs.

4. Routing Coverage Gates
- Must-route cases are stable:
  - `как тебя зовут`
  - `кто ты`
  - `зачем ты тут`
  - `что такое X`
  - `как отличить X от Y`
- For `X от Y`, both entities are extracted into `ipfSemanticCandidates`.

5. Observability Gates
- Daily metrics available:
  - route family distribution
  - fallback rate
  - worker restart/error rate
  - top failed prompts
- Alert thresholds configured for fallback spikes and route collapse into `CMReflect`.

## Severity Policy
- `P0`: wrong family + unsafe/empty answer + repeated template collapse.
- `P1`: intent mismatch with readable but wrong answer.
- `P2`: style/morphology issue without semantic break.

Release decision:
- Any open `P0` -> `NO-GO`.
- More than 8 open `P1` in 500-eval -> `NO-GO`.
- `P2` only -> allowed for `closed_beta`, requires backlog entry.

## Launch Decision Matrix
- `demo`: Build/Test green + smoke manual scenario pass.
- `closed_beta`: Build/Test + Runtime + partial quality (`intent_fit_rate >= 0.78`).
- `open_public`: all hard blocking gates complete.

## Execution Steps
1. Freeze commit hash and environment profile.
2. Run hard gates in order:
   - `cabal test qxfx0-test -v0`
   - `bash scripts/verify.sh`
   - `bash scripts/release-smoke.sh`
3. Run 500-prompt eval and fill report template.
4. Hold Go/No-Go review with evidence links.
5. If `GO`, tag release and publish notes with known limitations.

## Required Evidence Bundle
- test logs (`cabal test`, `verify`, `release-smoke`)
- runtime readiness output
- filled `reports/dialogue_eval_200_template.md`
- issue list for all non-zero defects
- final verdict: `GO` or `NO-GO` with timestamp and owner
