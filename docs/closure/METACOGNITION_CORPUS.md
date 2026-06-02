# Metacognition Corpus Spec (QxFx0_v3)

- **Status**: Active (closure-phase follow-up F-09, Package 9
  calibration gate)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/METACOGNITION_LOOP_DESIGN.md` §4
- **Related**:
  - `docs/closure/LEARNING_EXAMPLE.md` (F-07)
  - `docs/closure/CALIBRATION_BACKLOG.md`

## 0. Why this spec exists

The closure plan's Package 9 §4 requires that the
metacognitive loop is **calibrated against external
evaluation**. This means a held-out corpus with **external
labels** (human-rated decision-outcome alignment). Without
the corpus, the calibration gate cannot run, and the
metacognition module is `canonical-flag-off`.

This document specifies the corpus: which records, which
fields, which external labels, which labelling protocol, and
the initial data target.

## 1. The corpus shape

The corpus is a collection of records in JSONL format
(one record per line), stored at
`data/metacognition_corpus/`:

```
data/metacognition_corpus/
  v1/
    labelled.jsonl         -- the labelled subset (≥ 100 records)
    unlabelled.jsonl       -- the unlabelled subset (≥ 1k records)
    schema.json            -- the record schema
    labelling_protocol.md  -- the human-rating protocol
    README.md              -- what this corpus is, how it was built
```

The `v1` directory is the initial version. Future versions
(`v2`, `v3`, ...) are added as the calibration gate runs.

## 2. The record schema

Each record in `labelled.jsonl` and `unlabelled.jsonl` is a
JSON object with the following fields:

```json
{
  "schema_version": 1,
  "session_id": "sess-...",
  "turn_seq": 1,
  "decision": {
    "family": "CMContact",
    "style":  "Direct",
    "tone":   "Warm"
  },
  "deliberation": {
    "rule":      "salience_lead",
    "agreement": "agree",
    "divergence": 0.0
  },
  "salience": {
    "driver":     "resonance",
    "bias":       0.62,
    "confidence": 0.85
  },
  "essence": {
    "mode":       "witnessing",
    "angst":      0.10
  },
  "commitments_at_turn": [1, 2],
  "episodic_event_ids":   [1, 2, 3, 4],
  "outcome": {
    "kind": "Accepted" | "Refined" | "Rejected" | "Contradicted" | "Ignored" | "NoFeedback",
    "raw_user_text": "I work in Haskell."
  },
  "external_label": {
    "decision_outcome_alignment": "aligned" | "misaligned" | "ambiguous",
    "decision_quality":            "good" | "neutral" | "bad",
    "labeller_id":                 "rater-NN",
    "labelled_at":                 "2026-06-02T..."
  }
}
```

The `external_label` field is present only in
`labelled.jsonl`; `unlabelled.jsonl` has the same fields
except `external_label`.

## 3. The labelling protocol

The protocol is in
`data/metacognition_corpus/v1/labelling_protocol.md`. The
initial version has these rules:

### 3.1 `decision_outcome_alignment`

A labeller rates a `(decision, outcome)` pair as:

- **aligned** — the decision was correct given the outcome.
  The labeller should answer "yes, the system did the right
  thing" before seeing the system's self-evaluation.
- **misaligned** — the decision was wrong. The system
  should have done something different.
- **ambiguous** — the outcome is too weak to decide. The
  user's text is unclear, or the system had no good option.

The labeller sees:

- the `decision` (family, style, tone);
- the `outcome` (kind, raw user text);
- the `deliberation`, `salience`, `essence` (for context).

The labeller does **not** see:

- the system's self-evaluation (`Evaluation`);
- any previous labels for the same record.

### 3.2 `decision_quality`

A second dimension, rated independently:

- **good** — the decision was good in absolute terms.
- **neutral** — the decision was acceptable but not good.
- **bad** — the decision was bad in absolute terms.

This dimension is optional; the initial corpus may not have
it.

### 3.3 Inter-rater agreement

Every record is labelled by at least **2 raters**. The
inter-rater agreement is measured by **Cohen's kappa**:

- kappa ≥ 0.8: high agreement; the record is `accepted`.
- 0.6 ≤ kappa < 0.8: moderate agreement; the record is
  `accepted` with a note.
- kappa < 0.6: low agreement; the record is **excluded**
  from the labelled subset.

The initial corpus target: ≥ 80% of records have kappa ≥
0.8. Records with kappa < 0.6 are excluded.

## 4. The initial data target

The closure plan's Package 9 §4 requires:

- ≥ 1 000 unlabelled records (`unlabelled.jsonl`).
- ≥ 100 labelled records (`labelled.jsonl`).
- The labelled subset is held out (not used for training;
  only for calibration gate verification).

The initial corpus (`v1`) target:

- 1 000 unlabelled records (production trace, no external
  labels).
- 100 labelled records (production trace + 2-rater
  external labels, kappa ≥ 0.8).
- The 100 labelled records are split: 80 for the
  calibration gate, 20 held out for the calibration
  verification.

## 5. How the corpus is built

The corpus is built in three steps:

1. **Production trace extraction.** A CI job extracts
   `TurnReplayTrace` records from production sessions,
   filters for sessions with at least 4 turns and at least
   one `Outcome`, and writes the unlabelled records.
2. **Labelling campaign.** A small team of 2-4 raters
   labels a subset of the unlabelled records following the
   protocol of §3. Each rater is independent; the kappa
   is computed.
3. **Calibration gate.** The labelled subset is used by
   `Test.Suite.MetacognitionCalibration` to verify that
   the metacognitive loop's self-evaluation correlates
   with the external labels (per Package 9 §1.3).

The corpus is **regenerated** at every release (default).
The closure plan's Package 11 uses the corpus for
calibration; Package 9 uses it for the calibration gate.

## 6. The CI gate

The CI gate is:

```bash
# Verify the corpus is present and well-formed.
test -f data/metacognition_corpus/v1/labelled.jsonl
test -f data/metacognition_corpus/v1/unlabelled.jsonl
test -f data/metacognition_corpus/v1/schema.json

