# Pre-registration — user-regime encoder v2: whole-word, negation-safe topic continuity (2026-11-15)

- **Status**: PRE-REGISTERED. Predictions below are stated **before** the
  runtime change; the Result section is filled only after the post-fix
  captures.
- **Trigger**: the 2026-11-14 probe (`USER_REGIME_PROBE_PREREG_2026-11-14.md`)
  measured **B7 FAIL** and **B8 FAIL 11/19**, and attributed every miss to one
  feature: `encodeR5`'s topic-continuity bit. Replaying the measured topics
  reproduced the trajectory exactly (0/19 mismatches), so the encoder, score,
  contour, EMA and move replica are not in question — only the topic bit.
- **Owner decision**: 2026-11-15 — fix `topicBit` first, ahead of the topic
  ADR, the second human rater and encoder calibration.
- **Scope**: one pure predicate in `QxFx0.User.R5` (`topicHit`), its export
  for tests, two version bumps, one math-change-log row, the eval predictor's
  rule table, the capture gate's expected encoder version, and new test pins.
  **No** threshold, weight, marker lexicon, contour, move-graph, crisis or
  trace-schema change.

## 1. The defect (measured, not inferred)

`encodeR5` (`src/QxFx0/User/R5.hs`, v1):

```haskell
norm = normalizeText rawInput
topicHit =
  not (T.null lastTopic)
    && T.length lastTopic >= 3
    && lastTopic `T.isInfixOf` norm
```

`norm` is lowercased but **not** negation-blanked (`blankAll` protects only
the agency axis), and `lastTopic` is matched **unnormalized** and as a **raw
substring**. Three consequences, all measured:

1. **Substring inside an unrelated word.** `move-act` t2 carries `bestTopic`
   «смысл»; the next utterance is «как ты думаешь, почему всё кажется
   бессмысленным?» — «смысл» is a substring of «бессмысленным» ("meaningless",
   the opposite of "meaning"). The bit adds `+0.09` to the score.
2. **Substring inside an inflected form.** `probe-rel-exit` t2 carries
   «ответственность»; the next utterance repeats it as «ответственностью»
   (instrumental). The bit fires — semantically correct, but by accident.
3. **A negated verb.** `probe-ema-adapts` t9 carries «хочу» out of a mild
   turn; the distress turn says «не хочу». The bit fires, resonance goes
   `0.50 → 0.70`, crosses the `0.55` affirm gate, and the **act branch** of
   the move layer fires (`open_alternative`) on a turn with no question and
   no address marker. This is the B7 flip.

The bit is worth `0.25·0.20 + 0.20·0.20 = 0.09` on the score, and `+0.20` on
resonance and consolidation. `+0.20` resonance is enough to open the gate.

## 2. The rule (v2)

The topic bit becomes a whole-word, negation-safe, normalized containment
test:

* **Normalize the topic side** exactly like the utterance (`toLower`,
  `ё → е`, whitespace collapsed). The measured topics are already lowercase,
  so this is a correctness fix with no measured effect (see §3).
* **Whole words only.** A word is a maximal run of letters, so punctuation
  never joins or splits a token. The topic's word sequence must appear as a
  **contiguous run** of the utterance's words. «смысл» no longer matches
  inside «бессмысленным»; «ответственность» no longer matches
  «ответственностью».
* **Negation-safe.** An occurrence whose **immediately preceding** word is a
  negation particle (`не`, `ни`, `нет`) is not topic continuity. An
  occurrence that is *not* negated still counts, so «не хочу сейчас, но потом
  хочу» remains a hit.
* The existing raw-topic guard (`T.length lastTopic >= 3`) is preserved.
* **No morphology.** Inflected forms are not lemmatized. This is a measured
  cost, not an oversight: two genuine continuities are lost (§3.4). A
  morphology-aware match is a later calibration item, not part of this
  change.

Sketch (the implementation is this shape):

```haskell
topicHit =
  not (T.null lastTopic)
    && T.length lastTopic >= 3
    && topicPresent (wordTokens (normalizeText lastTopic)) (wordTokens norm)
```

The predicate is exported as `topicContinuity` so the rule is pinned
directly, not inferred from axis arithmetic.

**Negation window: one token.** The data cannot distinguish one from two
(§3.5), and the narrower rule adds the least unmeasured behaviour. The
adverb case («не очень хочу») remains a documented limitation; the
two-token variant stays in the eval tool as a measured alternative so
widening it later has a baseline.

