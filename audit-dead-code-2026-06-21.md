# Dead Code / Disabled Modules / Obsolete Architectural Decisions Audit

**Date:** 2026-06-21  
**Scope:** QxFx0 — поиск мёртвого кода, отключённых модулей, устаревших архитектурных решений

---

## Резюме

| Категория | Кол-во элементов | LOC / файлов |
|---|---|---|
| Truly dead Haskell modules | 4 | 199 LOC |
| Dead Thresholds sub-modules | 5 | 574 LOC |
| Duplicate Proposition*Admission types | 23 файла | 799 LOC (дубликат) |
| Dead Python scripts | 23 | 13 495 LOC |
| ADR proposed but never accepted | 19 | 19 файлов |
| Old reports (baseline_v2/final_gates) | — | 118 файлов |
| Stubs/placeholders in Haskell | ~45 refs | — |
| **Итого мёртвого/дублирующего кода** | — | **~15 067 LOC** |

---

## 1. Truly Dead Haskell Modules (никем не импортируются)

Четыре модуля не импортируются ни одним другим модулем в `src/` или `test/`:

| Модуль | LOC | Описание |
|---|---|---|
| `QxFx0.Bridge.EmbeddedSQLSync` | 76 | Синхронизация embedded SQL — функциональность не подключена |
| `QxFx0.Render.Text` | 32 | Текстовый рендеринг — не используется |
| `QxFx0.Self.MeaningDirective` | 19 | Директива смысла — не используется |
| `QxFx0.Semantic.AuthorityParse` | 72 | Парсинг авторитета — не используется |

**Рекомендация:** удалить. Эти модули компилируются, включены в cabal `exposed-modules`, но не вызываются.

---

## 2. Dead Thresholds Sub-modules (не реэкспортируются родителем)

`Types/Thresholds.hs` реэкспортирует только `Thresholds.Types` и `Thresholds.Constants`. Пять подмодулей не подключены:

| Модуль | LOC | Импортируется? |
|---|---|---|
| `Thresholds.Consciousness` | 126 | 0 ссылок |
| `Thresholds.Intuition` | 126 | 0 ссылок |
| `Thresholds.Dream` | 74 | 0 ссылок |
| `Thresholds.Common` | 118 | 0 ссылок |
| `Thresholds.Orbital` | 130 | 0 ссылок |

**Итого: 574 LOC мёртвого кода.** Эти модули содержат пороги для подсистем (Consciousness, Intuition, Dream, Orbital), которые документированы как `flag-off` / `canonical-flag-off`, но никогда не были включены.

**Рекомендация:** удалить или подключить через реэкспорт родителя, если подсистемы планируются к активации.

---

## 3. Duplicate Proposition*Admission Types

**Критическая находка:** 23 типа `Proposition*Admission` существуют в **двух копиях**:

- `Types/Proposition*Admission.hs` — 23 файла, 799 LOC (старая версия, в корне Types/)
- `Types/Admission/Proposition*Admission.hs` — 24 файла, 1039 LOC (новая версия, в Types/Admission/)

Оба набора импортируются разными модулями:
- `Types.Proposition*Admission` ← `Semantic.Proposition`, `Semantic.Proposition.Detectors`, `Semantic.Proposition.Types`, `Semantic.Proposition.Semantic`, тесты
- `Types.Admission.Proposition*Admission` ← `Core.TurnPipeline.Effects`, `Semantic.Proposition.Detectors`, тесты

`Semantic.Proposition.Detectors` импортирует **оба набора одновременно** — это архитектурный дубль, создающий риск рассинхронизации типов.

**Рекомендация:** унифицировать в один набор (оставить `Types/Admission/`), удалить дубликаты из `Types/` root.

---

## 4. Dead Python Scripts (не используются в build/CI)

Из 36 Python-скриптов в `scripts/` **23 не вызываются** ни из shell-скриптов, ни из CI, ни из Makefile/cabal:

| Скрипт | LOC | Назначение |
|---|---|---|
| `expand_en_lexicon.py` | 3369 | Расширение английского лексикона |
| `expand_ru_lexicon.py` | 1478 | Расширение русского лексикона |
| `import_ru_opencorpora.py` | 922 | Импорт OpenCorpora |
| `wave3_soak.py` | 1268 | Soak-тест wave 3 |
| `wave4_soak.py` | 1242 | Soak-тест wave 4 |
| `wave5_soak.py` | 1080 | Soak-тест wave 5 |
| `select_lemmas_20k.py` | 425 | Выбор 20k лемм |
| `add_verbs_adjs_to_paradigms.py` | 342 | Добавление глаголов/прилагательных |
| `import_brain_kb.py` | 356 | Импорт Brain KB |
| `expand_lexicon.py` | 350 | Расширение лексикона |
| `add_nouns_to_paradigms.py` | 270 | Добавление существительных |
| `run_blind_ab_eval.py` | 268 | A/B evaluation |
| `validate_paradigms.py` | 265 | Валидация парадигм |
| `score_blind_pairs.py` | 274 | Оценка blind pairs |
| `l3e0_baseline_parity.py` | 274 | Baseline parity |
| `generate_parity_report.py` | 280 | Отчёт parity |
| `generate_paradigms_pymorphy2.py` | 207 | Генерация парадигм (pymorphy2) |
| `generate_gf_from_tsv.py` | 169 | Генерация GF из TSV |
| `generate_haskell_from_tsv.py` | 138 | Генерация Haskell из TSV |
| `top_up_ru_lexicon.py` | 143 | Пополнение русского лексикона |
| `sync_embedded_sql.py` | 101 | Синхронизация SQL |
| `generate_paradigms_from_lexicon.py` | 144 | Генерация парадигм |
| `compute_ab_metrics.py` | 130 | A/B метрики |

**Итого: 13 495 LOC мёртвого Python-кода.**

Используемые скрипты (13): `http_runtime.py` (10 ссылок), `check_runtime_contract.py` (7), `check_concepts_schema.py` (7), `export_lexicon.py` (6), `verify_agda_sync.py` (4), `check_schema_consistency.py` (3), `check_schema_contract.py` (3), `wave2_soak.py` (3), `check_input_lexicon.py` (2), `check_replay_trace_fields.py` (2), `build_input_lexicon.py` (1), `check_gf_concrete_consistency.py` (1).

**Рекомендация:** переместить неиспользуемые скрипты в `scripts/archive/` или удалить. Особенно wave3/4/5 soak-тесты (3590 LOC) — они были разовыми тестами и больше не нужны.

---

## 5. Disabled / Flag-off Features

### 5.1 ExternalLLM — default disabled

`Bridge/ExternalLLM.hs` имеет `eqcTransportMode = "disabled"` по умолчанию. Транспорт активируется только через `QXFX0_LLM_TRANSPORT` env var. Импортируется только `Runtime.Wiring.Handlers` — функциональность подключена, но по умолчанию выключена.

### 5.2 Bayesian — flag-off discipline

`Core/Bayesian.hs` документирован как `flag-off` (ADR-0013 Rule 6). Импортируется `Core.Intuition`, `Core.TurnPipeline.Finalize.State`, `Core.TurnPipeline.Finalize.Projection`. Код вызывается, но `userModelActive` возвращает `False` в flag-off режиме — Bayesian update выполняется, но результат не используется.

### 5.3 ConsciousnessLoop — flag-off discipline

`Core/ConsciousnessLoop.hs` документирован как `flag-off`. Импортируется `Core.PipelineIO.Internal`, `Core.PipelineIO.Test`, `Core.PipelineIO.Replay`. Код вызывается, но в flag-off режиме работает в деградированном режиме.

### 5.4 semanticFirstDisabled — ablation flag

`tpSemanticFirstDisabled` в `TurnPipeline.Types` — флаг абляции B2 Control-A. Управляется через env var `QXFX0_SEMANTIC_FIRST_DISABLED=1`. По умолчанию выключен (semantic-first path активен).

### 5.5 rrEssenceActive — write-only поле (из предыдущих аудитов)

`rrEssenceActive = True` всегда, но поле никогда не читается. Штампует trace, но ничего не гейтит. Декоративно, не функционально.

---

## 6. ADRs Proposed But Never Accepted

**19 ADR** в `docs/adr/proposed/` никогда не были приняты. Директории `accepted/` не существует — принятые ADR лежат напрямую в `docs/adr/`.

Ключевые непринятые ADR:

| ADR | Описание |
|---|---|
| 0014 | Multiple essences per session |
| 0015 | External essence summons |
| 0016 | Essence-aware conatus weights |
| 0019 | Promote family divergence |
| 0020 | Promote perspective operator |
| 0021 | Promote external LLM transport |
| 0022 | Promote adaptive mutation |
| 0023 | Demotion procedure |
| **0034** | **Self-core role split** (центральное архитектурное решение) |
| 0035 | Domain reasoning packs |
| **0036** | **Promote essence commitment** (код уже включён, ADR не принят) |
| 0041 | Cross-session essence persistence |
| 0043 | Promote episodic recall |
| 0044 | Promote user model |
| 0045 | Promote doubt loop |
| 0046 | Promote decoupled affect/mood |
| 0047 | Field-aware rendering / content saliency |
| 0048 | Promote derived inference |

**ADR-0036** особенно показателен: код уже включает Essence (rrEssenceActive=True), а ADR всё ещё в `proposed/`. Архитектурное решение принято в коде, но не в документации.

**Рекомендация:** ревьюнуть каждый proposed ADR — либо принять, либо отклонить. Особенно ADR-0034 и ADR-0036.

---

## 7. Old Reports

| Директория | Файлов |
|---|---|
| `reports/` (всего) | 118 |
| `reports/baseline_v2/` | 51 |
| `reports/baseline_v2/final_gates/` | 45 |
| `reports/coverage/` | 272 файла |

`reports/baseline_v2/final_gates/` содержит 45 файлов `_gate_results_ci-*.md` — это CI gate результаты, накопленные с мая по июнь 2026. Они исторические и не несут операционной ценности.

**Рекомендация:** архивировать или удалить старые gate results, оставить только последний.

---

## 8. Stubs / Placeholders

~45 ссылок на stub/placeholder/TODO/FIXME в Haskell-коде. Ключевые:

- `Self/Field.hs` — Field и FieldHistory являются stubs (Phase 4)
- `Bridge/AgdaWitness.hs` — `writeStubAgdaWitness` функция
- `Render/Authority.hs` — `isStubAuthority` функция
- `Semantic/AtomAccretion.hs` — документирован как provisional/not yet promoted

Эти stubs — часть архитектурного плана (поэтапное развитие), не мёртвый код. Но они указывают на нереализованные подсистемы.

---

## 9. Old Documentation

- `docs/worker_protocol_v1.md` — старая версия протокола worker (v1 в имени)
- `Semantic/Proposition.hs` содержит комментарий: "Original file (2435 lines) backed up as Proposition.hs.backup" — но файл `.backup` не найден (уже удалён, комментарий остался)

---

## 10. Proposition.hs Refactoring Residue

`Semantic/Proposition.hs` был рефакторен из 2435-строчного файла в подмодули (`Proposition/Detection`, `Proposition/Detectors`, `Proposition/Focus`, `Proposition/Parse`, `Proposition/Semantic`, `Proposition/Types`). Родитель реэкспортирует всё для обратной совместимости.

Подмодули `Proposition.Detection`, `Proposition.Detectors`, `Proposition.Focus`, `Proposition.Parse` (2089 LOC) импортируются только внутри `Semantic.Proposition` и друг друга. Они не мёртвые (реэкспортируются родителем), но представляют собой **монолитный кластер** — если родитель перестанет их реэкспортировать, они станут мёртвыми.

---

## Сводная таблица рекомендаций

| Приоритет | Действие | LOC/файлов |
|---|---|---|
| **HIGH** | Удалить duplicate Proposition*Admission (Types/ root) | 799 LOC |
| **HIGH** | Архивировать/удалить 23 dead Python scripts | 13 495 LOC |
| **HIGH** | Ревью 19 proposed ADRs (принять/отклонить) | 19 файлов |
| **MEDIUM** | Удалить 4 truly dead Haskell modules | 199 LOC |
| **MEDIUM** | Удалить или подключить 5 dead Thresholds sub-modules | 574 LOC |
| **MEDIUM** | Архивировать старые gate results | 45+ файлов |
| **LOW** | Очистить комментарий о Proposition.hs.backup | 1 строка |
| **LOW** | Удалить worker_protocol_v1.md | 1 файл |

**Общий объём мёртвого/дублирующего кода: ~15 067 LOC** (из ~70k hand-written Haskell + ~13.5k dead Python).

Это ~17% от объёма рукописного кода — значительная часть не несёт ценности.