# Verify the labelled subset has at least 100 records.
wc -l data/metacognition_corpus/v1/labelled.jsonl | awk '$1 >= 100'

# Verify the unlabelled subset has at least 1k records.
wc -l data/metacognition_corpus/v1/unlabelled.jsonl | awk '$1 >= 1000'

# Verify the schema.
python3 -c "import json, jsonschema; ..."  # if a validator is available
# (note: this is the only Python in the project that is
# allowed; the validator is a one-shot CI check, not an
# authority path.)
```

The CI gate fails if any of the above fails.

## 7. The discipline

The discipline of this corpus is:

- **External labels are required.** A record without an
  external label is in `unlabelled.jsonl`; it is used for
  training but not for the calibration gate.
- **The labelling protocol is the spec.** A new label
  format requires a new schema version (`v2`, `v3`).
- **The kappa is the gate.** A record with kappa < 0.6 is
  excluded; it does not pollute the calibration gate.
- **The corpus is regenerated.** A stale corpus is a
  bug; the CI gate re-validates on every release.
- **The labelled subset is held out.** The same records
  cannot be used for both training and gate verification.
  The split is 80/20 (per §4).

## 8. Acceptance criteria for F-09

F-09 is closed when:

- [ ] The corpus spec (this file) is merged.
- [ ] `data/metacognition_corpus/v1/` exists with at least:
  - 1 000 unlabelled records;
  - 100 labelled records (kappa ≥ 0.8);
  - the schema and the labelling protocol.
- [ ] The CI gate of §6 is in place; CI is green.
- [ ] `Test.Suite.MetacognitionCalibration` passes against
  the labelled subset.
- [ ] The closure plan's Package 9 §4 acceptance criteria
  are met (precision ≥ 0.85, recall ≥ 0.70 on the held-out
  20% of the labelled subset).