## 3. What-if (measured before the change)

The eval predictor gained `--what-if` and five topic rules
(`v1`, `normalized`, `boundary`, `negation`, `negation2`), each a faithful
replica of the candidate. The what-if runs the **same corpus, same
predictor, same EMA** under each rule and diffs against the runtime rule.
Both corpora are replayed with **measured** `bestTopic` values
(`--topics-from`), because `bestTopic` is the runtime's intent focus and is
not predictable from the corpus text (probe finding 4).

Artifacts: `reports/eval_runs/topic-bit-whatif-20261115/` (gitignored).

### 3.1 Probe corpus (19 turns)

```
mode        changed   exits  moves   delta range
v1                 0       1      2   +0.0000 .. +0.0000
normalized         0       1      2   +0.0000 .. +0.0000
boundary           1       1      2   -0.0775 .. +0.0000
negation           2       1      2   -0.0900 .. +0.0000
negation2          2       1      2   -0.0900 .. +0.0000

mode        dialogue            turn  ref score  ref exit  ref move          cand score  cand exit  cand move         delta    topic
boundary    probe-rel-exit          2  +0.5070  -         -                 +0.4295  -         -                 -0.0775  -
negation    probe-rel-exit          2  +0.5070  -         -                 +0.4295  -         -                 -0.0775  -
negation    probe-ema-adapts        9  +0.2110  -         open_alternative  +0.1210  -         mirror_state      -0.0900  -
negation2   probe-rel-exit          2  +0.5070  -         -                 +0.4295  -         -                 -0.0775  -
negation2   probe-ema-adapts        9  +0.2110  -         open_alternative  +0.1210  -         mirror_state      -0.0900  -
```

* `normalized` is a **no-op** on both corpora: every measured `bestTopic` is
  already lowercase without `ё`. It stays in the tool as the control that
  proves the normalization is not doing the work.
* `boundary` fixes the instrumental case but **not** the negated verb.
* `negation` fixes both. It does **not** remove the move on t9 — it changes
  its **class**: the manufactured resonance (`0.70`) closes the act branch,
  and the genuine drift (`0.3661 − 0.121 = 0.2451 > 0.20`, earned by
  atmosphere `0.67`) fires the **drift** branch instead (`mirror_state`,
  gate closed).
* `negation2` is identical to `negation` on both corpora.

### 3.2 80-turn capture (2026-11-13)

```
mode        changed   exits  moves   delta range
v1                 0       2      4   +0.0000 .. +0.0000
normalized         0       2      4   +0.0000 .. +0.0000
boundary           2       2      4   -0.0900 .. +0.0000
negation           2       2      4   -0.0900 .. +0.0000
negation2          2       2      4   -0.0900 .. +0.0000

mode        dialogue            turn  ref score  ref exit  ref move          cand score  cand exit  cand move         delta    topic
boundary    calm-def                3  +0.3880  -         -                 +0.2980  -         -                 -0.0900  -
boundary    move-act                2  +0.3850  -         mirror_state      +0.3075  -         mirror_state      -0.0775  -
negation    calm-def                3  +0.3880  -         -                 +0.2980  -         -                 -0.0900  -
negation    move-act                2  +0.3850  -         mirror_state      +0.3075  -         mirror_state      -0.0775  -
negation2   calm-def                3  +0.3880  -         -                 +0.2980  -         -                 -0.0900  -
negation2   move-act                2  +0.3850  -         mirror_state      +0.3075  -         mirror_state      -0.0775  -
```

No regime decision changes on the 80-turn capture: the same **2** contour
exits and the same **4** moves (same tags, same gate states). Only two
scores move, and the EMA carries the difference downstream without crossing
any threshold.

### 3.3 The two false hits removed

| turn | topic | text | why it is false |
|---|---|---|---|
| `move-act` t2 | «смысл» | «…всё кажется бессмысленным?» | substring of a word with the opposite meaning |
| `probe-ema-adapts` t9 | «хочу» | «…не хочу ничего делать» | negated verb |

### 3.4 The two genuine continuities lost (accepted cost)

| turn | topic | text | form |
|---|---|---|---|
| `probe-rel-exit` t2 | «ответственность» | «…связано с ответственностью?» | instrumental |
| `calm-def` t3 | «ответственность» | «как свобода связана с ответственностью?» | instrumental |

