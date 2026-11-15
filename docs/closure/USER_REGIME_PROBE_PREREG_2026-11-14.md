# Pre-registration — targeted user-regime probe: the relative contour branch and the drift-move band (2026-11-14)

- **Status**: PRE-REGISTERED; capture and verification recorded below.
- **Trigger**: the 2026-11-13 capture measured **0 relative contour exits**
  and **0 drift-branch moves** over 80 turns. Post-landing analysis
  (`USER_REGIME_CAPTURE_PREREG_2026-11-13.md`, "Quantification of findings
  1 and 4") showed this is structural: gradual escalation lowers the EMA
  baseline faster than the score falls, so it always lands in the absolute
  floor, and the drift band is narrower still. Neither branch has ever been
  observed firing in a live session.
- **Scope**: one authored probe corpus (19 turns), one eval-only predictor,
  one safety pin, one allowlist entry. No runtime semantics, no threshold,
  no encoder constant, no trace field, no GF/prompt-file change.
- **Owner decision**: 2026-11-14 — "точечный probe (evidence-only, no
  behaviour change)" chosen as the next step after the M7 comparator.

## Question

Two claims about the frozen v1 model are testable and have never been tested
directly:

1. **The relative contour branch is reachable** — a sudden *moderate* drop
   from a calm, high baseline (`0.05 ≤ score < baseline − 0.25`) exits the
   contour through the *relative* branch, not the absolute floor.
2. **The drift-move band is reachable and narrow** — a turn with
   `score ≥ 0.05`, `prior − score > 0.20` and earned negative evidence fires
   an ontological move *without* a contour exit, i.e. the band
   `[baseline − 0.25, baseline − 0.20)` is non-empty in practice.

A third claim follows from the EMA arithmetic and is the control:

3. **The same utterance stops exiting once the baseline adapts** — after a
   run of mild turns the identical negative turn is read as ordinary
   (inside the contour, no move). This is the mechanism behind finding 1.

This is evidence, not a benchmark: the probe is authored to reach the
branches, and its counts describe the probe, not the population.

## Corpus design (4 dialogues × 19 turns)

