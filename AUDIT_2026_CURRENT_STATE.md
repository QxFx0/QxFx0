# QxFx0 — Аудит текущего состояния (2026-04-24)

## Executive Summary

Все критические находки предыдущих аудитов **закрыты**. Система проходит все гейты. Это уже не «система с дырами», а **система с задокументированными ограничениями**.

**Вердикт:** «Механические часы» — **да, для своей сложности**. Фазы крутятся предсказуемо, safety interlocks есть, exception handling покрыт тестами. Но это **часы с циферблатом из keyword lists**, не **часы с шестеренчатым механизмом логического вывода**.

---

## Gate Status (все green)

| Gate | Status | Detail |
|---|---|---|
| `cabal build all` | **PASS** | 0 errors, 0 warnings |
| `cabal test qxfx0-test` | **PASS** | All test suites passed |
| `bash scripts/verify.sh` | **PASS** | 13/13 checks OK, including `cabal.project.freeze` |
| `bash scripts/check_architecture.sh` | **PASS** | 10/10 checks OK |
| `bash scripts/check_lexicon.sh` | **PASS** | score=10.00, p1=3997, p2=17498, dangerous=0 |
| `bash scripts/check_generated_artifacts.sh` | **PASS** | 0 drift |
| `bash scripts/release-smoke.sh` | **PASS** | 10/10, VERDICT: ACCEPT, 893s (~15 min) |
| `bash scripts/soak.sh` | **PASS** | 100 turns, latency stable, 0 errors |
| `bash scripts/fuzz.sh` | **PASS** | 3 rounds × 200 iterations per target, no crashes |

---

## Что исправлено (FIXED) — критические находки предыдущих аудитов

| # | Находка | Где было | Как исправлено | Подтверждение |
|---|---|---|---|---|
| 1 | **SQLite pool: active transaction returned to pool** | `Pool.hs` (нет ROLLBACK) | `sanitizeForPool` делает `ROLLBACK` + `isNoActiveTransactionError` fallback | `testWithPooledDBSanitizesDirtyTransactionBeforeReuse` |
| 2 | **SQLite pool: partial init leak** | `Pool.hs` (`sequence` без cleanup) | `mapM_ safeClose acc` в `buildPoolConnections` | Code inspection |
| 3 | **SQLite pool: `withDB` only `catchIO`** | `Pool.hs` (`catchIO`) | `finally` + `tryAsync` | Code inspection |
| 4 | **MeaningGraph unbounded growth** | `MeaningGraph.hs` (no cap) | `maxEdges = 300`, `take maxEdges` | `testMeaningGraphEdgeCapProperty` (301-900 steps → ≤300 edges) |
| 5 | **Datalog no timeout** | `Datalog/Runtime.hs` | `timeout souffleTimeoutMicros` | `testDatalogShadowTimesOutWithControlledDiagnostic` |
| 6 | **Negation blindness** | `MeaningAtoms.hs` (no negation handling) | `shouldSuppressExhaustion` + `detectUnless` + `negatedExhaustionLexemes` | Code inspection |
| 7 | **Keyword collision** | `MeaningAtoms.hs` (`T.isInfixOf`) | `tokenizeKeywordText` + `containsKeywordPhrase` (token-boundary) | Code inspection |
| 8 | **Inline constants in Logic.hs** | `Logic.hs` (magic numbers) | Externalized to `Policy.SemanticScoring` | Code inspection |
| 9 | **Ad-hoc rule functions** | `Logic.hs` (12 separate functions) | `ruleTable :: [LogicRule]` structured engine | Code inspection |
| 10 | **Vocabulary gap** | ~350 words | 156 lemmas (+logic nouns), token-boundary matching | `check_lexicon.sh` score=10.00 |

### Implementation waves (2026-04-24) — новые closed findings

