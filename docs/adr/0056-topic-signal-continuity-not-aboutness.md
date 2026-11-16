# ADR-0056: Topic Signal — Continuity, Not Aboutness

**Status:** Accepted
**Date:** 2026-11-15
**Accepted-By:** operator review (2026-11-16)
**Supersedes:** None
**Related:**
- `AGENTS.md` — "Concept v3 two-protocol regime (2026-08-23)" and the
  2026-11-15 encoder-v2 entry (the regime record; **no ADR covers concept v3
  as a whole** — see §6.3)
- `docs/closure/USER_REGIME_PROBE_PREREG_2026-11-14.md` (measured the defect)
- `docs/closure/USER_REGIME_TOPIC_BIT_PREREG_2026-11-15.md` (encoder v2)
- `docs/closure/USER_REGIME_CAPTURE_PREREG_2026-11-13.md` (the capture protocol)
- `docs/closure/MATH_CHANGE_PROTOCOL.md` rows 3 and 5
- `src/QxFx0/User/R5.hs`, `src/QxFx0/Semantic/Ontological.hs`,
  `src/QxFx0/Semantic/MoveGraph.hs` (the arithmetic and the gate this ADR
  constrains)

---

## 1. Context

The user-regime encoder (`QxFx0.User.R5.encodeR5`) is a frozen linear model
over five axes. One of its inputs is a **topic-continuity bit**: it compares
the previous turn's `bestTopic` with the current utterance and contributes
`+0.20` to resonance, `+0.20` to consolidation, and — through
`userConatusScore` — `+0.09` to the viability score
(`0.20·0.25 + 0.20·0.20`; `+0.0775` when the resonance sum clamps at `1.0`).

### 1.1 What the bit actually compares

- `bestTopic` is the intent layer's focus word (`resolveCarryTopic` over the
  prepared intent) — a raw surface word, not a semantic id.
- It is **not predictable from the prompt text**: replaying measured topics
  reproduces a capture exactly (19/19 probe, 80/80 capture), while predicting
  topics from the corpus does not (`USER_REGIME_PROBE_PREREG_2026-11-14.md`,
  finding 4).
- v1 matched it as a raw substring of the normalized-but-unblanked utterance
  on an **unnormalized** topic. Three defect classes were measured: a
  substring inside an unrelated word («смысл» in «бессмысленным»), an
  inflection matched by accident («ответственность» in «ответственностью»),
  and a negated verb («хочу» in «не хочу»). Encoder v2 fixed all three
  (normalized topic side, whole words only, negation-safe) and deliberately
  gives up inflection, because it has no morphology pass.

### 1.2 What the bit is worth at the decision surfaces

`resonance = 0.5 + 0.20·question + 0.15·address + 0.20·topic`, and the
resonance-gated act entry of the move layer requires
`resonance > resonanceGateThreshold = 0.55`. **Any one** of the three features
clears the gate: question `0.70`, topic `0.70`, address `0.65`. Only a turn
with none of them stays at `0.50`.

Census (`user_regime_report.py --census`, 2026-11-15) over the four existing
captures:

| capture | turns | above gate | negative act | act-branch candidates | moves |
|---|---|---|---|---|---|
| 80-turn, v1 (`user-regime-20261113`) | 80 | 64 (80%) | 11 (14%) | 4 | 4 |
| 80-turn, v2 (`user-regime-20261115`) | 80 | 64 (80%) | 11 (14%) | 4 | 4 |
| probe, v1 (`user-regime-probe-20261114`) | 19 | 13 (68%) | 2 (11%) | **1** | 2 |
| probe, v2 (`user-regime-probe-20261115`) | 19 | 12 (63%) | 2 (11%) | **0** | 2 |

Two readings matter:

1. **The gate is near-vacuous.** It separates "any engagement signal" from
   "none", not "resonance with the system" from "none". In the pre-fix probe,
   **8 of the 13** above-gate turns were above on the topic bit **alone**
   (the `0.70 × 8` bar of the histogram; the other five carry question and
   address together at `0.85`/`1.00`). Measured twice: from the stored
   resonance values and independently from the prompt text.
