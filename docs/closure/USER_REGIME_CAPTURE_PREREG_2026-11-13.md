# Pre-registration — multi-turn user-regime capture and trace reader (2026-11-13)

- **Status**: PRE-REGISTERED; implementation and verification recorded below.
- **Trigger**: the concept-v3 regime (`trcUserRegime`) is replay-visible
  but has almost no multi-turn evidence. Measured on the local trace DB
  on 2026-11-12: 578 sessions / 655 traces, `trcUserRegime` present in
  570, `ur5PredictionError` non-empty in **16** (max 0.080, none above
  the 0.35 flag threshold), `urtOntologicalMove` fired **0** times, and
  only **10** sessions have more than one turn. The eval harness runs
  isolated one-turn sessions, so it can never produce this evidence.
- **Scope**: one authored probe corpus, one read-only Python reader, one
  capture driver, one safety pin, one allowlist entry. No runtime
  semantics, no threshold, no encoder constant, no trace field, no
  corpus/GF/prompt-file change.
- **Owner decision**: 2026-11-12, item (2) of the follow-up list.

## Why this is evidence, not a benchmark

The runtime already /computes/ the regime every turn; what is missing is
a record of it over a dialogue. This capture produces the first such
record: per-turn `UserR5State`, viability score, baseline, contour
membership, prediction residual, bounded residual window, and the
ontological move decision. It does not score the runtime and it does not
gate anything.

The corpus is a **probe corpus**, authored for this capture, not a
random sample of production dialogue. Its counts describe the probe, not
the population. Every prediction below is a hand-derived expectation
from the frozen v1 constants; a miss is a finding about the model, not a
runtime defect.

## Corpus design (10 dialogues × 8 turns)

| id | arc | predicted regime shape |
|---|---|---|
| `calm-def` | calm definitional chain, topic continuity | 0 exits, 0 moves, small residuals |
| `calm-alt` | calm, alternative-opening markers | 0 exits, 0 moves, counterfactual high |
| `decoy-pessimism` | philosophical pessimism (Schopenhauer/Camus) | 0 Protocol B; **predicted** ≥1 move — the v1 encoder cannot tell a doctrinal `being−` mention from the user's own act |
| `fatigue-inside` | concept v3 §9 edge case: «мне всё надоело» | 0 exits, 0 moves (the §9 invariant) |
| `pileup-exit` | escalation to a marker pile-up | **predicted** 1 absolute-floor exit and 1 drift-branch move on turn 5 (hand-derived score −0.015 against a baseline of 0.224) |
| `move-act` | negative act + addressed question | **predicted** ≥1 act-branch move with `ompAffirmGatePassed = true` |
| `recovery` | pile-up → addressed recovery question | **predicted** 1 absolute-floor exit, then a recovery turn whose hand-derived residual is **0.344** — just *below* the 0.35 flag threshold, so `user_model_high_residual` is predicted **not** to fire on the clearest recovery turn. The near-miss is the finding: the threshold is sized for a jump the v1 encoder barely produces |
| `topic-continuity` | 8 turns on «свобода» | 0 exits, 0 moves, consolidation/resonance above `calm-def` |
| `oscillation` | calm/negative alternation | 0 exits, 0 sustained-residual flag; window mean below 0.35 |
| `mixed-decoy` | absurde/despair philosophy + recovery | 0 Protocol B; **predicted** ≥1 move on a definitional `being−` question (same mention-vs-use class) |

The corpus deliberately contains **no acute crisis marker**: Protocol B is
safety-critical, already pinned by `Test.Suite.CrisisGuard`, and a bulk
capture must not generate real crisis surfaces. A new pin
(`crisisCorpusHasNoAcuteMarkers`) runs the canonical
`detectCrisisTrigger` over every prompt, so the exclusion is enforced by
the runtime's own lexicon rather than by a copy in the driver.

## Reader

`scripts/eval/user_regime_report.py`:

- read-only SQLite (`mode=ro`), unwraps
  `{replayTraceEnvelopeVersion, trace:{…}}` from
  `turn_quality.replay_trace_json`;
- per-session summary + per-turn table (`--verbose`), JSON output
  (`--json`);
- filters by `--session-prefix`;
- derives the three `analyzeUserRegime` flags with the same order and
  semantics as `QxFx0.Observability.TraceAnalysis`;
- classifies a contour exit as `absolute_floor` or `relative` from
  `ur5ConatusScore` against `vcAbsoluteFloor`;
- `--self-test` covers envelope unwrap, missing regime, null residuals,
  flag precedence, aggregation, prefix filtering, exit classification,
  and **pins the mirrored constants against the Haskell source**
  (`userResidualAnomalyThreshold`, `vcAbsoluteFloor`).

## Driver

`scripts/run_user_regime_capture.sh <run_id> [corpus.tsv]`:

- validates the corpus shape (4 columns, contiguous turns, unique ids);
- resolves the binary once (`cabal list-bin`), records its sha256;
- uses a **dedicated DB** (`reports/eval_runs/<run_id>/capture.db`) via
  `QXFX0_DB`, never the operator's local DB;
