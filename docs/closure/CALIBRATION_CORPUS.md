# Calibration corpus v1 — schema and stratification

Status: **SEED v1 (synthetic templates, prelabel-only)**.
Labels are `null` until human rating; no weight may be promoted on
prelabels alone (see `CALIBRATION_BACKLOG.md` §4).

## Record schema (`corpusVersion: 1`)

```json
{"id": "cal-0001", "corpusVersion": 1, "stratum": "covered_definitional",
 "input": "что такое свобода?", "topic": "свобода",
 "labels": {"predicate_relevant": null, "challenge_strength": null,
            "response_acceptable": null, "crisis_expected": false},
 "prelabel": {"topic": "свобода", "source": "synthetic_template_v1"},
 "provenance": "synthetic_template_v1"}
```

Label codomains: `predicate_relevant ∈ {0,1,2,null}`,
`challenge_strength ∈ {"weak","strong",null}`,
`response_acceptable ∈ {0,1,null}`, `crisis_expected ∈ {true,false}`.

## Stratification (1000 records seed; 1030 with probe strata since 2026-09-19)

Seed table below; current counts in `data/calibration_corpus/manifest.json`
(added `probe_uncovered`/`probe_oov`/`probe_r5` 5 each + `r5_negative` 15).

| Stratum | N | Purpose |
|---|---|---|
| `covered_definitional` | 120 | scorePred top-1 accuracy base |
| `covered_distinction` | 120 | composeFromActivation multi-topic |
| `covered_relation` | 120 | spreading recall via shared atoms |
| `covered_challenge` | 120 | evidenceWeight strong-class |
| `covered_practical` | 120 | field-conditioned predicate choice |
| `uncovered` | 200 | uncovered_generic path, no false-covered |
| `challenge_marks` | 150 | challenge-mark lexicon coverage |
| `safety_negative` | 50 | crisis decoys, must NOT fire hard gate |

## Promotion rule

A record becomes train-eligible only with human `labels` filled
(double-rated on 20% + kappa; disputes to `adjudicated/`).
`prelabel` never counts as a label. (`assistant-pre` + human-confirmed
batch ratings are NOT synthetic prelabels — they are proposed labels
with batch confirmation; see CALIBRATION_REPORT.md operator decision
2026-09-21. The terms look alike; the categories differ.)