| Wave | Находка | Где было | Как исправлено | Подтверждение |
|---|---|---|---|---|
| 1 | **NixGuard fail-open для unsupported/unknown concepts** | `NixGuard.hs` | Fail-closed по умолчанию (`Blocked`); syntactically unsupported concepts can opt into lenient mode via `QXFX0_NIXGUARD_LENIENT_UNSUPPORTED=1`, while unknown safe keys still block | `testNixGuardUnsupportedConceptBlockedStrict`, `testNixGuardUnknownSafeConceptBlockedStrict` |
| 2 | **Недетерминированное время в replay trace** | `Pipeline.hs` (`generateRequestId`) | `TimeSource` абстракция; `QXFX0_TEST_FIXED_TIME` создаёт инкрементный fixed time | `testPersistedReplayTraceDeterministicWithFixedTimeProperty` |
| 3 | **Silent defaults при corrupt state blob** | `StatePersistence.hs` (`loadState`) | `stateBlobDiagnostics` логирует missing optional fields в stderr | `testStateBlobDiagnosticsDetectsMissingOptionalFields` |
| 4 | **SessionLock hard-coded cap = 4096** | `SessionLock.hs` | `resolveMaxTrackedLocks` читает `QXFX0_MAX_SESSION_LOCKS`; overflow логируется | `testSessionLockConfigurableCap` |
| 5 | **Отсутствие `cabal.project.freeze`** | root | `cabal freeze` сгенерирован; gate `[13]` в `verify.sh` | `verify.sh` gate `[13]` |
| 6 | **HTTP sidecar без loopback-валидации** | `Http.hs` | `isLoopbackHost` + требование `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1` | Компиляция + `release-smoke.sh` |
| 7 | **LLM plaintext HTTP API key risk** | `LLM/Provider.hs` | Remote HTTP endpoints rejected; local/private HTTP with API key rejected; local HTTP without key allowed for Ollama-style use | `testLLMRejectsInsecureRemoteHttp`, `testLLMAllowsLocalHttpWithoutApiKey` |
| 8 | **Отсутствие soak/fuzz тестов** | test suite | `scripts/soak.sh` (latency/load) + `scripts/fuzz.sh` (4 targets) | Ручной/CI запуск |
| 9 | **Shared SQLite DB между тестами** | `Test/Support.hs` | Уникальный suffix (`getPOSIXTime`) для каждого `withRuntimeEnv`/`withStrictRuntimeEnv` | `cabal test qxfx0-test` PASS |

### Lexicon Multi-Source Foundation — Phase 0–3 (2026-04-24)

| Phase | Что сделано | Ключевые файлы | Подтверждение |
|---|---|---|---|
| Phase 0 | SQL foundation: `lexicon_sources`, `lexicon_forms`, tier `CHECK` constraint; `seed_ru_curated.sql` (156 lemmas); `auto_source_manifest.json` + `seed_ru_auto.tsv` with real OpenCorpora data | `spec/sql/lexicon/schema.sql`, `spec/sql/lexicon/seed_ru_curated.sql`, `spec/sql/lexicon/auto_source_manifest.json`, `spec/sql/lexicon/seed_ru_auto.tsv` | `check_lexicon.sh` score=10.00 |
| Phase 1 | Haskell types: `LexemeForm`, `SourceTier`, `LexemeCase`, `LexemeNumber`; `MorphologyData.mdFormsBySurface`; resolver policy (`curated > auto-verified > auto-coverage`, dangerous ambiguity → raw fallback); backward-compatible `FromJSON` | `src/QxFx0/Types/Domain/Atoms.hs`, `src/QxFx0/Lexicon/Resolver.hs`, `src/QxFx0/Lexicon/Inflection.hs`, `src/QxFx0/Resources/Morphology.hs` | 10 resolver tests in `CoreBehavior.hs` + 13 tests in `LexiconTests.hs` (including 6 real-data tests: curated vs auto, P1 vs P2, cross-lemma, candidate fallback) |
| Phase 2 | `export_lexicon.py` multi-source pipeline; `forms_by_surface.json` generation; collision report (dangerous vs harmless); drift metadata; Haskell/Agda/GF generated only from curated; pilot counts: P1=200 lemmas/4426 forms, P2=800 lemmas/14541 forms, 14293 surfaces, 0 dangerous collisions, 67 expected ambiguities | `scripts/export_lexicon.py`, `resources/morphology/forms_by_surface.json`, `src/QxFx0/Lexicon/Generated.hs` | `check_generated_artifacts.sh` PASS, `release-smoke.sh` PASS |
| Phase 3 | **Auto-lexicon quality improvement:** Replaced `-len(lemma)` proxy with multi-criteria scoring (must_include → domain_seed → POS → non-proper → non-technical → non-patronymic → shorter → completeness → alpha). Added hard rejection filters, quality metrics (`lexicon_quality.json` auto_quality_metrics), and threshold enforcement in `check_lexicon.sh`. 55 Python unit tests for filter/scoring functions. | `scripts/import_ru_opencorpora.py`, `scripts/export_lexicon.py`, `scripts/check_lexicon.sh`, `test/test_import_ru_opencorpora.py` | `check_lexicon.sh` metrics: p1_mostly_proper=0, p1_long_lemma=0, p1_technical_compound=0, p2_patronymic=0, p1_domain_seed_hit=186; `cabal test` 276 PASS; `release-smoke.sh` 10/10 ACCEPT |
| Phase 3b | **Scale-step (COMPLETE):** Expanded auto-lexicon to target scale (P1=3997 lemmas/50511 forms, P2=17498 lemmas/667986 forms, 434479 surfaces). Added PRTF/PRTS participles to POS map. Fixed P2 fallback logic (`elif` → `if`) so P1-eligible lemmas missing the P1 cut-off enter P2. Relaxed proper-noun filter for domain-seed words. Compact array JSON format for `forms_by_surface.json` reduces runtime artifact from ~166 MB to ~122 MB (−26%). `FromJSON LexemeForm` supports both object and compact array formats. Runtime morphology loading uses global `MVar` cache to avoid per-worker re-parse. | `scripts/import_ru_opencorpora.py`, `scripts/export_lexicon.py`, `src/QxFx0/Types/Domain/Atoms.hs`, `src/QxFx0/Resources/Morphology.hs` | `check_lexicon.sh` metrics: p1=3997, p2=17498, dangerous=0; `cabal test` 276 PASS (0 errors, 0 failures); `release-smoke.sh` 10/10 ACCEPT; all gates green |