- one process per turn (`--session cap-<run_id>-<dialogue> --input … --json`),
  which is the only multi-turn path the CLI offers;
- runs the reader, then a structural gate: turns persisted == rows run,
  regime records == rows run, 0 Protocol B, encoder version == 1,
  residual samples == rows − dialogues;
- `QXFX0_CAPTURE_LIMIT=<n>` runs a prefix (smoke test).

## Bars

| # | Bar | Measure |
|---|---|---|
| B1 | Reader is self-tested and allowlisted | `--self-test` green (≥ 12 cases); `check_architecture.sh` rule [24] green; entry in `PYTHON_SUPPLIER_ALLOWLIST.md` §1 |
| B2 | Corpus is structurally valid and safe | 10 × 8 = 80 rows, contiguous, unique; `detectCrisisTrigger == Nothing` for every prompt (new pin in `Test.Suite.CrisisGuard`) |
| B3 | Capture completes | 80/80 turns persisted, 80/80 traces carry `trcUserRegime`, **0 hard-trigger** Protocol B turns. A contour exit *is* Protocol B by the two-protocol law, so contour-exit Protocol B turns are expected and counted (the bar as first written said "0 Protocol B" — see the correction note in the Result) |
| B4 | Residual evidence exists | `ur5PredictionError` non-null in 70/80 turns (turn 1 of each dialogue has none); `ur5WindowMean` non-null from turn 2 |
| B5 | The regime fires on the probe corpus | contour exits and moves are counted and each prediction above is marked hit/miss in the Result. **Non-binding**: a miss is a finding |
| B6 | Reader reproduces the DB | reader totals equal an independent SQL count for the same prefix; the DB mtime is unchanged by the reader |
| B7 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups) |

## Residual risks (accepted, documented)

1. **Probe corpus, not a sample.** The 10 dialogues are authored to
   exercise the branches. Counts are not population estimates and must
   not be quoted as such.
2. **Predictions are hand-derived.** `topicBit` depends on the
   classifier's `lastTopic`, which this pre-registration cannot compute
   exactly, so some predicted residuals/exits may miss. Misses are
   reported, not patched.
3. **The reader mirrors three constants.** Two are numeric and pinned to
   the Haskell source by `--self-test`; the third is the string tag
   `"contour_exit"`, pinned by a case. A semantic change that keeps the
   constants is not caught.
4. **Cost and isolation.** 80 turns × one process per turn ≈ 1.6 h; the
   capture must not run alongside another memory-heavy job. It uses its
   own DB, so a crash cannot corrupt the operator's trace history.
5. **Protocol B excluded by design.** The capture is a regime probe, not
   a crisis-path exercise. The hard gate is covered by unit pins; the
   corpus pin keeps the capture in Protocol A.
6. **One turn, one process.** Session state is loaded from the DB each
   turn, so the capture also exercises the persistence/restore path; a
   restore defect would show up as a regime discontinuity. That is
   desirable, but it means a turn's regime depends on the previous
   turn's persisted state, not on in-process memory.

## Result (2026-11-13)

### Bar correction (recorded, not hidden)

B3 was pre-registered as "0 Protocol B turns". That wording conflated the two
causes of Protocol B: a hard lexical trigger (a safety event) and a viability
contour exit (the law working). The capture produced **2 contour-exit Protocol
B turns and 0 hard-trigger turns**; the raw data was never in question, the bar
was. The corrected bar is "0 hard-trigger Protocol B, and every Protocol B is a
contour exit". The driver gate was corrected in the same change and re-run
against the same DB (`QXFX0_CAPTURE_SKIP_EVAL=1`), so the correction is visible
in the tool, not only in this document.

### Bars

| # | Bar | Verdict | Evidence |
|---|---|---|---|
| B1 | Reader self-tested and allowlisted | **PASS** | `--self-test` 15/15; `check_architecture.sh` green including rule [24]; allowlist §1 row added (nine eval-only tools) |
| B2 | Corpus valid and safe | **PASS** | 10 dialogues × 8 turns = 80 rows, contiguous, unique; new pin `user-regime capture corpus stays in Protocol A` in `Test.Suite.CrisisGuard` runs `detectCrisisTrigger` over all 80 prompts (`CrisisGuard` 21/21 green) |
| B3 | Capture completes | **PASS (corrected)** | 80/80 turns persisted, 80/80 regime records, 0 missing, **0 hard-trigger** Protocol B, **2** contour-exit Protocol B (`protocol_b == contour_exits`) |
| B4 | Residual evidence exists | **PASS** | `ur5PredictionError` non-null in **70/80** turns (turn 1 of each dialogue has none), `ur5WindowMean` non-null in 70/80 |
| B5 | Regime fires on the probe corpus | **PASS as a measurement** | 2 absolute-floor exits, 4 moves (all `mirror_state`, all with `ompAffirmGatePassed = true`), 0 relative exits, 0 sustained-residual flags. Prediction hits/misses below |
| B6 | Reader reproduces the DB | **PASS** | capture DB: reader equals an independent SQL count — 80 rows / 80 regime / 70 residual / 70 window / 2 Protocol B / 2 exits / 4 moves, residual max 0.344; the DB's mtime and size are unchanged by the reader (`1794581168` / `122937344` before and after). Operator DB: 655 scanned / 570 regime / 554 sessions / 16 residuals / max 0.080 / 0 moves, matching the measurement made before the reader existed. Opened `mode=ro` |
| B7 | Landing matrix | **PASS** | matrix 2026-11-13 (`reports/eval_runs/_logs/matrix-20261113/`): 10/10 steps exit 0, tree byte-identical start→end — unit 1845, fast 1938, property 244, integration 47, main runtime 106 + http 23, slow 190 (runtime 106 / state 50 / http 23 / lifecycle 11) = **4 393 cases**, 0 errors, 0 failures |

