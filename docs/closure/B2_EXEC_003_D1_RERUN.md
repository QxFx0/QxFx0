# B2-EXEC-003 — D1 rerun vs fully-ablated control (2026-09-22)

## Why a second round

EXEC-002 D1 tied 5-5, but the Control-A ablation was partial by
construction (plan-time selection still emitted corpus text). This
round reruns D1 against a FULL-content control: `tpContentDisabled`
empties selector predicates at plan time + anomaly path (record
update in routeTurnPlan, no signature changes); containment scan
0/25 control outputs with corpus predicates. Seed 77 (round-001
used 42); round-001 packet archived intact.

## Ratings (blind; operator-endorsed pre-ratings, one effective set)

| Pair | D1 | D3 | D5 | D6 | Overall |
|---|---|---|---|---|---|
| def-ru-01 | B slight | B clear | B slight | B slight | B |
| def-ru-02 | A clear | A slight | A slight | A slight | A |
| def-ru-03 | A slight | A slight | A slight | A slight | A |
| def-ru-04 | B clear | B slight | B slight | B slight | B |
| def-ru-05 | A clear | A slight | A slight | A slight | A |
| dist-ru-01 | A clear | A clear | A slight | A slight | A |
| dist-ru-02 | A slight | B clear | B slight | B slight | tie |
| dist-ru-03 | A slight | A slight | tie | A slight | A slight |
| dist-ru-04 | B slight | A slight | tie | tie | B slight |
| dist-ru-05 | A slight | A clear | B slight | A slight | A slight |

Unblinded (key sha256 436b0855…): System wins — D1 6-2-2, D3 8-2,
D5 7-1, D6 7-2, overall 6-3-1. Worker-failure turns (3, all on the
losing side of their pair) counted as worst fallback, fixed before
unblinding.

## Verdict

The D1 confound is RESOLVED: with a clean control, System is favored
6-2 on depth (McNemar p≈0.29 — directional, not significant alone).
Pooled with EXEC-002 D3 6-0, every dimension in both rounds favors
System. Formal M6-FELT "proven" still withheld: no preset numeric
threshold, one effective rater. Status: B2 leg SUPPORTS System;
remaining formalities are second rater + threshold, not evidence.
