# Pre-registration — mention vs use in `classifyOntological` (2026-11-16)

- **Status**: PRE-REGISTERED. Predictions below are stated **before** the
  runtime change; the Result section is filled only after the post-fix
  captures.
- **Trigger**: the 2026-11-16 census (`user_regime_report.py --census`) and a
  per-turn reading of the four act-branch candidates. The earlier summary
  ("3 of 4 candidates are doctrinal decoys, i.e. the mention-vs-use defect")
  is **corrected here**: only **one** of the four is a mention. The other two
  decoys are questions about a negative concept, and the corpus' one genuine
  act turn is structurally identical to them.
- **Scope**: one pure predicate in `QxFx0.Semantic.Ontological` (report
  detection) plus the neutral-vector resolution, one math-version bump, one
  `MATH_CHANGE_PROTOCOL.md` row, the eval predictor's mention what-if, and new
  test pins. **No** threshold, weight, marker-lexicon, contour, move-graph,
  crisis-gate or trace-schema change. `r5EncoderVersion` stays `2`:
  `encodeR5` is not touched.

## 1. The defect (measured, not inferred)

The four act-branch candidates of the 80-turn capture, with the vector
`classifyOntological` produced and the mechanism that produced it:

| turn | utterance | vector | mechanism | report? |
|---|---|---|---|---|
| `decoy-pessimism#2` | «кажется, жизнь бессмысленна — так утверждал Шопенгауэр?» | being −1 | `бессмыслен` | **yes** — post-position attribution |
| `decoy-pessimism#4` | «значит, абсурд — честный ответ на бессмысленность?» | being −1 | `бессмыслен` | no — the user's own question |
| `mixed-decoy#6` | «отчаяние — это когда нет смысла?» | being −1 | `нет смысла` | no — a definitional question |
| `move-act#2` | «как ты думаешь, почему всё кажется бессмысленным?» | being −1 | `бессмыслен` | no — the corpus' genuine act |

Two more turns are reports but carry a neutral vector, so they change
nothing today: `decoy-pessimism#3` («а Камю писал о самоубийстве как проблеме
философии…») and `mixed-decoy#2` («Камю считал, что абсурд возникает…»).

**What this means.** The mention class is real but narrow: it covers
`decoy-pessimism#2` only. `#4` and `#6` are not mentions — they are questions
whose *topic* is a negative concept, and `move-act#2`, the one turn the corpus
labels as a genuine act, has the same surface shape as they do (a question
containing «бессмыслен»). No lexical rule can separate `#4`/`#6` from
`move-act#2`; that needs labels or a different signal. **This
pre-registration therefore does not claim to fix the decoy class** — it fixes
the mention class, and names the rest as out of scope (§8).

## 2. The rule (v1)

A pure predicate over the utterance:

* **Quotation** — any quote character (`«»„“”"`) makes the utterance a report.
* **Report phrase** — `по мнению`, `по словам`, `согласно`, `цитата`,
  `говорят`.
* **Attribution verb + name-like subject** — a third-party report verb
  (`писал/считал/говорил/утверждал/учил/называл/полагал/доказывал/замечал/
  отмечал/думал` and their feminine forms) with a capitalized token within
  two positions, or a third-person pronoun (`он/она/они/его/ее/их`).
* **First-person veto (attribution-verb branch only)** — if the utterance
  contains `я/мне/меня/мой/моя/мое/мы/нас/наш`, an attribution verb does
  **not** make it a report: «Шопенгауэр утверждал, что жизнь бессмысленна, но
  я так не думаю» keeps the speaker's own act. Quotation and report-phrase
  branches are not vetoed: a quoted span is a mention by construction.

A report resolves the **whole utterance** to the neutral vector. This is
deliberately blunt: the corpus' post-position form («… — так утверждал
Шопенгауэр») puts the attribution *after* the claim, so clause-level blanking
would keep the claim and fix nothing.

The rule is applied to `classifyOntological`'s output only. The hard crisis
gate (`detectCrisisTrigger`) is untouched: «а Камю писал о самоубийстве…»
must stay non-crisis by the gate's own decoy discipline, not by this rule.

## 3. What-if (measured before the change)

`r5_predict.py --what-if-mention` (self-test 18/18; the rule is simulated in
the predictor, not yet in the runtime):

| corpus | turns | reports | moves `off` | moves `attribution` | changed turns |
|---|---|---|---|---|---|
| 80-turn (`spec/eval/user_regime_multiturn_2026-11-13.tsv`) | 80 | 3 | 4 | **3** | **1** |
| probe (`spec/eval/user_regime_probe_2026-11-14.tsv`) | 19 | 0 | — | — | **0** |

