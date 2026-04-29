# Codex Research Execution Plan 2026

## Цель

Этот план превращает накопленные исследования в **исполняемый backlog для Codex**.

Ключевое решение:

- мы **не строим вторую архитектуру**;
- мы **оживляем и дожимаем существующую QxFx0-архитектуру**;
- приоритет у связки:
  `state -> decision -> trace -> parity -> verification`.

## Статус исполнения

`2026-04-23`: `Wave 1` выполнена в коде и проверена через `cabal test`, `verify.sh`, `release-smoke.sh`.
`2026-04-23`: `Wave 2` реализована: canonical shadow snapshot + snapshot id + divergence taxonomy протянуты в pipeline/projection/sql и покрыты тестами, гейты `verify.sh`/`release-smoke.sh` зелёные.
`2026-04-23`: `Wave 3` реализована: typed replay trace (`TurnReplayTrace`) строится в finalize, сохраняется в `turn_quality.replay_trace_json`, проверяется тестами и release-smoke gate.
`2026-04-23`: `Wave 4` зафиксирована по границе narrative: ADR принят, добавлен тест-инвариант "narrative hint cannot bypass hard shadow gate".
`2026-04-23`: `Wave 5` усилена по trace/gates: `verify.sh` и `release-smoke.sh` теперь валят gate при отсутствии replay-trace контракта в schema/migration или smoke-turn persistence.

## Источники плана

План синтезирован из:

- `brain_kb2.txt`, особенно блоков:
  - evidence-based audit / mechanism classifier,
  - legitimacy vs warrantedness,
  - Datalog shadow parity,
  - turn FSM / illegal transitions,
  - runtime gates / property-tests,
  - tail block `7378+` с P1/P2/P3 backlog;
- `research_packs/research_pack_all_in_one.md`;
- `research_packs/research_pack_shadow.md`;
- `research_packs/research_pack_decision.md`;
- `research_packs/research_pack_narrative.md`;
- текущего кода QxFx0.

## Что уже подтверждено в коде

Это не гипотезы, а реальные опорные точки:

- стадийный `TurnPipeline` существует:
  `PreparedTurn -> PlannedTurn -> RenderedTurn -> finalize`;
- `Finalize` уже разделён на `Precommit` / `Commit`;
- shadow real и не декоративный:
  `Bridge/Datalog.hs` сравнивает `R5Verdict`,
  `Route/Shadow.hs` может менять effective family и триггерить repair;
- `WarrantedMoveMode` и `R5Verdict` уже существуют;
- `LegitimacyReason` уже существует, но пока узкий;
- narrative и intuition уже влияют на route-поведение:
  это подтверждено и call edge, и тестами.

## Что считаем главными незакрытыми контурами

1. Нет явно закрытого `DecisionDisposition`-уровня:
   `permit / repair / deny / advisory` пока не собраны в одну типизированную outcome-модель.
2. Нет доказанного `canonical frozen snapshot` для parity между runtime и Datalog shadow.
3. Нет replay-grade turn trace, позволяющего без догадок восстановить:
   - requested family,
   - hints,
   - pre-shadow family,
   - shadow resolution,
   - final family,
   - final disposition.
4. Нет формально закрытого решения по narrative boundary:
   narrative как route hint уже есть, но его статус не закреплён архитектурно.

## Негласные правила для Codex

Во всех волнах:

- не удалять существующий pipeline и не строить параллельный;
- не заменять Datalog shadow новым движком;
- не делать "большой rewrite";
- любая новая сущность должна иметь:
  - ADT,
  - call edge,
  - downstream consumer,
  - tests,
  - gate или diagnostics;
- сначала делаем trace/parity/semantics,
  потом более высокоуровневые algorithmic overlays.

---

## Wave 1. Закрыть Outcome Semantics

### Задача

Сделать явной turn-level decision model поверх уже существующих:

- `WarrantedMoveMode`
- `LegitimacyReason`
- `TurnDecision`
- `TurnProjection`

### Что добавить

Новые сущности:

- `DecisionDisposition`
  - `DispositionPermit`
  - `DispositionRepair`
  - `DispositionDeny`
  - `DispositionAdvisory`
- `LegitimacyOutcome`
  - disposition
  - reasons
  - legitimacy status
  - warrant mode
- при необходимости `DecisionAdvisoryCode`

