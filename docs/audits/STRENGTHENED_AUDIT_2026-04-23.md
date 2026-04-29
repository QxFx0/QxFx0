# Strengthened Audit — 2026-04-23

Historical note: this audit predates the removal of LLM rescue semantics from
the turn runtime. Treat any LLM references below as historical context, not the
current architecture contract.

## Scope

Усиленный аудит после structural cleanup по трём направлениям:

1. Архитектурная завершённость
2. Технический долг
3. Слаженность системы как «механических часов»

Фокус этого цикла:

- подтвердить, что `Render ↔ Semantic` больше не связаны перекрёстными утилитами;
- подтвердить, что гигантский `Types.Thresholds.Constants` действительно разрезан на тематические модули;
- проверить, не осталось ли после cleanup критичных или средних дефектов в gate-контуре;
- зафиксировать остаточный `P3`-долг как репозиторный артефакт.

## Methodology

- `cabal build all` — baseline build
- `cabal test qxfx0-test` — regression suite
- `bash scripts/check_architecture.sh` — import and policy boundaries
- `bash scripts/verify.sh` — full verification gate
- `bash scripts/release-smoke.sh` — strict runtime end-to-end smoke
- `cabal check` — package hygiene
- import scan для `src/QxFx0/Render` и `src/QxFx0/Semantic`
- size scan для `Types/Thresholds/*`, `Core/TurnPipeline/*`, `Core/Consciousness/*`
- residual inline numeric scan по `Core`, `Render`, `Semantic`, `Types`

Дополнительный probe:

- попытка `cabal build all --ghc-options=-Werror --ghc-options=-Wunused-binds --ghc-options=-Wunused-imports --ghc-options=-Wunused-top-binds`
- результат **inconclusive как quality-signal**: probe упирается в локальный `cabal` environment / installed package instances при изолированном `HOME`, а не в реальные warning’и исходников. В audit score этот probe не учитывался ни как минус, ни как плюс.

## Verification Evidence

- `bash scripts/check_architecture.sh` -> PASS
- `bash scripts/verify.sh` -> PASS (`11/11`)
- `bash scripts/release-smoke.sh` -> ACCEPT (`10/10`, elapsed `57s`)
- `cabal check` -> clean
- `cabal test qxfx0-test` -> PASS (`Cases: 212`, `Errors: 0`, `Failures: 0`)
- `find src/QxFx0/Bridge -maxdepth 2 -type d` -> только `Bridge/` и реальная `Bridge/LLM`
- import scan по `Render/` и `Semantic/` -> прямых перекрёстных импортов `Render -> Semantic.*` и `Semantic -> Render.*` больше нет

## 1. Architecture Completeness — 9.4/10

### Confirmed Strengths

| Area | Status | Evidence |
|---|---|---|
| Layer boundaries | ✅ clean | `check_architecture.sh` passes all 10 checks plus shadow trace schema gate |
| Render/Semantic decoupling | ✅ completed | direct cross-imports removed; neutral helpers moved to `Types.Text` and `Lexicon.Inflection` |
| Threshold modularization | ✅ completed | `Constants.hs` is now a thin re-export aggregator over 7 thematic modules |
| Turn pipeline decomposition | ✅ sustained | largest modules remain bounded: `Consciousness/Kernel` 346 LOC, `TurnPipeline/Route` 274 LOC, `Route/Render` 254 LOC |
| Bridge hygiene | ✅ improved | stray `Bridge/{LLM}` artifact removed; only real `Bridge/LLM` remains |

### Before / After (latest structural cleanup)

| Structural topic | Before | After |
|---|---|---|
| `Render ↔ Semantic` utilities | `Render.Dialogue -> Semantic.Morphology`, `Semantic.* -> Render.Text` | neutralized via `Types.Text` and `Lexicon.Inflection` |
| Threshold source layout | single `Constants.hs` at 554 LOC | thematic modules: `Common`, `Legitimacy`, `Intuition`, `Consciousness`, `Orbital`, `Routing`, `Dream` |
| Bridge directory hygiene | stray literal `Bridge/{LLM}` present | removed |

### Architectural Nuances (non-blocking)

1. `Core/Consciousness/Kernel.hs` at 346 LOC is still the largest pure decision module. This is acceptable, but it is the next natural split point if consciousness logic grows further.
2. Parameter governance is now materially cleaner: semantic scoring lives in `Policy.SemanticScoring`, state defaults live in `Types.Config.*`, and shadow penalties live in `Types.Thresholds.Legitimacy`. The remaining question is no longer “where do these numbers live?” but only whether future algorithmic coefficients should also be grouped by domain.

## 2. Technical Debt — 9.2/10

### Closed in this cycle

