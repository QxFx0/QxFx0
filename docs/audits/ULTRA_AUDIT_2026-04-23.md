# Ultra Audit — 2026-04-23

## Scope

Усиленный post-remediation audit после следующей structural wave:

1. сплит `Core.TurnPipeline.Route`
2. сплит `Bridge.Datalog`
3. повторная жёсткая верификация полного контура
4. refresh concentration baseline и остаточного `P3`-долга

Цель этого обновления: зафиксировать, что ещё два coordination-hotspot’а были разрезаны без ослабления verification contour, smoke-path и sync governance.

## Methodology

- `cabal build all`
- `cabal test qxfx0-test`
- `cabal check`
- `bash scripts/check_architecture.sh`
- `python3 scripts/verify_agda_sync.py`
- `bash scripts/verify.sh`
- `bash scripts/release-smoke.sh`
- `cabal build all --ghc-option=-Werror --ghc-option=-Wunused-binds --ghc-option=-Wunused-imports --ghc-option=-Wunused-top-binds`
- import scan for `Render ↔ Semantic`
- module/LOC rescan after remediation
- spot review of remaining concentration modules and sync-gate resilience

## Verification Evidence

- `cabal build all` -> PASS
- `cabal test qxfx0-test` -> PASS
  - current runner log: `Cases: 212`, `Errors: 0`, `Failures: 0`
- `cabal check` -> clean
- `bash scripts/check_architecture.sh` -> PASS
- `python3 scripts/verify_agda_sync.py` -> PASS
- `bash scripts/verify.sh` -> PASS (`11/11`)
- `bash scripts/release-smoke.sh` -> ACCEPT (`10/10`, `58s`)
- strict warning probe:
  - `cabal build all --ghc-option=-Werror --ghc-option=-Wunused-binds --ghc-option=-Wunused-imports --ghc-option=-Wunused-top-binds`
  - PASS

Additional structural facts after the latest wave:

- Haskell module count:
  - `src/`: `193`
  - `app/`: `8`
  - `test/`: `6`
- `src/` LOC: `17,717`
- `Render ↔ Semantic` cross-import scan:
  - `rg '^import QxFx0\.Semantic' src/QxFx0/Render` -> no matches
  - `rg '^import QxFx0\.Render' src/QxFx0/Semantic` -> no matches

## Findings

No `HIGH` or `MEDIUM` defects were confirmed in this cycle.

### LOW-1 — Concentration debt remains, but the hotspot set narrowed again

Current non-generated hotspots:

- `src/QxFx0/Types/State/System.hs` — `262 LOC`
- `src/QxFx0/Types/Observability.hs` — `255 LOC`
- `src/QxFx0/Core/Consciousness/Kernel/Pulse.hs` — `255 LOC`
- `src/QxFx0/Core/TurnPipeline/Route/Render.hs` — `254 LOC`
- `src/QxFx0/Semantic/Morphology.hs` — `251 LOC`
- `src/QxFx0/Policy/RenderLexicon.hs` — `236 LOC`
- `src/QxFx0/Types/Decision/Model.hs` — `234 LOC`
- `src/QxFx0/Resources/Paths.hs` — `231 LOC`
- `src/QxFx0/Core/Consciousness/Types.hs` — `231 LOC`
- `src/QxFx0/Bridge/AgdaWitness.hs` — `229 LOC`
- `src/QxFx0/Bridge/NativeSQLite.hs` — `226 LOC`
- `src/QxFx0/Core/Intuition.hs` — `220 LOC`
- `src/QxFx0/Semantic/Proposition.hs` — `216 LOC`
- `src/QxFx0/Bridge/Datalog/Runtime.hs` — `214 LOC`
- `src/QxFx0/Bridge/Datalog/Support.hs` — `200 LOC`
- `src/QxFx0/Core/TurnPipeline/Protocol.hs` — `194 LOC`
- `src/QxFx0/Semantic/Embedding/Runtime.hs` — `192 LOC`
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` — `191 LOC`

This is maintainability debt, not correctness debt.

The important change of this wave is that these former top-level hotspots are now closed as concentration findings:

- top-level `Core.TurnPipeline.Route`
- top-level `Bridge.Datalog`
- top-level `Semantic.Embedding`
- top-level `Runtime.Session`
- `Bridge.SQLite`
- top-level `Core.Consciousness.Kernel`
- `Policy.Consciousness`
- `Types.Decision.Enums`
- `Runtime.Wiring`
- top-level `Types.State`
- `Resources`
- `Types.Domain`

### LOW-2 — Sync governance remains resilient under repeated decomposition

This cycle reconfirmed the stronger property of the system:

1. hard-fail sync checking still works,
2. it survives another facade/submodule split wave,
3. it still blocks drift in both `verify.sh` and `release-smoke.sh`,
4. Datalog readiness and strict runtime probes still pass after bridge factoring.

This is verification-strength evidence, not just "the script still runs".

### LOW-3 — Documentation debt is now helper-level polish

The open documentation debt is now almost entirely helper-level:

1. Haddock/docstrings inside the still-largest coordination modules
2. onboarding clarity inside the remaining coordination-heavy hotspots

This is polish debt, not architectural ambiguity.

## 1. Architecture Completeness — 9.9/10

### Confirmed strengths

| Area | Status | Evidence |
|---|---|---|
| Layer boundaries | ✅ clean | `check_architecture.sh` passes all boundary checks |
| Render/Semantic separation | ✅ real | direct cross-import scan returns zero matches |
| Formal contract sync | ✅ strict | Agda sync passes and remains hard-fail in `verify.sh` |
| Parameter governance | ✅ strong | thresholds/defaults flow through thematic config and threshold modules rather than leaf-module scatter |
| Runtime layering | ✅ intact | `Core` remains isolated from `Bridge`/`Runtime`; `Runtime` remains composition root |
| Foundational module factoring | ✅ improved | `Types.State`, `Runtime.Wiring`, `Resources`, `Types.Domain`, `Policy.Consciousness`, `Types.Decision.Enums`, `Bridge.SQLite`, `Core.Consciousness.Kernel`, `Semantic.Embedding`, `Runtime.Session`, `Core.TurnPipeline.Route`, and `Bridge.Datalog` are now facades or focused submodules |
| Sync contour resilience | ✅ improved | constructor sync remains hard-fail after repeated module decomposition |
| Route-phase factoring | ✅ improved | route effect planning/resolution is now separate from route-plan assembly and render handoff |
| Datalog bridge factoring | ✅ improved | public bridge API is now separate from verdict comparison, result types, and runtime execution path |

### Before / After (latest remediation wave)

| Structural topic | Before | After |
|---|---|---|
| `Core.TurnPipeline.Route` surface | route effect planning, effect resolution, route-plan assembly, and render handoff concentrated in one module | split into `Types`, `Effects`, `Build` with thin facade |
| `Bridge.Datalog` surface | executable resolution, rule loading, comparison logic, result types, and runtime shadow execution concentrated in one module | split into `Types`, `Compare`, `Runtime` with thin facade |
| route mental model | planning and assembly logic mixed in one file | effectful route path and pure plan assembly are now distinct |
| datalog mental model | bridge API, comparison rules, and runtime execution mixed together | public API, comparison semantics, and runtime bridge path are now separated |

### Architectural nuances

1. The architecture is now clearly layered, facaded, and verification-aware.
2. Remaining large modules are concentration points, not broken boundaries.
3. The current state is best described as "architecturally mature with narrow residual hotspots".

## 2. Technical Debt — 9.9/10

### What is fully closed

- `Render ↔ Semantic` utility coupling
- giant threshold monolith
- Agda constructor sync gaps for legitimacy/trace types
- hard-fail sync gate in `verify.sh`
- session lock race
- SQLite overflow leak
- shared HTTP manager
- Agda timeout
- Datalog path fragility
- shadow penalty naming
- state/domain/decision/semantic-scene/render calibration drift
- module synopsis gaps in previously flagged foundational files
- `Bridge.Datalog` over-concentration into a single bridge/runtime/comparison module
- `Core.TurnPipeline.Route` over-concentration into a single route/effects/render-handoff module
- `Types.State` over-concentration into a single state-definition module
- `Runtime.Wiring` over-concentration into a single runtime-wiring module
- `Resources` over-concentration into a single resource/bootstrapping module
- `Types.Domain` over-concentration into a single foundational-domain module
- `Types.Decision.Enums` over-concentration into a single enum module
- `Policy.Consciousness` over-concentration into a single template/prompt module
- `Bridge.SQLite` over-concentration into a single runtime-storage module
- `Core.Consciousness.Kernel` over-concentration into a single initialization/pulse module
- `Semantic.Embedding` over-concentration into a single embedding/runtime module
- `Runtime.Session` over-concentration into a single session/runtime-shell module
- Agda sync script blind spots after decomposition

### What remains

Only `LOW` debt is confirmed:

1. concentration debt in a shorter set of remaining coordination modules
2. helper-level documentation polish inside those modules
3. optional future splits if `Types.State.System`, `Types.Observability`, `Core.TurnPipeline.Route.Render`, or `Bridge.Datalog.Runtime` continue to grow

No evidence of critical debt, failing gates, concurrency regressions, resource leaks, or boundary violations was found in this cycle.

## 3. Clockwork Precision — 9.9/10

### What runs like clockwork

1. `verify.sh` passes `11/11`
2. `release-smoke.sh` passes `10/10` in `strict` mode
3. runtime readiness reports:
   - `agda_ok: true`
   - `datalog_ok: true`
   - `ready: true`
   - `runtime_mode: strict`
4. CLI and HTTP smoke paths both complete with replay/state persistence
5. post-smoke cleanliness gate passes
6. strict warning probe with `-Werror -Wunused-*` passes
7. architecture boundary checks and Agda sync both remain in the green path
8. sync hard-gate, Datalog bridge path, and smoke contour all survived another structural split wave without regression

### Residual micro-lash

1. The automated suite remains stable at `212` observed cases; this wave improved structure more than envelope size.
2. A few coordination modules still centralize logic, so mechanical clarity is high but not yet maximally granular.
3. Unit logs may still include isolated degraded-harness noise such as `missing_witness`, but strict verification and smoke readiness close that gap explicitly.

## Scores

| Dimension | Score | Notes |
|---|---:|---|
| Architecture Completeness | 9.9/10 | boundaries, facades, and decomposition quality are now extremely strong |
| Technical Debt | 9.9/10 | only low-priority concentration and helper-doc debt remains |
| Clockwork Precision | 9.9/10 | strict gates, sync contour, Datalog bridge, and end-to-end runtime path remain fully green |
| Overall | 9.9/10 | mature runtime/research system with narrow residual polish work |

## Recommended Next Steps

1. Split one or two remaining concentration modules before they grow further:
   - `Types.State.System`
   - `Types.Observability`
   - optionally `Core.TurnPipeline.Route.Render` or `Bridge.Datalog.Runtime`
2. Add helper-level Haddock/docstrings in the largest remaining coordination modules.
3. Re-run this same audit template after the next non-trivial feature wave to ensure concentration debt does not creep back.

## Verdict

This revision of QxFx0 is no longer just "green by gates". It is structurally disciplined after repeated remediation waves, and those remediations continue to hold under strict verification.

The key conclusion of this refreshed audit is:

- the architecture is coherent,
- the sync contour survives refactoring rather than being bypassed by it,
- the parameter model is governed rather than scattered,
- the verification pipeline is real and strict,
- the remaining debt is narrow, explicit, and low-priority.

Практически это уже система уровня "часы идут ровно". Оставшееся — не спасение конструкции, а шлифовка немногих крупных шестерёнок.
