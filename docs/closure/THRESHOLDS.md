# QxFx0 — единый реестр порогов (audit 2026-09-15)

Status: **HAND-SET v1, НЕ КАЛИБРОВАНЫ**. Все константы ниже — ручные,
frozen-on-release. Любое изменение требует bump `currentMathVersion`
(`QxFx0.Types.RuntimeRegime`) + holdout-проверку. Калибровка заблокирована
отсутствием `data/calibration_corpus/` (N≥1k + ≥100 labelled) — см.
`docs/closure/CALIBRATION_BACKLOG.md`.

Правило чтения: одно имя — один смысл — одна шкала. Похожие имена в разных
шкалах НЕ взаимозаменяемы; правка «по аналогии» запрещена без кросс-проверки
всей таблицы.

## 1. «Низкий conatus» — пять разных порогов

| Порог | Значение | Шкала | Смысл | Код |
|---|---|---|---|---|
| `conatusGateThreshold` | 0.0 | `ceScalar` (log-scale) | Salience gate: ниже → `PreferFormal/DrivenByConatusGate` | `Self/Salience.hs` |
| `lowEnergyThreshold` | 3.0 | `ceScalar` | Routing-рестрикции | `Self/Conatus.hs` |
| `emConatusStructuralFloor` | 7.0 | `ceScalar` | Essence-триггер (окно свидетелей < 7.0); WP-F фикс unit-mismatch | `Types/Self/Essence.hs` |
| AntiConatus gate | 5.0 | `ceScalar` | `conatus < 5.0` в конъюнкции Anomaly-2 | `Core/TurnPipeline/Route/Anomaly.hs:101` |
| Perspective admissibility | 0.0 | `csEnergy` | Другая величина (не `ceScalar`) | `Self/Perspective.hs:157` |

## 2. Essence / angst / divergence

| Порог | Значение | Код |
|---|---|---|
| `emAngstCommitmentThreshold` | 0.75 | `Types/Self/Essence.hs` |
| `emAngstAccrualRate` / `emAngstDecayRate` | 0.05 / 0.02 | `Types/Self/Essence.hs` |
| `sdtThreshold` / `sdtScaling` / `sdtWindow` | 0.35 / 0.035 / 8 | `Types/Self/SelfDivergence.hs` |
| SelfRef collapse | angst > 0.9 ∧ substring из 8 субъектов | `Route/Anomaly.hs:61` |
| AntiConatus | conf > 0.7 ∧ ¬consistent ∧ angst > 0.8 ∧ conatus < 5.0 | `Route/Anomaly.hs:101` |

## 3. Семантика / spreading / defense

| Порог | Значение | Код |
|---|---|---|
| `scorePred` floor | 0.1 | `Semantic/ContentSelector.hs` |
| activation cutoff | 0.05 (каскад × take 3) | `Semantic/Network.hs`, `ContentSelector.hs` |
| `weightContentSaliency` | 0.6 | `Self/Salience.hs:189` |
| `contentDensityGate` | ≥50 edges ∧ ≥15 nodes | `Semantic/Network.hs:238` |
| defend strong-challenge | `weight < 0.88` (шкала [0.7, 1.0]!) | `Semantic/Stance.hs` |
| synthesis Conjunction/Irreducible | shared ≥ 2 атома | `Semantic/Revision.hs` |
| confidence decay / synthesis conf | ×0.9 / 0.5 / 0.3 | `Semantic/Revision.hs` |

## 4. Concept-v3 / user contour

| Порог | Значение | Код |
|---|---|---|
| `vcAbsoluteFloor` / `vcPersonalMargin` | 0.05 / 0.25 | `Types/User/R5.hs` |
| `negativeEvidenceEarned` | atm > 0.30 ∨ conf < 0.45 | `Types/User/R5.hs` |
| `resonanceGateThreshold` | 0.55 | `Semantic/Ontological.hs` |
| `moveDriftMargin` | 0.10 (< margin 0.25 — move раньше выхода) | `Semantic/MoveGraph.hs` |
| residual anomaly | > 0.35 | `Observability/TraceAnalysis.hs` |
| EMA / residual windows | 10 / 8 | `Types/User/R5.hs` |

## 5. Recovery severity ladder

`Nothing 0 < ParserLowConfidence 20 < LowLegitimacy 30 < UnknownTopic 40 <
ShadowUnavailable 50 < ShadowDivergence 60 < RuntimeDegraded 70 <
RenderBlocked 80 < LearningNeed 85 < SelfDivergence 90 < ConatusGate 100`
(`Self/Deliberation.hs:278-289`, merge — `pickHigherSeverity`).