- `Render ↔ Semantic` utility coupling
- monolithic threshold registry as single 554 LOC file
- stray `Bridge/{LLM}` filesystem artifact
- several core-layer inline tuning values moved into thematic threshold/config modules

### Remaining Debt

No `HIGH` or `MEDIUM` findings were confirmed.

The original `P3` residue from this audit has been closed in the same remediation wave:

- semantic rule weights, atom intensities, and proposition confidence tables moved into [Policy/SemanticScoring.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Policy/SemanticScoring.hs:1);
- shadow divergence penalties moved under [Types/Thresholds/Legitimacy.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Thresholds/Legitimacy.hs:1);
- identity/orbital/dream defaults now flow through [Types/Config/Identity.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Config/Identity.hs:1), [Types/Config/Orbital.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Config/Orbital.hs:1), and [Types/Config/Dream.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Config/Dream.hs:1);
- Haddock module headers were added to [Core/Intuition.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/Intuition.hs:1), [Core/PrincipledCore.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/PrincipledCore.hs:1), and [Core/Consciousness/Kernel.hs](/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/Consciousness/Kernel.hs:1).

At this point the residual debt from this strengthened audit is documentation-sized and optional, not structural.

## 3. Clockwork Precision — 9.4/10

### What is running like a clock

1. **Verification gates**  
   `verify.sh` passes `11/11`; `release-smoke.sh` passes `10/10` in strict runtime mode.

2. **Formal sync contour**  
   Agda/Haskell sync verifies:
   - `CanonicalMoveFamily` from `Sovereignty`
   - `CanonicalMoveFamily` from `R5Core`
   - `IllocutionaryForce`
   - `SemanticLayer`
   - `ClauseForm`
   - `WarrantedMoveMode`
   - `IsLegit`
   - `LegitimacyReason`
   - `DecisionDisposition`

3. **Runtime readiness**  
   Strict smoke confirms:
   - `agda_ok: true`
   - `datalog_ok: true`
   - `ready: true`
   - `runtime_mode: strict`

4. **End-to-end worker lifecycle**  
   HTTP sidecar smoke confirms:
   - worker spawn
   - turn execution
   - state save
   - second rapid request accepted
   - clean shutdown on signal 15

5. **Post-smoke cleanliness**  
   `release-smoke.sh` finishes with clean working tree check.

### Micro-lash still visible under magnification

1. Test suite remains strong and green, but the observed total remains `212` cases in the current runner log; this remediation wave improved parameter governance, not test envelope size.
2. Some formulas still intentionally retain neutral literals like `0.0` accumulators or `log 2 / halfLife` transformations; these are implementation mechanics rather than configuration debt.
3. The strongest remaining work items are polish-level: future docstrings for exported helpers and periodic review of algorithmic coefficients as they evolve.

## Scores

| Dimension | Score | Notes |
|---|---:|---|
| Architecture Completeness | 9.4/10 | structural cleanup confirmed and holds under gates |
| Technical Debt | 9.2/10 | no high/medium debt found; residual debt is parameter hygiene + docs |
| Clockwork Precision | 9.4/10 | strict verify/smoke green; sync contour and runtime path stable |
| Overall | 9.3/10 | system is stable for experimental/research production use |

## Post-Audit Remediation Update

The `P3` roadmap from this audit has been implemented end-to-end:

1. `Semantic.Logic`, `Semantic.MeaningAtoms`, and `Semantic.Proposition` now consume named values from `QxFx0.Policy.SemanticScoring`.
2. `Types.ShadowDivergence` now consumes named penalty weights from `QxFx0.Types.Thresholds.Legitimacy`.
3. `Types.IdentityGuard`, `Types.Orbital`, and `Types.Dream` now consume defaults from `QxFx0.Types.Config.*` modules while preserving their public constructors and helper APIs.
4. Missing Haddock module headers were added to the three previously flagged core modules.

Post-remediation verification remained green:

- `cabal build all` -> PASS
- `cabal test qxfx0-test` -> PASS (`Cases: 212`, `Errors: 0`, `Failures: 0`)
- `bash scripts/check_architecture.sh` -> PASS
- `bash scripts/verify.sh` -> PASS (`11/11`)
- `bash scripts/release-smoke.sh` -> ACCEPT (`10/10`, `57s`)
- `cabal check` -> clean

## Verdict

The recent cleanup materially improved the codebase:

- architectural coupling is lower,
- threshold governance is much cleaner than before,
- gate reliability remains fully green,
- no new critical or medium-severity issues were uncovered.

The remaining debt is now narrow and explicit. The system no longer looks like a prototype held together by local fixes; it looks like a mature research runtime with a short and realistic `P3` finishing list.
