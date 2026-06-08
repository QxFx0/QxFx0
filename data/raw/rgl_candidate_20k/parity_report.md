# RGL Candidate 20k Parity Report
**Date:** 2026-06-08
**Candidate:** `data/raw/rgl_candidate_20k/paradigms_candidate_20k.json` (20,000 paradigms)
**Existing:** `resources/morphology/paradigms.json` (3,968 paradigms)
**Funmap:** `spec/gf/lexicon_funmap.tsv` (3,743 noun lemmas)
## Coverage Summary
- **Funmap superset:** YES
- **Funmap present in candidate:** 3,743 / 3,743
- **Funmap missing from candidate:** 0
- **Verbal nouns in funmap:** 131 (all present in candidate: True)
## Discrepancy Classification (funmap vs candidate)
| Class | Count | Description |
|-------|-------|-------------|
| G1 (ё normalization) | 0 | Forms contain ё or value mismatch vs existing JSON |
| G2 (animacy) | 0 | Animacy flag differs from existing JSON |
| G3 (gender) | 0 | Gender flag differs from existing JSON |
| G4 (missing forms) | 8 | Empty or partial paradigm (empty: 9, partial: 3139) |
| G5 (new coverage) | 0 | Not in existing JSON or missing from candidate |
| OK | 3,735 | Perfect match with existing JSON |
## Notable Cases
### Empty paradigms (no inflectable forms)
- `авр`: G4 (empty paradigm — no inflectable forms)
- `априори`: G4 (empty paradigm — no inflectable forms)
- `арх`: G4 (empty paradigm — no inflectable forms)
- `вчера`: G4 (empty paradigm — no inflectable forms)
- `далеко`: G4 (empty paradigm — no inflectable forms)
- `диг`: G4 (empty paradigm — no inflectable forms)
- `завтра`: G4 (empty paradigm — no inflectable forms)
- `сегодня`: G4 (empty paradigm — no inflectable forms)
- `хорошо`: G4 (empty paradigm — no inflectable forms)
### Partial paradigms (fewer than 12 forms)
- `аба`: 6/12 forms
- `абаза`: 6/12 forms
- `абаканвагонмаш`: 6/12 forms
- `абаканэнергопромстрой`: 6/12 forms
- `абанагропромхимия`: 6/12 forms
- `абразивность`: 6/12 forms
- `абсорбирование`: 6/12 forms
- `абсорбированье`: 6/12 forms
- `авантажность`: 6/12 forms
- `авиазапчасть`: 6/12 forms
- `авиазондирование`: 6/12 forms
- `авиаимущество`: 6/12 forms
- `авиаипотека`: 6/12 forms
- `авиалесоохрана`: 6/12 forms
- `авиаопрыскивание`: 6/12 forms
- `авиаопыливание`: 6/12 forms
- `авиаопыливанье`: 6/12 forms
- `авиасообщение`: 6/12 forms
- `авиатопливо`: 6/12 forms
- `авиатопливообеспечение`: 6/12 forms
... and 3119 more partial paradigms
### Verbal nouns (funmap subset)
- `абсорбированье`: 6/12 forms
- `авиаопыливанье`: 6/12 forms
- `авиасообщение`: 6/12 forms
- `авизованье`: 6/12 forms
- `агентирование`: 6/12 forms
- `агрегатированье`: 6/12 forms
- `агрегирование`: 6/12 forms
- `администрирование`: 12/12 forms
- `адресованье`: 6/12 forms
- `азотированье`: 6/12 forms
- `азотоподавление`: 6/12 forms
- `активированье`: 6/12 forms
- `акцептованье`: 6/12 forms
- `акционирование`: 6/12 forms
- `алитированье`: 6/12 forms
- `алкилирование`: 6/12 forms
- `версионирование`: 6/12 forms
- `видение`: 12/12 forms
- `владение`: 12/12 forms
- `влечение`: 12/12 forms
- `влияние`: 12/12 forms
- `возвышение`: 12/12 forms
- `воздухоплавание`: 12/12 forms
- `восстановление`: 12/12 forms
- `восхищение`: 12/12 forms
- `впечатление`: 12/12 forms
- `вращение`: 12/12 forms
- `выражение`: 12/12 forms
- `высказывание`: 12/12 forms
- `выступление`: 12/12 forms
- `горение`: 12/12 forms
- `давление`: 12/12 forms
- `движение`: 12/12 forms
- `делегирование`: 12/12 forms
- `дешифрование`: 6/12 forms
- `дополнение`: 12/12 forms
- `допущение`: 12/12 forms
- `достижение`: 12/12 forms
- `завершение`: 12/12 forms
- `заключение`: 12/12 forms
- `замедление`: 12/12 forms
- `заявление`: 12/12 forms
- `здание`: 12/12 forms
- `землетрясение`: 12/12 forms
- `значение`: 12/12 forms
- `изгнание`: 12/12 forms
- `излучение`: 12/12 forms
- `изменение`: 12/12 forms
- `исключение`: 12/12 forms
- `испарение`: 12/12 forms
- `исправление`: 12/12 forms
- `испытание`: 12/12 forms
- `классифицирование`: 6/12 forms
- `колебание`: 12/12 forms
- `конфигурирование`: 6/12 forms
- `кэширование`: 12/12 forms
- `мгновение`: 12/12 forms
- `молчание`: 12/12 forms
- `наваждение`: 12/12 forms
- `назначение`: 12/12 forms
- `намерение`: 12/12 forms
- `нападение`: 12/12 forms
- `направление`: 12/12 forms
- `напряжение`: 12/12 forms
- `обещание`: 12/12 forms
- `обобщение`: 12/12 forms
- `обоснование`: 12/12 forms
- `обслуживание`: 12/12 forms
- `обсуждение`: 12/12 forms
- `объединение`: 12/12 forms
- `объяснение`: 12/12 forms
- `ограничение`: 12/12 forms
- `окисление`: 12/12 forms
- `окружение`: 12/12 forms
- `опережение`: 12/12 forms
- `описание`: 12/12 forms
- `определение`: 12/12 forms
- `опровержение`: 12/12 forms
- `основание`: 12/12 forms
- `отклонение`: 12/12 forms
- `отношение`: 12/12 forms
- `отражение`: 12/12 forms
- `отрицание`: 12/12 forms
- `отчаяние`: 12/12 forms
- `перемещение`: 12/12 forms
- `пересечение`: 12/12 forms
- `питание`: 12/12 forms
- `плавление`: 12/12 forms
- `поведение`: 12/12 forms
- `помещение`: 12/12 forms
- `понимание`: 12/12 forms
- `поручение`: 12/12 forms
- `предложение`: 12/12 forms
- `предположение`: 12/12 forms
- `прерывание`: 12/12 forms
- `преступление`: 12/12 forms
- `принуждение`: 12/12 forms
- `продолжение`: 12/12 forms
- `профилирование`: 12/12 forms
- `прощение`: 12/12 forms
- `разграничение`: 12/12 forms
- `разрешение`: 12/12 forms
- `расписание`: 12/12 forms
- `распоряжение`: 12/12 forms
- `распределение`: 12/12 forms
- `расставание`: 12/12 forms
- `расстояние`: 12/12 forms
- `решение`: 12/12 forms
- `свидание`: 12/12 forms
- `сиденье`: 12/12 forms
- `следование`: 12/12 forms
- `смирение`: 12/12 forms
- `сознание`: 12/12 forms
- `солнцестояние`: 12/12 forms
- `сомнение`: 12/12 forms
- `сообщение`: 12/12 forms
- `соотношение`: 12/12 forms
- `сопротивление`: 12/12 forms
- `страдание`: 12/12 forms
- `суждение`: 12/12 forms
- `существование`: 12/12 forms
- `трение`: 12/12 forms
- `уведомление`: 12/12 forms
- `удовлетворение`: 12/12 forms
- `умозаключение`: 12/12 forms
- `управление`: 12/12 forms
- `ускорение`: 12/12 forms
- `утверждение`: 12/12 forms
- `целеполагание`: 6/12 forms
- `шифрование`: 6/12 forms
- `явление`: 12/12 forms
## Predicted Integration Backlog (full 20k set)
### Verbal nouns — InsSg breakdown
- **Total verbal nouns in candidate:** 4,169
- **InsSg ending in `-нием`:** 4,150
- **InsSg NOT ending in `-нием` (potential G1-like fix):** 19
#### Examples: `-нием` (5)
- `абонирование` → `абонированием`
- `абсолютизирование` → `абсолютизированием`
- `абсорбирование` → `абсорбированием`
- `абстрагирование` → `абстрагированием`
- `авансирование` → `авансированием`
#### Examples: non`-нием` (5)
- `абсорбированье` → `абсорбированьем`
- `авиаопыливанье` → `авиаопыливаньем`
- `авизованье` → `авизованьем`
- `агрегатированье` → `агрегатированьем`
- `адресованье` → `адресованьем`
### Predicted G-class examples (5 each, full 20k)
- **G1 (yo in forms):** 0 total
  - None
- **G2 (animacy mismatch):** 0 total
  - None
- **G3 (gender mismatch):** 0 total
  - None
- **G4 empty (no forms):** 9 total
  - `авр`
  - `априори`
  - `арх`
  - `вчера`
  - `далеко`
- **G4 partial (< 12 forms):** 3,139 total
  - `аба` (6/12)
  - `абаза` (6/12)
  - `абаканвагонмаш` (6/12)
  - `абаканэнергопромстрой` (6/12)
  - `абанагропромхимия` (6/12)
- **G5 (new coverage, not in existing):** 16,032 total
  - `а-конто`
  - `а-ось`
  - `аба`
  - `абажурчик`
  - `абаза`
## Methodology
- G1: checked for unnormalized ё in candidate form values; also flagging form-value mismatches against existing JSON.
- G2/G3: compared `animacy` and `gender` fields against existing JSON.
- G4: counted candidate paradigms with 0 forms (empty) or fewer than 12 keys (partial).
- G5: funmap lemmas missing from candidate entirely, or not present in existing JSON.
- Verbal nouns: identified by suffix `-ние`, `-нье`, `-ение` in funmap lemmas.
- Predicted integration backlog: classified across full 20k candidate set for future integration planning.