### Куда встраивать

- `src/QxFx0/Types/Decision/**`
- `src/QxFx0/Types/Decision.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`
- `src/QxFx0/Core/TurnLegitimacy/**`
- `src/QxFx0/Types/Domain.hs`
- `spec/Legitimacy.agda`

### Что изменить

1. Вынести расчёт итогового disposition в отдельную pure function.
2. Перестать разносить outcome semantics по нескольким местам неявно.
3. В `buildTurnProjection` писать не только `LegitimacyReason`, но и итоговый disposition.
4. Не ломать текущий `WarrantedMoveMode`; расширять поверх него, а не вместо него.

### Тесты

Добавить:

- matrix tests:
  `LegitimacyReason x WarrantedMoveMode x ShadowStatus -> DecisionDisposition`;
- сценарии:
  - shadow diverged -> repair/deny по policy;
  - parser low confidence -> advisory или degraded permit;
  - always warranted + no issues -> permit;
  - never warranted -> deny или forced repair.

### Критерий приёмки

- outcome semantics читается из одного типа и одной pure function;
- `TurnProjection` и runtime trace отражают disposition явно;
- тесты фиксируют переходы и не дают размыть `allowed` и `supported`.

---

## Wave 2. Freeze Shadow Snapshot

### Задача

Перевести shadow из "runtime facts appended to program" в
**явный canonical snapshot contract**, сохранив текущий Datalog engine.

### Что добавить

- `ShadowSnapshot`
- `ShadowSnapshotId`
- `ShadowCompareOutcome`
- `ShadowDivergenceKind`

### Куда встраивать

- `src/QxFx0/Bridge/Datalog.hs`
- `src/QxFx0/Types/ShadowDivergence.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Shadow.hs`
- `docs/adr/0004-shadow-snapshot-parity.md` или аналогичный ADR

### Что изменить

1. Вводим pure freeze-функцию:
   `freezeShadowSnapshot`.
2. Haskell-side verdict derivation и Datalog fact rendering должны читать один и тот же snapshot.
3. Добавить `ShadowSnapshotId` в trace/log/projection.
4. Расширить divergence taxonomy:
   - logic mismatch,
   - missing fact,
   - encoding mismatch,
   - version skew,
   - constant skew,
   - unavailable shadow.

### Тесты

Добавить:

- snapshot stability tests;
- bridge round-trip tests;
- parity tests на фиксированном snapshot;
- negative tests на missing facts / version skew.

### Gates

Расширить:

- `scripts/verify.sh`
- при необходимости новый replay/parity step

Fail conditions:

- hard divergence on canonical snapshot;
- missing hard-path facts;
- constant/version skew.

### Критерий приёмки

- shadow сравнивает runtime и Datalog по общему frozen snapshot;
- у divergence есть тип причины, а не только bool-флаги;
- parity можно воспроизвести детерминированно.

---

## Wave 3. Replay-Grade Turn Trace

### Задача

Сделать turn decision reconstructable без гадания.

### Что добавить

- `RouteDecisionTrace`
- `TurnReplayEnvelope` или `TurnDecisionTrace`

### Минимальные поля trace

- `requestId`
- `sessionId`
- `requestedFamily`
- `strategyFamily`
- `narrativeHint`
- `intuitionHint`
- `preShadowFamily`
- `shadowSnapshotId`
- `shadowStatus`
- `shadowDivergenceKind`
- `shadowResolvedFamily`
- `finalFamily`
- `finalForce`
- `decisionDisposition`
- `legitimacyReason(s)`
- `parserConfidence`
- `embeddingQuality`

### Куда встраивать

- `src/QxFx0/Core/TurnPipeline/Types.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`
- `src/QxFx0/Core/Observability/**`
- persistence path, где уже строится `TurnProjection`

### Что изменить

1. Не тащить trace в виде текстового мусора в логи; сделать typed trace.
2. Freeze trace до commit.
3. Persist replay envelope или его минимально достаточную проекцию.

### Тесты

- replay trace completeness;
- route override trace correctness;
- final family equals trace final family;
- commit path preserves replay envelope.

### Gates

Новый gate:

- trace completeness

Fail if:

- hard-gated turn не имеет полного trace;
- shadow-override произошёл, но не отражён в trace.

### Критерий приёмки