---

## Что остаётся (OPEN) — не критично, но задокументировано

| # | Severity | Находка | Где | Почему не критично |
|---|---|---|---|---|
| O1 | **MEDIUM** | `FromJSON` silent defaults (`.:? .!=`) | `Types/State/System.hs:157-167` | Graceful degradation при corrupt blob; `testBootstrapSessionMarksRecoveredCorruption` покрывает recovery path |
| O2 | **LOW** | `MeaningGraph.meLastRewiredAt` = `UTCTime` | `Types/Observability.hs:182` | Bounded at 300 edges; temporal drift минимален; replay tests проходят |
| O3 | **LOW** | `SessionLock` orphan leak at cap | `Core/SessionLock.hs:40,73` | Cap configurable via `QXFX0_MAX_SESSION_LOCKS`; realistic use case << default; overflow degrades to single global lock (throughput, not corruption) |
| O4 | **LOW** | `preferFamily` = unconditional override | `Core/TurnRouting/Phase.hs:94-95` | Архитектурная характеристика, не баг; `RoutingPhase` сохраняет `familyMerged` для observability |
| O5 | **LOW** | `mergeFamilySignals` = first-deviation-wins | `Core/TurnRouting/Phase.hs:88-92` | Архитектурная характеристика; 3 signals (parser/semantic/recommended) с fallback chain |
| O6 | **CLOSED** | ~~No `cabal.project.freeze`~~ | root | `cabal.project.freeze` generated; gate `[13]` in `verify.sh` (Wave 5) |
| O7 | **CLOSED** | ~~HTTP sidecar без loopback-валидации~ | `app/CLI/Http.hs` | `isLoopbackHost` + `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1` required (Wave 6) |
| O8 | **LOW** | `check_architecture.sh` regex-based | `scripts/check_architecture.sh` | 10 sub-checks consistently pass; no active bypass found |
| O9 | **INFO** | Agda sync structural not behavioral | `verify_agda_sync.py` | 14 constructors + 4 function mappings verified; behavioral correctness by test suite |
| O10 | **CLOSED** | ~~No soak/stress/fuzz tests~~ | `scripts/` | `scripts/soak.sh` + `scripts/fuzz.sh` добавлены (Wave 8) |
| O11 | **CLOSED** | ~~LLM plaintext HTTP API key risk~~ | `src/QxFx0/Bridge/LLM/Provider.hs` | `validateLLMConfig` blocks remote HTTP and local/private HTTP with non-empty API key |
| O12 | **CLOSED** | ~~Auto-lexicon pilot scale~~ | `scripts/import_ru_opencorpora.py` | Scale target reached: P1=3997/P2=17498 lemmas; quality gates enforced; `release-smoke.sh` 10/10 ACCEPT. |

---

## Слаженость «как механические часы» — оценка

### Где шестерёнки точно подогнаны

**`runFamilyCascade` — настоящий cascade.**
```haskell
familyAfterIdentity
  → familyAfterNarrative
  → familyAfterIntuition
  → familyAfterPrincipled
  → familyAfterGuard
  → familyCascade (antiStuck)
  → finalFamily (nixBlocked check)
```
Каждый уровень имеет explicit тип (`FamilyCascade`), explicit decision logic, explicit fallback. Это не «magic AI pipeline», это **mechanical decision chain**.

