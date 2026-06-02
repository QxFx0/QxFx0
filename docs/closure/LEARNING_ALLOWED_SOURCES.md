# Learning Allowed Sources (QxFx0_v3)

- **Status**: Active (closure-phase follow-up F-04, Package 8
  invariant I2)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/BOUNDED_LEARNING_DESIGN.md` §1, I2
- **Related**: `docs/closure/LEARNING_ALLOWED_TARGETS.md` (F-03)

## 0. Why this file exists

The closure plan's Package 8 invariant I2 says: "a learning
update may only consume signals from **authority-bearing**
sources. The closed list is in `LEARNING_ALLOWED_SOURCES.md`;
CI rejects consumption of any other signal."

This is that file. The list is **closed**: adding a new
source requires a phase-ADR (or closure-plan follow-up) and
a follow-up issue.

## 1. The closed list

Each entry has:

- `source` — the `LearningSource` constructor.
- `owner-module` — the Haskell module that produces the
  signal.
- `signal-type` — the underlying type of the signal.
- `value-range` — the closed range the signal must stay in.
- `rationale` — why this source is authority-bearing.
- `added-in` — the closure-plan PR / ADR that added it.
- `removal-criterion` — when this source should be removed.

### S-01: `SrcDialogueOutcome !DialogueOutcomeTag`

- **owner-module**: `QxFx0.Core.DialogueOutcomeLearning` (and
  its post-Package 8 successor in `QxFx0.Learning.Contour`)
- **signal-type**: `DialogueOutcomeTag` (a closed enum; the
  exact set is `Success | Failure | Refinement |
  Contradiction | NoSignal`).
- **value-range**: enum; no numeric range.
- **rationale**: `DialogueOutcomeLearning` is the existing
  per-turn dialogue-outcome signal. It is authority-bearing
  because it is the **direct** observation of whether the
  system's response was accepted. Without it, no learning
  loop can detect "did this work?".
- **added-in**: pre-closure (existing field on `SystemState`).
- **removal-criterion**: if dialogue-outcome learning is
  retired, this source is removed.

### S-02: `SrcCommitmentRetraction !CommitmentId`

- **owner-module**: `QxFx0.Semantic.Commitment` (post-Package 2)
- **signal-type**: `CommitmentId` (the id of the retracted
  commitment).
- **value-range**: enum (id is `Int`).
- **rationale**: a commitment retraction is a typed event
  (Package 2 §1.2). It signals that the system **withdrew**
  a previous claim. This is a strong negative signal for
  learning: the underlying parameters were wrong, or the
  parser was wrong, or the orchestrator was wrong.
- **added-in**: closure-plan P2.
- **removal-criterion**: if commitment retraction is
  removed, this source is removed.

### S-03: `SrcCommitmentContradiction !(CommitmentId, CommitmentId)`

- **owner-module**: `QxFx0.Semantic.Commitment` (post-Package 2)
- **signal-type**: pair of commitment ids; the system
  recorded that two commitments contradict.
- **value-range**: enum (pair of ids).
- **rationale**: a contradiction is a typed event (Package 2
  §1.2). It signals that the system has two claims that
  cannot both be true. This is a strong negative signal.
- **added-in**: closure-plan P2.
- **removal-criterion**: if contradiction recording is
  removed, this source is removed.

### S-04: `SrcEpisodicRetrievalOutcome !RetrievalOutcomeTag`

- **owner-module**: `QxFx0.Memory.Episodic` (post-Package 7)
- **signal-type**: `RetrievalOutcomeTag` (a closed enum;
  the exact set is `Useful | NotUseful | Empty`).
- **value-range**: enum.
- **rationale**: a retrieval outcome is the system's own
  observation of whether the episodic memory retrieval
  helped the current turn. It is authority-bearing because
  it is the **direct** signal of memory utility.
- **added-in**: closure-plan P7.
- **removal-criterion**: if episodic memory is removed, this
  source is removed.

### S-05: `SrcMetacognitiveEvaluation !EvaluationTag`

- **owner-module**: `QxFx0.Policy.Metacognition` (post-Package 9)
- **signal-type**: `EvaluationTag` (a closed enum mirroring
  the `Evaluation` constructors: `Aligned | Misaligned |
  Ambiguous | Uncalibrated`).
- **value-range**: enum.
- **rationale**: a self-evaluation is the system's own
  post-hoc assessment of its own decision (Package 9 §1.3).
  It is authority-bearing **only if** the calibration gate
  (Package 9 §4) is met. Until the calibration gate is met,
  this source is `canonical-flag-off`.
- **added-in**: closure-plan P9.
- **removal-criterion**: if metacognition is removed, this
  source is removed.

## 2. The CI gate (extension of `check_architecture.sh`)

The invariant I2 enforcement at CI time is:

```bash
# Find every constructor of LearningSource in src/ and tests/.
# Verify each appears in this file (LEARNING_ALLOWED_SOURCES.md).
grep -rh "Src" src/QxFx0/Learning/ test/Test/Suite/LearningContour/ \
  | grep -oE "Src[A-Z][a-zA-Z]+" \
  | sort -u \
  > /tmp/learning_sources_used.txt
grep -oE "Src[A-Z][a-zA-Z]+" docs/closure/LEARNING_ALLOWED_SOURCES.md \
  | sort -u \
  > /tmp/learning_sources_allowed.txt
diff /tmp/learning_sources_used.txt /tmp/learning_sources_allowed.txt \
  && echo "OK: all learning sources are allowlisted" \
  || (echo "FAIL: unknown learning source"; exit 1)
```

The check is: every `Src*` constructor used in code is in
this file.

## 3. The discipline

The discipline of this list is:

- **Closed by default.** A new source is added by editing
  this file, with a follow-up ADR, in the same PR as the
  code that introduces the source.
- **Authority-bearing by construction.** A source on this
  list is, by definition, an authority-bearing signal (per
  Package 1's classification). It is subject to the replay
  gate (Package 3).
- **Sources depend on packages.** S-02 and S-03 depend on
  Package 2 (semantic commitments). S-04 depends on
  Package 7 (episodic memory). S-05 depends on Package 9
  (metacognition). A source whose underlying package is
  not landed is `canonical-flag-off`.
- **No LLM signals.** The closure plan explicitly rejects
  LLM outputs as a learning source. The LLM is
  supplier-flag-off; its outputs are not authority-bearing.
  A future ADR may revisit this; the discipline is
  "no silent LLM-to-learning channel".
- **No raw user text.** A learning update may not consume
  raw user text directly. The text must first be
  parser-typed into a `Commitment`, `Outcome`, or
  `Evaluation`. This is the closure plan's "typed, not
  text" discipline.

## 4. Acceptance criteria for F-04

F-04 is closed when:

- [ ] This file is merged with S-01 through S-05 as the
      initial closed list.
- [ ] The CI gate of §2 is in place; CI is green.
- [ ] Every `Src*` constructor in `src/QxFx0/Learning/` and
      `test/Test/Suite/LearningContour/` is in this file.
- [ ] Future additions to the list follow the discipline of §3.