The v1 encoder is a linear feature sum, so each prompt is designed by
marker count. All prompts are topic-free after turn 1: the encoder receives
`ssLastTopic` (the *previous* turn's best topic), and no prompt after turn 1
contains the turn-1 topic word, so `topicBit = 0` from turn 2 on and the
prediction does not depend on the classifier's topic extraction.

| dialogue | arc | design | predicted |
|---|---|---|---|
| `probe-rel-exit` | calm, calm, **negative**, recover | two calm turns establish `baseline = 0.4295` (question + address + 2 connectives + 2 alternatives), then one moderate negative turn (3 distress + 1 agency-negative, score `0.121`) | **1 relative exit** on t3 (`0.121 < 0.4295 − 0.25 = 0.1795`, margin `0.0585`), Protocol A returns on t4 |
| `probe-drift-move` | calm, **drift**, recover | calm baseline `0.4175`, then a turn with one distress + one connective + one agency-negative (score `0.197`) | **1 drift move** (`mirror_state`, gate **not** passed), **no exit** (band `[0.1675, 0.2175)`, margin `0.0295` to the exit, `0.0205` to the drift threshold) |
| `probe-control` | calm, mild, recover | same baseline, then one distress + one connective + one agency-positive (score `0.262`) | **no exit** (margin `0.0945`), **no move** (drift threshold `0.2175`, margin `0.0445`) |
| `probe-ema-adapts` | calm, **7 mild**, negative | calm `0.4295`, seven mild turns (`0.262`) pull the baseline to `0.3031`, then the **same negative utterance as `probe-rel-exit` t3** | **no exit** (threshold `0.0531`, margin `0.0679`), **no move** (drift threshold `0.1031`, margin `0.0179`) |

The corpus contains **no acute crisis marker**: a new pin
(`userRegimeProbeCorpusStaysInProtocolA` in `Test.Suite.CrisisGuard`) runs
the canonical `detectCrisisTrigger` over every prompt, so the exclusion is
enforced by the runtime's own lexicon rather than by a copy in the driver.
The single Protocol B turn is a contour exit (the law working), not a
safety event.

Corpus: `spec/eval/user_regime_probe_2026-11-14.tsv`, sha256
`55265d15…57ea27`.

## Predictor

`scripts/eval/r5_predict.py` (eval-only, read-only) mirrors
`encodeR5` → `userConatusScore` → `outsideViabilityContour` →
`updateUserBaseline` → `planOntologicalMove` in ~700 lines (self-test
included), parses the
marker lexicons from `src/QxFx0/Semantic/Markers.hs` (one source of truth),
and **pins every contour/move constant against the Haskell source** — a
runtime change makes the tool fail loudly instead of predicting stale
numbers.

Fidelity is measured, not assumed: `--verify-capture
reports/eval_runs/user-regime-20261113` recomputes all five axes, the score
and the post-turn baseline for every recorded turn and reports **80/80 exact
matches** against the 2026-11-13 capture.

The prediction table below is the tool's own output for this corpus
(`r5_predict.py --corpus …`), not a hand transcription:

```
dialogue              turn  arc       score   prior   thresh  exit           move                 gate   base_after
probe-rel-exit          1  calm     +0.4295       -       -  -              -                    None   +0.4295
probe-rel-exit          2  calm     +0.4295  0.4295  0.1795  -              -                    None   +0.4295
probe-rel-exit          3  negative +0.1210  0.4295  0.1795  relative       -                    None   +0.3734
probe-rel-exit          4  recover  +0.2900  0.3734  0.1234  -              -                    None   +0.3582
probe-drift-move        1  calm     +0.4175       -       -  -              -                    None   +0.4175
probe-drift-move        2  drift    +0.1970  0.4175  0.1675  -              mirror_state         False  +0.3774
probe-drift-move        3  recover  +0.2900  0.3774  0.1274  -              -                    None   +0.3615
probe-control           1  calm     +0.4175       -       -  -              -                    None   +0.4175
probe-control           2  mild     +0.2620  0.4175  0.1675  -              -                    None   +0.3892
probe-control           3  recover  +0.2900  0.3892  0.1392  -              -                    None   +0.3712
probe-ema-adapts        1  calm     +0.4295       -       -  -              -                    None   +0.4295
probe-ema-adapts        2  mild     +0.2620  0.4295  0.1795  -              -                    None   +0.3990
probe-ema-adapts        3  mild     +0.2620  0.3990  0.1490  -              -                    None   +0.3741
probe-ema-adapts        4  mild     +0.2620  0.3741  0.1241  -              -                    None   +0.3537
probe-ema-adapts        5  mild     +0.2620  0.3537  0.1037  -              -                    None   +0.3371
probe-ema-adapts        6  mild     +0.2620  0.3371  0.0871  -              -                    None   +0.3234
probe-ema-adapts        7  mild     +0.2620  0.3234  0.0734  -              -                    None   +0.3122
probe-ema-adapts        8  mild     +0.2620  0.3122  0.0622  -              -                    None   +0.3031
probe-ema-adapts        9  negative +0.1210  0.3031  0.0531  -              -                    None   +0.2700
```

## Bars

| # | Bar | Measure |
|---|---|---|
| B1 | Predictor is self-tested, allowlisted, and faithful | `--self-test` green (12 cases); `check_architecture.sh` rule [24] green; entry in `PYTHON_SUPPLIER_ALLOWLIST.md` §1; `--verify-capture` reports 80/80 exact matches on the 2026-11-13 capture |
| B2 | Corpus is structurally valid and safe | 19 rows, 4 dialogues, contiguous turns; `detectCrisisTrigger == Nothing` for every prompt (new pin in `Test.Suite.CrisisGuard`) |
| B3 | Capture completes and stays inside the two-protocol law | 19/19 turns persisted, 19/19 traces carry `trcUserRegime`, **0 hard-trigger** Protocol B, `protocol_b == contour_exits == 1` |
| B4 | The relative branch fires | `probe-rel-exit` t3: `outside_contour = true`, `exit_class = relative` (not `absolute_floor`), score `0.121`, prior baseline `0.4295` |
| B5 | The drift move fires without an exit | `probe-drift-move` t2: `move = mirror_state`, `affirm_gate_passed = false`, `outside_contour = false`, score `0.197`, prior baseline `0.4175` |
| B6 | The control stays calm | `probe-control` t2: no exit, no move, score `0.262` |
| B7 | The same utterance stops exiting after adaptation | `probe-ema-adapts` t9: no exit, no move, score `0.121`, prior baseline `0.3031` |
| B8 | The whole trajectory matches the prediction | every one of the 19 turns: measured score and post-turn `ur5Baseline` equal the predicted values within `1e-9`; every turn's `outside_contour` and `move` match the table |
| B9 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups) |