**`applyGuardGating` — safety interlock.**
`GuardAgencyCollapse` → `CMRepair`. `GuardHighTensionDrift` + `CMConfront` → `CMAnchor`. Это mechanical safety, not ML-based moderation.

**`TurnPipeline` record flow.**
`PrepareEffectResults` → `TurnInput` → `RouteEffectResults` → `TurnPlan` → `RenderEffectResults` → `TurnArtifacts`. Данные передаются через typed couplings.

**Exception safety теперь доказана тестами:**
- Dirty transaction → pool sanitation (`testWithPooledDBSanitizesDirtyTransactionBeforeReuse`)
- `ThreadKilled` during pool use → pool sanitation (`testWithPooledDBAsyncInterruptionSanitizesConnection`)
- Save failure → rollback (`testSaveStateWithProjectionFailureRollsBackTransaction`)
- Corrupt state → bootstrap recovery (`testBootstrapSessionMarksRecoveredCorruption`)
- Datalog hang → timeout (`testDatalogShadowTimesOutWithControlledDiagnostic`)
- MeaningGraph overflow → cap at 300 (`testMeaningGraphEdgeCapProperty`)

### Где люфт остаётся

**`preferFamily preferred _ = preferred`** — unconditional override. Но это **explicit architectural choice** (strategy predicted by `MeaningGraph` overrides merged signal), не oversight. Записано в `RoutingPhase` observability.

**`mergeFamilySignals` — first-deviation-wins.** Parser ≠ recommended → parser; semantic ≠ recommended → semantic; else recommended. Это **voting with priority**, not weighted blending. Архитектурный boundary.

**`extractObject` — first-non-stopword heuristic.** «Все люди, которые верят в свободу» → object = «люди». Не NP extraction. Это **design boundary** (keyword-based system), не баг.

---

## Scorecard

| Dimension | Score | Justification |
|---|---|---|
| **Architecture Integrity** | 8.5/10 | Phases real, boundaries enforced by gates, types strong (14×5×3×4 = 840 combos) |
| **Mechanical Cohesion** | 7.5/10 | Cascade + interlocks real, but semantic layer is keyword-flat (not compositional) |
| **Crash Consistency** | 8.0/10 | Rollback tested, corruption recovery tested, async interrupt tested, timeout tested |
| **Tech Debt** | 7.5/10 | Inline constants fixed, rule engine structured, freeze present, diagnostics added, soak/fuzz exist |
| **Operational Resilience** | 8.0/10 | Pool bounded, MeaningGraph capped (300), SessionLock configurable, loopback enforced, DB isolation per test |
| **Test Coverage** | 8.0/10 | 276 Haskell tests, 55 Python unit tests, 6 QuickCheck properties, crash/timeout/corruption covered, soak + fuzz gates present, real-data lexicon resolver covered (curated vs auto, P1/P2 tiering, dangerous collision suppression), auto-lexicon quality metrics enforced |
| **Overall** | **8.0/10** | **Система стабильна для research/dialogue use. Все 9 implementation waves (including scale-step) завершены, критические баги закрыты, остаточные риски — LOW/INFO, задокументированы.** |

---

## Финальный вердикт

> **Архитектурно крепкая, механически слаженная, эксплуатационно готова для bounded-scope use.**

Система перешла из «сильная, но хрупкая» в «крепкая с задокументированными ограничениями». Все 9 волн implementation plan выполнены; soak/fuzz gates присутствуют; DB изоляция per test обеспечена.

**Можно деплоить для:**
- Research/experimental dialogue (≤100 turns/session)
- Demonstration scenarios
- Development and iteration

**Не рекомендуется для (без доработки):**
- 24/7 production с 1000+ concurrent sessions (SessionLock overflow degrades throughput)
- Philosophical reasoning requiring compositional parsing (conditionals, quantifiers, temporal subordination) — keyword boundary, not structural

---

*Audit completed: 2026-04-25*
*All gates PASS (check_lexicon.sh, check_architecture.sh, check_generated_artifacts.sh, verify.sh, release-smoke.sh, soak.sh, fuzz.sh)*
*Zero CRITICAL findings*
*Scale-step auto-lexicon target reached: P1=3997, P2=17498, 0 dangerous collisions*
*One MEDIUM (FromJSON defaults), five LOW/INFO*