2. **The gate-passed act branch fires on exactly its candidate turns.** The
   act branch has two entries (`MoveGraph.moveNeeded`): the resonance-gated
   one (`actNegative ∧ ontologicalMoveAdmissible`) and the earned-drift one
   (`actNegative ∧ negativeEvidenceEarned ∧ score < baseline − margin`). The
   census counts only the first. On the 80-turn capture all four moves came
   through the gate-passed entry, so 4 candidates = 4 moves — and three of the
   four candidates are turns the corpus labels as doctrinal decoys
   (`decoy-pessimism` #2/#4, `mixed-decoy` #6). Only #2 is a *mention*
   (attribution to Schopenhauer); #4 and #6 are the user's own questions about
   a negative concept, and the corpus' one genuine act turn (`move-act` #2)
   has the same surface shape as they do. See
   `USER_REGIME_MENTION_VS_USE_PREREG_2026-11-16.md` §1. On the pre-fix probe
   the single candidate was exactly the B7 defect turn (`probe-ema-adapts`
   t9); after encoder v2 it is zero, and both of the probe's moves come from
   the drift entry.

So the bit is not a minor score term: it is **sufficient** to open the gate
the concept document's §5 ordering (mirror → resonance → affirm) relies on.

## 2. Decision

**2.1 Semantics.** The topic signal means **continuity**: "the utterance
repeats the carried topic word". It never means **aboutness** ("the utterance
is about the topic"). A repeated content word with no negation counts; an
inflected repeat does not.

**2.2 Ownership.** `bestTopic` stays an intent-layer surface word. The encoder
consumes it and must not own topic extraction, and must not import the
morphology resource. A morphology-aware match is a calibration-phase change
with its own pre-registration.

**2.3 Keep the bit in the encoder.** It is the only turn-to-turn linkage
signal the encoder has; removing it would make the score blind to dialogue
continuity. It stays in the score and in consolidation with its current
weights until a labelled set exists to fit them. Whether it also feeds
*resonance* is exactly what §2.4 settles.

**2.4 The bit is not evidence of resonance with the system.** Continuity of
the user's own topic is not address and is not a question. The act branch
must therefore not be openable by the topic bit alone. This ADR fixes the
principle; the rule change lands as a separate pre-registered math change —
**implementation B** (drop the bit from resonance, keep it in consolidation
and in the score), chosen 2026-11-16 on the measurement in §3.1.

**2.5 Versioning.** Any change to the bit's weight, or to its role in the
gate, is a math change: `r5EncoderVersion` and `currentMathVersion` bump
together and `MATH_CHANGE_PROTOCOL.md` gains a row.

**2.6 Safety is out of scope.** The hard crisis gate
(`Safety/CrisisGuard.detectCrisisTrigger`) stays lexical and unconditional:
it never consults the model or the score, and the regime is law-driven, not
flag-gated (ADR-0034 §3 Rule 5). Nothing here may weaken it.

## 3. Alternatives

| # | Alternative | Cost | Why not (yet) / status |
|---|---|---|---|
| A | Status quo: v2 rule, bit in resonance | none | keeps the gate near-vacuous (80 % / 63 % saturation) |
| B | Drop the bit from **resonance**, keep it in consolidation | one weight change | **chosen 2026-11-16** — see §3.1 |
| C | Morphology-aware match | encoder depends on the morphology resource | recovers the two lost continuities but cannot be validated without labels |
| D | Replace `bestTopic` with a normalized topic id | intent-layer change | makes the bit predictable and closer to semantic; needs its own pre-registration |
| E | Raise `resonanceGateThreshold` to 0.72 | one constant | excludes topic-only **and** question-only turns (both 0.70); blunt |
| F | Require question **or** address for the act branch, keep resonance | one conjunction | same reach as B on today's captures, but needs the evidence bits plumbed into `MoveGraph`; under the current weights the gate reduces to `question ∨ address` (§3.1) |

B and F both close the measured defect. They are **not** equivalent in
implementation: B is a weight change inside `encodeR5`; F needs the
question/address bits plumbed into `MoveGraph`, because they live inside
`encodeR5` today and `UserR5State` does not carry them. With the current
weights F's resonance comparison is also redundant: question alone gives
`0.70 > 0.55`, address alone `0.65 > 0.55`, so under F the gate reduces to
`question ∨ address`.

### 3.1 Measured cost of B and F (2026-11-16, read-only)

The bit is decodable from the stored trace —
`topic = (resonance − 0.5 − 0.20·question − 0.15·min(1,address)) / 0.20` —
exactly on all 99 turns of the four captures (0 undecodable). It is set on
15/80 turns of the 80-turn v2 capture and 7/19 of the v2 probe.

| capture | act candidates today | under B | under F | moves today | moves under B/F |
|---|---|---|---|---|---|
| 80-turn v2 | 4 | 4 | 4 | 4 | 4 |
| probe v2 | 0 | 0 | 0 | 2 (both drift entry) | 2 |

- All four 80-turn moves carry a question, so neither B nor F removes any of
  them. The three doctrinal decoys are an ontological-layer problem (§6.2),
  not a topic problem — this ADR does not fix them, and only one of the three
  is a mention (2026-11-16 pre-registration, §1).
- No turn that carries the bit sits within `0.05` of a contour boundary, so
  B's score shift flips no contour verdict on these captures.
- The only act candidate either rule removes is the pre-fix probe turn
  `probe-ema-adapts#9`, already closed by encoder v2.

So on today's corpora B and F are indistinguishable at every decision
surface, and B is the cheaper of the two — hence the 2026-11-16 choice.

## 4. Consequences

- **Positive**: the gate becomes a gate; the act branch stops firing on topic
  continuity alone; the bit's semantics are written down and testable.
- **Negative, measured as zero today**: B/F reduce act-branch reach. On the
  four existing captures neither changes a single move (§3.1); reach is cut
  only where the topic bit was the sole gate-opener.
- **Side effects**: B removes `0.05` from the score on the turns that carry
  the bit (`0.0375` when the resonance sum clamps), so the contour distance
  and the residual audit move with it. Measured: no contour verdict flips;
  the residual effect is bounded by `0.05` and is not yet measured (the
  current maximum is `0.344` against a `0.35` threshold, so this is the one
  place B could surface something new). F leaves the score untouched.
- **Risk**: without labels, B/C/E/F are rule decisions, not calibrated ones.
  This ADR records that explicitly rather than hiding it behind a threshold.

## 5. Quality Gate

- `user_regime_report.py --census` on the four existing captures before the
  change, and on the post-change re-captures; the delta is reported turn by
  turn.
- The topic bit is decoded from the stored traces (§3.1) and the predicted
  delta is stated per turn — above-gate flips, act candidates, contour
  verdicts, residual — before the runtime change is pre-registered.
- `r5_predict.py --what-if` (or a sibling mode) reproduces the delta on the
  text side, where question and address live.
- Pre-registration with predictions; re-captures must reproduce the predicted
  tables exactly, or the miss is reported and not patched.
- `Test.Suite.UserR5` + `Test.Suite.MoveGraph` pins; `r5_predict.py
  --self-test` stays green with the new pinned constants.
- Math version bump and a `MATH_CHANGE_PROTOCOL.md` row.

## 6. Decision record and open questions

**Decided 2026-11-16 (operator):** §2.4 is accepted and **B** is the chosen
implementation — the bit leaves `resonance`, stays in `consolidation` and in
the score. The rule lands as a separate pre-registered math change (§5), not
in this ADR. That also settles the old "does continuity belong in resonance
at all" question: no.

Open:

1. What is `bestTopic` when the intent has no focus word? Observed: it can be
   a modal («хочу»), which is a poor topic and was one of the measured
   false-hit sources before encoder v2.
2. `classifyOntological` reads a marker anywhere in the utterance as the
   speaker's act. Of the four act-branch candidates in the 80-turn capture,
   three are corpus-labelled decoys, but only one is a *mention*; the other
   two are questions about a negative concept, indistinguishable at the
   surface from the corpus' genuine act turn. A mention fix is pre-registered
   and landed (`USER_REGIME_MENTION_VS_USE_PREREG_2026-11-16.md`; its §9
   records two prediction misses — the negative-act count and the residual
   audit); the rest needs labels. Not a topic-signal question, and this ADR
   does not fix it.
3. **No ADR records concept v3 as a whole.** The regime landed under
   `AGENTS.md` plus closure pre-registrations, while ADR-0048 requires an
   accepted ADR for new subsystems. This ADR covers the topic signal only; a
   regime-level ADR is a separate document and is not claimed here.