B4–B7 are the substance. B8 is the strong form: it checks the *entire*
trajectory, so a lucky hit on the headline turn cannot pass while the model
is wrong elsewhere.

## Residual risks (accepted, documented)

1. **Probe corpus, not a sample.** The dialogues are authored to reach the
   branches. Counts are not population estimates and must not be quoted as
   such.
2. **The predictor mirrors ~17 inline encoder constants** (the bases and
   increments inside `encodeR5`) that are not machine-pinned; only the
   contour and move constants are parsed from the source. The self-test pins
   the neutral point and several exact scores, which catches most silent
   changes, but a coordinated edit of the encoder and the predictor would
   not be caught by construction.
3. **Margins are small by nature.** The drift band is `0.05` wide and the
   EMA moves the threshold by ~`0.03` per turn, so the drift prediction
   carries a `0.0205` margin and the adapted-baseline "no move" `0.0179`.
   The predictor's 80/80 fidelity on measured data is what makes these
   margins usable; a single marker-count error would flip them.
4. **One turn, one process.** Session state is restored from the DB each
   turn, so a restore defect would show up as a regime discontinuity. That
   is desirable, but a turn's regime depends on the previous turn's
   persisted state.
5. **Protocol B by design.** One contour-exit Protocol B turn is the
   intended measurement; the hard gate is not exercised (and must not be,
   on a bulk capture).
6. **Cost and isolation.** 19 turns × one process per turn ≈ 12 min; the
   capture uses its own DB and must not run beside another memory-heavy job.

## Result (2026-11-14)

Capture: `reports/eval_runs/user-regime-probe-20261114/` — 19/19 turns,
19/19 regime records, one process per turn, 14:04:42Z → 14:11:55Z
(~23 s/turn). Binary sha256 `882df14d…60441c`, the same runtime as the
2026-11-13 capture; `git_head 3a0be69` with 7 dirty files (test, docs,
eval tool and the corpus — no runtime source). The corpus sha256 matches
the pre-registration (`55265d15…57ea27`).

Measured headline: **1 relative contour exit** (`{'relative': 1}`,
Protocol B cause `contour_exit`), **2 moves**
(`{'mirror_state': 1, 'open_alternative': 1}`), 0 hard-trigger Protocol B,
residual mean 0.104 / max 0.380, window max 0.225.

### Bars

| # | Verdict | Evidence |
|---|---|---|
| B1 | **PASS** | `--self-test` 12/12 at capture time (13/13 now: the measured-topic replay case was added after the capture and is diagnostic-only); `check_architecture.sh` rule [24] green; allowlist §1 (eleven tools); `--verify-capture` **80/80** on `user-regime-20261113` and **19/19** on this probe run |
| B2 | **PASS** | 19 rows / 4 dialogues / contiguous turns; new pin `userRegimeProbeCorpusStaysInProtocolA` (`Test.Suite.CrisisGuard`) asserts 19 prompts and `detectCrisisTrigger == Nothing` for each; filtered suite **22/22** green (`QXFX0_UNIT_SUITE=crisisguard`) |
| B3 | **PASS** | driver gate 8/8: turns persisted 19, regime records 19, missing regime 0, hard-trigger Protocol B 0, `protocol_b == contour_exits == 1`, encoder versions `[1]`, residual samples 15, window samples 15 |
| B4 | **PASS** (substance) | `probe-rel-exit` t3: `outside_contour = true`, `exit_class = relative` (not `absolute_floor`), score `0.1210`, Protocol B cause `contour_exit`. One pre-registered number corrected: the prior baseline is **0.4436**, not `0.4295`, so the margin is `0.0726` (`0.1210 < 0.1936`), not `0.0585` |
| B5 | **PASS** | `probe-drift-move` t2: `move = mirror_state`, `affirm_gate_passed = false`, `outside_contour = false`, score `0.1970`, prior baseline `0.4175`; distance `0.12775 → 0.09775`. Margins: `0.0295` to the exit threshold, `0.0205` to the drift threshold |
| B6 | **PASS** | `probe-control` t2: score `0.2620`, no exit, no move, prior baseline `0.4175` |
| B7 | **FAIL** | `probe-ema-adapts` t9: no exit ✓, but a move **did** fire — `open_alternative`, `affirm_gate_passed = true` (resonance `0.70 > 0.55`), score `0.2110` (predicted `0.1210`), prior baseline `0.3661` (predicted `0.3031`) |
| B8 | **FAIL** | 11/19 turns mismatch the pre-registered trajectory (table below); the post-hoc measured-topic replay is 0/19 |
| B9 | **PASS** | matrix 2026-11-14 (`reports/eval_runs/_logs/matrix-20261114/`): 10/10 steps exit 0, tree byte-identical start→end — unit **1846**, fast **1939**, property 244, integration 47, main runtime 106 + http 23, slow 190 (runtime 106 / state 50 / http 23 / lifecycle 11) = **4 395 cases**, 0 errors, 0 failures |

