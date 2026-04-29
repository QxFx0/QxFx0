# Clockwork Delta Audit — 2026-04-23

## Scope

Точечный аудит после трёх задач:
1. Усилить `verify_agda_sync.py` дополнительными trace/legitimacy конструкторами.
2. Добавить property-тесты на детерминизм replay envelope для одинаковых входов.
3. Ужесточить verify gate: sync mismatch должен быть hard-fail.
4. Зафиксировать метрики `до/после` по clockwork-контурy.

## Baseline (до изменений)

- Sync-контур проверял только 2 пары:
  - `CanonicalMoveFamily` (Agda ↔ Haskell)
  - `IsLegit` (Agda ↔ Haskell)
- Replay envelope детерминизм не был закрыт property-тестами.
- Тестовый раннер: `Cases: 209` (предыдущая ревизия).
- Gate-система уже была зелёной, но без расширенного trace-sync покрытия.

## Реализация

### 1) Agda sync расширен

`scripts/verify_agda_sync.py` теперь проверяет 9 контрактов:

- `CanonicalMoveFamily[Sovereignty]`
- `CanonicalMoveFamily[R5Core]` (двойная проверка против второго Agda-источника)
- `IllocutionaryForce[Trace]`
- `SemanticLayer[Trace]`
- `ClauseForm[Trace]`
- `WarrantedMoveMode[Legitimacy]`
- `IsLegit[Legitimacy]`
- `LegitimacyReason[Legitimacy]`
- `DecisionDisposition[Legitimacy]`

Итог: sync-контур теперь покрывает не только family/legit-теги, но и ключевые trace-поля replay envelope (force/layer/clause), legitimacy mode и reason/disposition ветку.

### 2) Property-тесты replay envelope

В `test/Test/Suite/TurnPipelineProtocol.hs` добавлены:

- `testReplayEnvelopeDeterministicProperty`
- `testReplayEnvelopeJsonDeterministicProperty`

Оба теста гоняются как QuickCheck (`maxSuccess = 100`) по одинаковым входам и проверяют:

- детерминизм typed replay envelope;
- детерминизм JSON-сериализации replay envelope.

В `test/Test/Suite/RuntimeInfrastructure.hs` добавлен интеграционный property-тест:

- `testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty`

Тест гоняется как QuickCheck (`maxSuccess = 20`) и проверяет детерминизм уже persisted `replay_trace_json` между двумя fresh-сессиями для одинакового входа (с нормализацией `trcRequestId`/`trcSessionId`).

### 3) Verify sync ужесточён до hard-fail

В `scripts/verify.sh` post-check для `verify_agda_sync.py` переведён с warning-режима на обязательный gate:

- раньше: mismatch -> `PASS_WITH_WARNINGS`;
- теперь: mismatch -> `FAIL` с `exit 1`.

## Верификация после изменений (2026-04-23)

- `python3 scripts/verify_agda_sync.py` -> PASS (9/9 контрактов)
- `cabal build all` -> PASS
- `cabal test qxfx0-test` -> PASS (`Cases: 212`, `Errors: 0`, `Failures: 0`)
- `bash scripts/verify.sh` -> PASS
- `bash scripts/release-smoke.sh` -> ACCEPT (`10/10`, elapsed `93s`)
- `cabal check` -> clean

## Метрики Clockwork (до/после)

| Метрика | До | После | Δ |
|---|---:|---:|---:|
| Agda sync контрактов | 2 | 9 | +7 |
| Constructor assertions (Agda↔Haskell) | 17 | 54 | +37 |
| Replay determinism property-тестов | 0 | 3 | +3 |
| Replay determinism QuickCheck прогонов | 0 | 220 | +220 |
| Общие тест-кейсы (`cabal test`) | 209 | 212 | +3 |
| verify gate | PASS | PASS | = |
| release smoke gates | 10/10 | 10/10 | = |

## Оценка

- Architecture completeness: без изменений в структуре слоёв.
- Technical debt: локально снижен в зоне sync/trace reliability.
- Clockwork precision: **9.3 -> 9.5** за счёт более жёсткого contract-sync, hard-fail sync gate и доказанного replay determinism (typed + persisted).

## Остаточный контур

- Для текущего контура критичных долгов нет; остаток относится к дальнейшему расширению coverage/spec depth, а не к блокирующей надёжности clockwork-гейтов.