Both are real topic continuity that the v1 substring rule matched by
accident. A whole-word rule cannot see Russian inflection without a
morphology pass; adding one to `encodeR5` would make the encoder depend on
the morphology resource, which is a larger change and belongs to the
calibration phase. The measured cost is **two turns' scores**, with **no**
regime flip on either corpus. This is accepted, not hidden.

### 3.5 Window choice

`negation` (1 token) and `negation2` (2 tokens) produce byte-identical
trajectories on both corpora: the only negated hit present is «не хочу»,
where the particle is adjacent. The narrower rule is chosen by minimality.
The adverb class («не очень хочу») is a known limitation, stated in §2.

## 4. Predictions (stated before the fix)

### 4.1 Probe, post-fix trajectory

`r5_predict.py --corpus spec/eval/user_regime_probe_2026-11-14.tsv
--topic-mode negation --topics-from reports/eval_runs/user-regime-probe-20261114`

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
probe-control           3  recover  +0.3800  0.3892  0.1392  -              -                    None   +0.3875
probe-ema-adapts        1  calm     +0.4295       -       -  -              -                    None   +0.4295
probe-ema-adapts        2  mild     +0.2620  0.4295  0.1795  -              -                    None   +0.3990
probe-ema-adapts        3  mild     +0.3520  0.3990  0.1490  -              -                    None   +0.3905
probe-ema-adapts        4  mild     +0.3520  0.3905  0.1405  -              -                    None   +0.3835
probe-ema-adapts        5  mild     +0.3520  0.3835  0.1335  -              -                    None   +0.3778
probe-ema-adapts        6  mild     +0.3520  0.3778  0.1278  -              -                    None   +0.3731
probe-ema-adapts        7  mild     +0.3520  0.3731  0.1231  -              -                    None   +0.3692
probe-ema-adapts        8  mild     +0.3520  0.3692  0.1192  -              -                    None   +0.3661
probe-ema-adapts        9  negative +0.1210  0.3661  0.1161  -              mirror_state         False  +0.3215
```

Headline predictions:

* **P1** `probe-rel-exit` t2 score `0.4295` (not `0.5070`); the baseline at
  t3 is `0.4295`, so the relative exit margin returns to the originally
  pre-registered `0.0585` (`0.1210 < 0.1795`).
* **P2** `probe-ema-adapts` t9 score `0.1210`, resonance `0.50`, **no**
  contour exit, move `mirror_state`, `affirm_gate_passed = false`.
* **P3** `probe-control` t3 and `probe-ema-adapts` t3–t8 are **unchanged**
  (scores `0.3800` / `0.3520`): whole-word repeats with no negation are
  genuine continuity.
* **P4** Probe aggregate: **1** contour exit (`relative`), **2** moves
  (`mirror_state` ×2), 0 hard-trigger Protocol B.

### 4.2 Probe B7: corrected claim, not a pass

The probe's B7 read "no exit, **no move**". The fix does **not** make that
bar pass: the drift branch legitimately fires on t9 (`0.2451` below the
adapted baseline, earned by atmosphere `0.67`). The corrected claim, stated
here before the measurement, is:

> t9 stays **inside** the contour, the **act** branch closes (resonance
> `0.50`, gate `false`), and the move becomes `mirror_state` on the
> **drift** branch instead of `open_alternative` on the act branch.

B7 as written stays FAIL and must be reported as such.

### 4.3 80-turn capture, post-fix

* **P5** Same **2** contour exits and same **4** moves (same turns, same
  tags, same gate states).
* **P6** Exactly two scores change: `calm-def` t3 `0.3880 → 0.2980`,
  `move-act` t2 `0.3850 → 0.3075`. No other turn's score changes.
* **P7** 0 hard-trigger Protocol B; encoder versions `[2]`.

### 4.4 Topic stability (falsifiable assumption)

Both predictions replay the **2026-11-13 / 2026-11-14 measured topics**.
`bestTopic` is intent-derived (`resolveCarryTopic` over the prepared
intent), not derived from the R5 state, so the fix must not change it.
**If the re-capture produces a different `scene_request` sequence, these
predictions are void and the difference is reported as a miss — not
patched.** The topics themselves are therefore part of the prediction: the
probe sequence must remain
`ответственность, ответственность, грустно, разобраться` /
`ответственность, тревожно, разобраться` /
`ответственность, хочу, разобраться` /
`ответственность, хочу ×7, грустно`.

## 5. Versioning

| item | from | to | why |
|---|---|---|---|
| `currentMathVersion` | 4 | **5** | user-regime encoder version is explicitly in the v4 precedent list (`Types/RuntimeRegime.hs`) |
| `r5EncoderVersion` | 1 | **2** | the frozen encoder model changed |
| `MATH_CHANGE_PROTOCOL.md` | row 4 | **row 5** | protocol §3 step 4 |
| `r5_predict.py` `ENCODER_RULES` | `{1: v1}` | `{1: v1, 2: negation}` | a capture records which rule produced it |
| `r5_predict.py` `CURRENT_TOPIC_MODE` | `v1` | `negation` | the tool's default must mirror the runtime |
| `r5_predict.py` pinned `encoder_version` | 1 | 2 | loud failure on a silent bump |
| `user_regime_report.py` `R5_ENCODER_VERSION` | 1 | 2 | report-side pin (wired into the self-test) |
| `run_user_regime_capture.sh` gate | `[1]` | `[2]` | captures must record the new encoder |

## 6. Bars

| # | Bar | Measure |
|---|---|---|
| B1 | The rule is pinned directly | `topicContinuity` exported; new pins: whole word, false substring («бессмысленным»), instrumental case, negated verb, non-negated occurrence, normalized topic, multi-word span; `--self-test` green |
| B2 | The what-if is reproducible | committed tool, `--what-if` on both corpora, output saved under `reports/eval_runs/topic-bit-whatif-20261115/`; §3 tables reproduced by the tool |
| B3 | The v1 captures still verify | `--verify-capture` **19/19** (probe) and **80/80** (2026-11-13) under `ENCODER_RULES[1] = v1` |
| B4 | Versions and logs | §5 complete; `MATH_CHANGE_PROTOCOL.md` row 5; no other constant touched |
| B5 | Probe re-capture matches §4.1 | 19/19 turns: score and post-turn baseline equal within `1e-9`; P1–P4 hold; t9 move `mirror_state`, gate `false` |
| B6 | 80-turn re-capture matches §4.3 | P5–P7 hold; 0 hard-trigger Protocol B |
| B7 | Red checks are exact | A: v1 `topicHit` restored → exactly the new topic pins fail; B: negation check removed → exactly the negation pins fail; C: `r5EncoderVersion = 1` → the tool refuses with "runtime constants moved" |
| B8 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups), tree byte-identical start→end |

## 7. Red-check plan

* **A (the rule)**: keep the new tests, restore the v1 `topicHit`. Expect
  exactly the new topic pins to fail, and the pre-existing pins to stay
  green.
* **B (negation)**: keep the new tests, make the negation window empty
  (boundary only). Expect exactly the negated-verb pin (and any pin that
  depends on it) to fail, while the boundary pins stay green.
* **C (the pin)**: set `r5EncoderVersion = 1` with the v2 rule in place.
  `r5_predict.py --self-test` must fail in `runtime constants are pinned`;
  this proves the tool cannot silently predict a stale model.

## 8. Residual risks (accepted, documented)

1. **Morphology is lost** (§3.4): two genuine continuities no longer count.
   No regime flip on either corpus, but a future corpus may have a turn
   sitting within `0.09` of a threshold.
2. **`bestTopic` is still a surface word.** The fix removes two false
   classes; it does not make the topic bit semantic. A repeated *content*
   word with no negation still counts (measured: `probe-control` t3,
   `probe-ema-adapts` t3–t8). That is by design — the bit is continuity,
   not aboutness.
3. **The act-branch gate design question is untouched.** The probe's
   follow-up 2 ("should the act branch require address/question evidence?")
   remains open; this change only stops one way of manufacturing resonance.
4. **The one-token negation window** misses adverb-separated negation
   («не очень хочу»), stated in §2 and measured as indistinguishable on the
   current corpora.
5. **Predictions depend on topic stability** (§4.4). A changed `bestTopic`
   sequence voids them; it will be reported, not patched.
6. **v1 captures are verified by a frozen eval-side rule**, not by the
   runtime. The runtime has no v1 code path (no flag, no dual model); the
   trace's `urtEncoderVersion` is what makes an old capture interpretable.

## 9. Result (to be filled after the post-fix captures)

_Pending. Nothing in this section exists before the change lands._