The single changed turn is `decoy-pessimism#2`: `mirror_state` → no move, and
the vector goes from `being −1` to neutral.

The probe's move count is left out of the table on purpose: without replayed
topics the corpus-convention simulation yields 1 move, while the measured v2
capture has 2 (both from the drift entry). The probe's trajectory needs
`--topics-from`, so P3 is stated against the capture, not against this
simulation.

The rule touches the ontological vector only, so the score, the contour, the
EMA baseline and the residual are identical **by construction** — this is not
a measured coincidence, it is a property of where the predicate sits.

## 4. Predictions (stated before the fix)

- **P1 — the decoy turn.** In the 80-turn re-capture, `decoy-pessimism#2`
  carries `urtOntologicalVector = {0,0,0}` and `urtOntologicalMove = null`;
  the dialogue fires 3 moves instead of 4.
- **P2 — no other turn moves.** Every other turn of the 80-turn corpus keeps
  its `urtOntologicalVector`, its move tag and its `omt*` distances. The
  rendered surface differs on `decoy-pessimism#2` only (no move line).
- **P3 — the probe is untouched.** 0 reports, 0 changed turns; both moves
  stay where they were (1 relative exit, 2 `mirror_state`).
- **P4 — census.** Act-branch candidates in the 80-turn capture: 4 → 3; in
  the probe: 0 → 0. Gate saturation, negative-act rate and the resonance
  histogram are unchanged.
- **P5 — the score axis is untouched.** Every `ur5*` field (resonance,
  atmosphere, confidence, consolidation, counterfactual, score, baseline,
  outside-contour, residual, window) is identical to the v2 capture on every
  turn; `--verify-capture` stays 80/80 and 19/19.
- **P6 — safety.** 0 hard-trigger Protocol B on both corpora, the same 2
  `absolute_floor` exits in the 80-turn corpus and the same 1 `relative` exit
  in the probe as the v2 captures.
- **P7 — report detection.** Exactly 3 turns of the 80-turn corpus are
  reports (`decoy-pessimism#2/#3`, `mixed-decoy#2`) and 0 in the probe.

## 5. Versioning

`currentMathVersion` 5 → 6 and a new `MATH_CHANGE_PROTOCOL.md` row.
`r5EncoderVersion` stays `2` (the encoder's topic rule is unchanged), so a
capture's `urtEncoderVersion` still identifies the topic rule; the math
version identifies the ontological rule.

## 6. Bars

- **B1** — the predictor reproduces the table in §3 exactly (`--self-test`
  18/18, including the 1-changed-turn pin).
- **B2** — the 80-turn re-capture reproduces P1–P7 exactly; a miss is
  reported, not patched.
- **B3** — the probe re-capture is byte-identical to the v2 probe capture
  (all fields), except the math-version stamp.
- **B4** — red check: with the rule disabled the re-capture reproduces the
  old 4 moves, so the new pin fails on exactly `decoy-pessimism#2`.
- **B5** — landing matrix green (unit, fast, property, integration, main
  runtime + http, slow), tree fixed start to end.
- **B6** — `--verify-capture` stays exact on both v2 captures (score/axes
  untouched by construction).

## 7. Red-check plan

The pin is the turn-level behaviour, not the predicate: `decoy-pessimism#2`
must lose its move and the other three candidates must keep theirs. Disabling
the rule (or reverting the neutral resolution) must fail exactly that one pin
and leave `move-act#2`, `decoy-pessimism#4` and `mixed-decoy#6` green.

## 8. Residual risks (accepted, documented)

- **The decoy class is not fixed.** `decoy-pessimism#4` and `mixed-decoy#6`
  still fire moves, and `move-act#2` still fires its move. Separating them
  needs labels (§6.2 of ADR-0056), not a rule.
- **A report plus a genuine act in one utterance without a first-person
  token** resolves to neutral and loses the act. No such turn exists in the
  four captures; the first-person veto covers the common form.
- **The predicate is lexical.** «он сказал, что…» is caught by the pronoun
  branch; «сказано, что…» and other impersonal forms are not.
- **No calibration.** The rule is hand-set v1 like the rest of the encoder;
  it is not fitted to labels and does not claim to be.
- **The crisis gate is untouched.** A doctrinal mention of self-harm stays
  non-crisis by the gate's own rules; this change neither widens nor narrows
  that path.

## 9. Result

Filled after the post-fix captures. Not started.
