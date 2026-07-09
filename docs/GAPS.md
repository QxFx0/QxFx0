# QxFx0 — Surface Predicate Gaps (P0.2 dogfooding)

This file lists concepts that appear in the curated atom-graph seed (`resources/knowledge/relations.jsonl`) but have no `SemanticPredicate` in `definitionCorpus`. These concepts can be activated by spreading activation yet cannot be verbalized by `composeFromActivation` until surface predicates are curated.

## Method

Static scan comparing the `from`/`to` tokens of the 666 curated relations against the 30 topics currently present in `QxFx0.Semantic.Content.definitionCorpus`.

## Summary

- Covered topics: **30**
- Concepts in relations graph: **311**
- Uncovered (gap) concepts: **281**
- Top-20 candidate backlog below.

## Gap backlog (top 20 by frequency in relations)

| Rank | Concept | Frequency | Status |
|---|---|---|---|
| 1 | смысл | 23 | pending |
| 2 | идентичность | 18 | pending |
| 3 | граница | 15 | pending |
| 4 | ремонт | 15 | pending |
| 5 | цифра | 14 | pending |
| 6 | доказательство | 5 | pending |
| 7 | становление | 4 | pending |
| 8 | сущность | 3 | pending |
| 9 | целостность жизни | 3 | pending |
| 10 | соотнесённость с целым | 3 | pending |
| 11 | различение внутри и снаружи | 3 | pending |
| 12 | условие формы | 3 | pending |
| 13 | дискретность и точность | 3 | pending |
| 14 | формализация опыта | 3 | pending |
| 15 | преемственность я | 3 | pending |
| 16 | нарратив о себе | 3 | pending |
| 17 | восстановление функции | 3 | pending |
| 18 | диагностика поломки | 3 | pending |
| 19 | осознанность выбора | 3 | pending |
| 20 | самоопределение | 3 | pending |

Full list contains 50 concepts; top 20 shown.

## Notes

- Full live-dialog dogfooding with 10 philosophical turns is pending; this scan is a static lower bound of the gap.
- The next step (P1.2) is to curate 1–2 `SemanticPredicate`s for each top-20 concept and load them via `resources/knowledge/curated_predicates.jsonl`.