B4–B7 were the substance. The two headline claims held: **the relative
contour branch fired** and **the drift-move band fired**, both for the
first time in a live session. The control claim held for the contour
(no exit after EMA adaptation) but **failed for the move layer**, and the
strong trajectory bar failed on 11 of 19 turns.

### B8: the 11 misses are one feature

| dialogue | turn | predicted score | measured | Δ | cause |
|---|---|---|---|---|---|
| `probe-rel-exit` | 2 | 0.4295 | 0.5070 | +0.0775 | topic hit «ответственность» (resonance clamps at 1.0) |
| `probe-rel-exit` | 3 | 0.1210 | 0.1210 | 0 | baseline only (carried from t2) |
| `probe-rel-exit` | 4 | 0.2900 | 0.2900 | 0 | baseline only |
| `probe-control` | 3 | 0.2620 | 0.3800 | +0.0900 | topic hit «разобраться» |
| `probe-ema-adapts` | 3–8 | 0.2620 | 0.3520 | +0.0900 | topic hit «хочу» |
| `probe-ema-adapts` | 9 | 0.1210 | 0.2110 | +0.0900 | topic hit «хочу» inside «не хочу»; move flips |

Every miss is exactly `+0.09` (the topic bit:
`0.25·0.20 + 0.20·0.20 = 0.09`) or `+0.0775` when resonance is clamped at
`1.0`. The two turns marked "baseline only" have the correct score; only
the EMA anchor inherited from t2 differs.

The pre-registered design assumed "no prompt after turn 1 contains the
turn-1 topic word, so `topicBit = 0` from turn 2 on". **That assumption is
false**, and the measurement shows why it could not hold:

* `probe-rel-exit` t2 repeats «ответственность» in the instrumental case
  («ответственностью»), which *contains* the nominative form as a
  substring;
* the mild turns repeat «хочу» and «разобраться»;
* the runtime's `bestTopic` is the **intent-derived focus** (`resolveCarryTopic`
  over the prepared intent), not the definitional topic. Measured
  `scene_request` per dialogue: `probe-rel-exit` — ответственность,
  ответственность, грустно, разобраться; `probe-drift-move` —
  ответственность, тревожно, разобраться; `probe-control` —
  ответственность, хочу, разобраться; `probe-ema-adapts` —
  ответственность, хочу ×7, грустно. The definitional turn's focus is
  «ответственность» (the last mentioned topic), never «свобода».

Attribution is complete: replaying the **measured** topics through the same
corpus and the same predictor gives **0/19 mismatches**
(`r5_predict.py --corpus … --topics-from reports/eval_runs/user-regime-probe-20261114`,
a post-hoc diagnostic, not a prediction). The encoder, score, contour, EMA
and move replica are exact; the only unpredictable input is `bestTopic`.

### Finding: `topicBit` is a repeated-word feature, and it is not negation-safe

`encodeR5` (`src/QxFx0/User/R5.hs`):

```haskell
norm = normalizeText rawInput
topicHit =
  not (T.null lastTopic)
    && T.length lastTopic >= 3
    && lastTopic `T.isInfixOf` norm
```

`norm` is the lowercased raw text; the negation blanking that protects the
agency axis is applied only to `cleaned`, never to `norm`, and `lastTopic`
is matched unnormalized. So:

1. **Any repeated content word counts as topic continuity.** «хочу» carried
   out of a mild turn is a hit inside the next turn's «не хочу»; the
   distress turn is then read as *more* resonant (+0.20) and *more*
   consolidated (+0.20), i.e. `+0.09` on the viability score.