Capture identity: corpus sha256 `0ea4cc34…c1e412`, binary sha256
`882df14d…60441c`, `git_head 847245b`, 13 uncommitted paths (the landing
change set), started 13:57:34Z, last turn 14:46:08Z (80 turns, ~36 s/turn),
dedicated DB `reports/eval_runs/user-regime-20261113/capture.db`.

### Predictions: hit / miss

| dialogue | prediction | measured | verdict |
|---|---|---|---|
| `calm-def`, `calm-alt`, `topic-continuity`, `oscillation` | 0 exits, 0 moves | 0 / 0 each | **hit** |
| `topic-continuity` | consolidation/resonance above `calm-def` | score max 0.425 vs 0.388 | **hit** |
| `fatigue-inside` | 0 exits, 0 moves (concept §9) | 0 / 0; the «надоело» turn scores 0.149, well above the 0.05 floor | **hit** |
| `decoy-pessimism` | ≥1 move on a doctrinal `being−` mention | **2** moves (t2, t4), both `mirror_state` | **hit** |
| `mixed-decoy` | ≥1 move on a definitional `being−` question | **1** move (t6) | **hit** |
| `move-act` | ≥1 act-branch move with gate passed | **1** move (t2), gate passed | **hit** |
| `pileup-exit` | 1 absolute-floor exit **and** 1 drift move on t5 | 1 exit (score −0.015, baseline 0.192) but **0 moves** | **partial miss** — see finding 4 |
| `recovery` | 1 absolute-floor exit, then residual **0.344** (below the 0.35 flag) | exit on t3; residual **0.344**; flag did not fire | **hit** |
| `oscillation` | window mean below 0.35, no sustained flag | window max 0.168, no flag | **hit** |

### Findings

1. **The relative contour branch is a narrow band, and escalation misses it.**
   `outsideViabilityContour` checks the absolute floor first, so a relative
   exit needs `0.05 ≤ score < baseline − 0.25`, i.e. a baseline above ~0.30.
   Both exits in the capture were absolute-floor (score −0.015 against
   baselines 0.192 / 0.196): the escalation lowered the EMA baseline faster
   than the score fell, and the floor caught the turn first. The relative
   branch is reachable in principle (a calm high baseline plus a moderate
   negative turn), but this probe never produced it — a target for the
   calibration phase, not a defect.
2. **The residual flag is inert at v1 jump sizes.** Across 70 residual samples
   the maximum is **0.344** — the clearest recovery turn lands 0.006 below the
   0.35 `user_model_high_residual` threshold. No high/sustained flag fired.
   The persistence transition model *is* wrong on recovery turns, but the
   threshold is sized above the jump the encoder actually produces. Either the
   threshold or the transition model has to move; the capture cannot say which.
3. **Mention vs use: 3 of 4 moves are doctrinal, not the user's state.**
   `decoy-pessimism` t2/t4 («жизнь бессмысленна — так утверждал Шопенгауэр?»,
   «абсурд — честный ответ на бессмысленность?») and `mixed-decoy` t6
   («отчаяние — это когда нет смысла?») fire `MoveMirrorState` because the v1
   encoder reads a quoted `being−` as the speaker's act. Only `move-act` t2
   is a first-person act. The move layer inherits the encoder's ambiguity;
   separating mention from use is a calibration target.
4. **The drift branch and the contour exit are mutually exclusive on the same
   turn.** The predicted drift move on `pileup-exit` t5 did not fire: the exit
   switches the turn to Protocol B, where the move layer does not run. The
   drift branch's firing window is `0.05 ≤ score < baseline − 0.20` (baseline
   above ~0.25), which is even narrower than the exit band. All 4 measured
   moves are act-branch moves (`ompAffirmGatePassed = true`, resonance above
   the 0.55 gate).
5. **The §9 invariant holds.** «Мне всё надоело» stays inside the contour
   (score 0.149), and the fatigue dialogue produces no exit and no move.

### Cost

80 turns at ~36 s/turn (48.5 min wall), one process per turn, dedicated DB.
No turn hit the 600 s per-turn timeout; no stall of the 4 987 s class
recurred.