- любой спорный turn можно восстановить по trace;
- причины смены family больше не живут только в неявной логике.

---

## Wave 4. Закрепить Narrative Boundary

### Задача

Не гадать, а архитектурно зафиксировать:

- narrative только downstream?
- или narrative законно влияет на route?

### Важный факт

Сейчас код и тесты подтверждают реальное влияние narrative/intuition на route.
Значит, убрать это "по красоте" нельзя.

### Решение по умолчанию для этой волны

Сначала не удалять влияние narrative.
Сначала:

1. сделать его наблюдаемым,
2. типизировать,
3. зафиксировать policy,
4. только после этого решать, сузить границу или узаконить её.

### Что сделать

1. Добавить ADR:
   `narrative-as-route-hint` vs `narrative-downstream-only`.
2. Явно выделить narrative/intuition hints в trace.
3. Добавить tests на allowed / forbidden influence edges.
4. Если решаем оставить route influence:
   - добавить invariants:
     - hint never bypasses hard gate,
     - hint cannot hide shadow divergence,
     - hint is replay-visible.
5. Если решаем сужать:
   - сначала убрать family-changing path,
   - потом оставить only modulation/render path.

### Куда встраивать

- `src/QxFx0/Core/TurnModulation/Narrative.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/Consciousness/**`
- `test/Test/Suite/CoreBehavior.hs`
- ADR в `docs/adr/`

### Критерий приёмки

- narrative boundary перестаёт быть скрытым архитектурным спором;
- поведение либо explicitly legal, либо explicitly forbidden.

---

## Wave 5. Strengthen Gates And Replay Harness

### Задача

Довести verify/release harness до проверки не только "собирается", но и:

- parity,
- trace completeness,
- replay determinism.

### Что сделать

1. Расширить `scripts/verify.sh`:
   - trace schema check,
   - snapshot/parity check.
2. Расширить `scripts/release-smoke.sh`:
   - fixture-based replay turn,
   - assert stable family/disposition for fixed snapshot.
3. При необходимости добавить:
   - `scripts/replay-smoke.sh`

### Тесты и property layer

Из исследований брать только то, что напрямую полезно:

- deterministic route on fixed state;
- no partial facts on hard shadow path;
- deny/repair/advisory semantics are stable;
- narrative hint visible and bounded;
- illegal transition attempts rejected.

### Критерий приёмки

- build/test/smoke подтверждают не только сборку, но и архитектурную честность runtime.

---

## Deferred. Что из прошлых исследований не забываем, но не тащим сейчас в ядро

Ниже важные идеи, но **не P1** до завершения trace/parity/disposition:

### 1. Speculative Noise / Back to Kernel

Из `brain_kb2.txt` блоков `7001+`.

Статус:

- не забыто;
- отложено до тех пор, пока не будет replay infrastructure.

Причина:

- это уже algorithmic overlay;
- без trace/parity легко превратится в красивую, но неверифицируемую надстройку.

### 2. Slave Mode / Anticipation Trap / LIV

Статус:

- использовать как hypothesis bank для будущих policy modules;
- не внедрять сейчас в core routing.

Причина:

- пока нет достаточного repo-grounded decision harness;
- сначала нужна опора на replay and metrics.

### 3. Большие socio-ontological и incentive-модели

Статус:

- не потеряны;
- держать как отдельный research backlog;
- не смешивать с текущим hardening QxFx0 runtime.

---

## Порядок выполнения для Codex

### Sprint A

- Wave 1
- Wave 2

Результат:

- explicit disposition model
- shadow snapshot contract

### Sprint B

- Wave 3
- Wave 4

Результат:

- replay-grade trace
- narrative boundary policy

### Sprint C

- Wave 5
- точечные follow-up fixes из Sprint A/B

Результат:

- gates enforce architectural honesty

---

## Definition of Done

План считается реально реализованным только если:

1. `DecisionDisposition` и related outcome types встроены в runtime.
2. Shadow работает от canonical frozen snapshot.
3. Route/shadow/final decision reconstructable from typed trace.
4. Narrative boundary зафиксирована кодом + ADR + тестами.
5. `verify.sh` / `release-smoke.sh` валят сборку при нарушении новых invariants.

Если нет хотя бы одного из этих пунктов, исследования ещё не превращены в operational architecture.