2. **That is enough to flip the move layer.** At `probe-ema-adapts` t9 the
   topic bit lifts resonance from `0.50` to `0.70`, above the `0.55`
   gate, so the act branch (`striving = −1`, resonance above the gate)
   fires and `open_alternative` is chosen. B7 predicted "no move" because
   it assumed resonance `0.50` and therefore a closed gate. The act itself
   is genuine (the speaker's own `striving −1`, not a quotation), so this
   is **not** the mention-vs-use class of finding 3; the defect is the
   gate's input — resonance `0.70` was manufactured by a repeated word on
   a turn with no question and no address markers.
3. The contour control itself still holds: with or without the topic bit,
   t9's score (`0.121` or `0.211`) stays above the adapted threshold
   (`0.0531` or `0.1161`). The EMA mechanism is confirmed; it simply does
   not protect the move layer, which reads the act branch before any
   baseline comparison.

This is a finding about the frozen v1 encoder, not about the probe. It is
**not** fixed here: `encodeR5` is runtime semantics, and a change needs its
own pre-registration and a `currentMathVersion` bump.

### Residual flag on the contour-exit turn

`probe-rel-exit` t3 carries `ur5PredictionError = 0.38`, above the `0.35`
threshold. The trace's `uraAnomaly` is single-valued
(`analyzeUserRegime`: contour exit first, then residual, then window), so
the aggregate `flags` counter shows only `{'user_contour_exit': 1}`. The
per-turn record's multi-valued `flags` list carries **both**
`user_contour_exit` and `user_model_high_residual` — the residual flag is
recorded, not lost. Two views of the same turn, no missing anomaly.

### What the probe established

1. **The relative contour branch is reachable** (first live observation):
   a sudden moderate drop from a calm baseline exits through `relative`,
   with a `0.0726` margin. The 2026-11-13 finding that *gradual* escalation
   always lands in the absolute floor is not contradicted — the branch
   needs a step, not a slope.
2. **The drift-move band is reachable and narrow** (first live
   observation): `mirror_state` fired with the gate closed, `0.0295` from
   the exit threshold and `0.0205` from the drift threshold — the band is
   `0.05` wide and the prediction was exact on that turn.
3. **EMA adaptation protects the contour but not the move layer**: the
   same negative utterance that exited at baseline `0.4436` does not exit
   at `0.3661`, yet it still triggers an ontological move — via the act
   branch, on a topic-bit artefact.
4. **`bestTopic` is an intent-focus surface word, not a semantic topic**.
   Any pre-registration that assumes topic-free prompts must check the
   runtime's topic extraction, not the prompt text. The probe's own
   design assumption was falsified by the measurement.
5. **The predictor is faithful** (80/80 and 19/19 exact) but its input
   `bestTopic` is not predictable from the corpus. A future probe should
   either replay measured topics or make the topic bit impossible.

### Residual-risk update

* Risk 2 (predictor mirrors inline constants) did **not** materialize:
  80/80 and 19/19 exact matches.
* Risk 3 (small margins) materialized differently than expected: the
  arithmetic margins were right, but the topic input moved whole
  trajectories by up to `0.09` per turn — larger than every margin in the
  design.
* New risk, accepted: `bestTopic` is a raw surface word. A probe that
  cannot control it cannot predict the move layer, even with a perfect
  encoder replica.
* The probe remains a probe: 4 authored dialogues, counts are not
  population estimates.

### Follow-ups (not in this landing)

1. `topicBit` negation safety and semantic-topic matching — runtime
   change, needs pre-registration and a math-version bump.
   **Landed 2026-11-15** for the measured defect class: encoder v2
   (`QxFx0.User.R5.topicContinuity`) normalizes the topic side, matches
   whole words only and rejects a negated occurrence;
   `docs/closure/USER_REGIME_TOPIC_BIT_PREREG_2026-11-15.md`. Semantic
   topic matching (morphology / aboutness) remains open — v2 deliberately
   loses two instrumental-case continuities.
2. Whether the act branch should require address/question evidence, not
   only `resonance > 0.55` — the probe shows the gate can be opened by a
   repeated word alone. A design question, not a defect in the move
   search.
3. Whether the regime should surface *both* anomaly flags in the
   aggregate, or keep the single-valued precedence — an observability
   decision, not a defect.

