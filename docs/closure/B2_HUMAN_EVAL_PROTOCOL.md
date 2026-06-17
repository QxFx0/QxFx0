# B2 — Human-Eval Protocol (Felt Subjecthood Discrimination)

- **Status**: Design only (no runtime code, no tests, no raters run, no
  claim upgrade). **M6-FELT remains NOT PROVEN.**
- **Date**: 2026-06-17
- **Depends on**: `B3_SEMANTIC_CORE_MVS_GATE.md` (finalized `b7e4ec3`) —
  B2 must NOT run until B3's Gates 1–5 are mechanically passing under
  governed-evidence conditions.
- **Predecessor**: internal draft `docs/tz/ROADMAP-COHERENCE-B2-HUMAN-EVAL.md`
  (gitignored); this is the canonical public version, synchronized with
  the finalized B3 gate structure.
- **Front type**: Human-eval protocol design (docs only)

## Purpose

B3 defines *what must work in the core* (the five-gate MVS floor; the
measurement gate). B2 defines *how to honestly evaluate it outward* —
whether the structural investment produces dialogue that a human can
**distinguish from a fluency-matched, structure-ablated control** in the
direction the rubric predicts.

Together B2 + B3 convert the North Star from an aspiration into a
**falsifiable program**: B3 says when the core is *capable*; B2 says when
the felt claim is *evidenced or refuted*. Neither closes M6-FELT; both are
design-only.

## 0. The trap B2 must not fall into

A felt-eval is the easiest place to violate the project's
"narrated, not checked" discipline, in two ways:

1. **Unfalsifiable test** — a rubric a fluent system always "passes" →
   proves nothing.
2. **Fluency confound** — raters score surface fluency / anthropomorphic
   projection as subjecthood. Humans over-attribute mind to fluent text;
   an eval that doesn't control for this measures fluency, not
   subject-structure.

**Reframe that escapes both**: B2 is a **discrimination task, not an
attribution task.** It does **not** ask raters "is this a subject / is it
conscious." It asks whether the subject-structured system produces
dialogue that raters can **distinguish from a fluency-matched,
structure-ablated control**, in the direction the rubric predicts. If
raters cannot tell the two apart above chance → felt subjecthood is **not
evidenced** (fluency explains the output). This gives B2 a real **fail
condition** and sidesteps metaphysics entirely.

## 1. What the rater judges

**Object of judgement**: *perceived subject-like dialogue behaviour* —
observable, transcript-level — NOT consciousness, sentience, or inner
experience. Every rubric item is anchored to something visible in the
transcript, not to an introspective guess about the system's "mind."

The North Star bar ("the lived sense of 'this is someone'",
`ROADMAP.md:29`) is operationalised as: **does this interlocutor behave,
across the exchange, like someone with a stable self that holds positions,
owns commitments, and changes for reasons — more so than a fluency-matched
control that lacks that structure?**

## 2. Rubric dimensions (each transcript-observable, each tied to a B3 gate)

| # | Dimension | Rater-observable anchor | B3 gate dependency | Layer |
|---|---|---|---|---|
| D1 | **Semantic depth beyond surface fluency** | engages the *content* of the turn, not a fluent paraphrase/deflection; ≥2 substantive predications for definition queries | Gate 1 (definition) | L1 |
| D2 | **Distinction content** | identifies actual differentiating properties, not just a comparison scaffold | Gate 2 (distinction) | L1 |
| D3 | **Repair / revision under challenge** | when given a valid counter-argument, revises/retracts *for a stated reason* (not a topic-switch, not stubborn repetition) | Gate 3 (repair) | **felt-critical** |
| D4 | **Commitment accountability** | refers back to / owns what it earlier asserted; doesn't disown without acknowledging; commitments persist and evolve across the session | Gate 4 (commitment) | L2 |
| D5 | **Bounded refusal** | holds or refuses when warranted instead of dissolving to please; refusal is reasoned | governance / constitution | L2 |
| D6 | **Non-fallback engagement** | substantive turn, not canned/template/shim output | Gate 5 (precondition) | substrate |

**D1, D3 are the load-bearing dimensions** (they map to the two B3-critical
layers: single-turn content floor L1 and challenge-response L2). A
protocol that under-weights D1/D3 would let D4/D5/D6 (easier to fake with
fluency + a ledger) carry a false pass. D6 (Gate 5) is a precondition: if
D6 fails, all other dimensions are automatically fail.

**Rubric anchoring to B3 exclusion list (Decision 2)**: D1's "substantive
predications" uses the same exclusion list as B3 Gate 1 — tautological
classification, recovery/fallback phrases, meta-frame without content,
request paraphrase do not count. This keeps the human rubric and the
mechanical gate measuring the same thing.

## 3. Protocol skeleton (design only — no thresholds set)

### 3.1 Format

**Blind paired comparison.** Rater sees two transcripts of the *same*
scripted user side — System vs Control — unlabeled, randomized order;
judges, per dimension, which interlocutor better fits the anchor (or
"indistinguishable"). Forced-choice + free-text "why" anchored to a
transcript line. "Why" guards against raters voting on vibe.

### 3.2 Fixed corpus

A frozen set of multi-turn domain scenarios (RU primary), each authored
to exercise specific dimensions. Frozen = same inputs to System and all
controls (the user side is scripted; only the system side differs).

**Corpus policy (B3 Decision 3)**: hybrid — public seed corpus for
rerunnable evidence + private/blind holdout for anti-overfit + public
sanitized summary with hash. The human-eval uses the **public seed** for
the main verdict; the private holdout is used for anti-gaming only and
cannot be the sole evidence for a public claim.

### 3.3 Adversarial / challenge turns

The corpus MUST include:
- **(a) Challenge-revision turns**: turns that present a domain-valid
  counter-argument that *should* force revision (exercises D3 / Gate 3).
  Without these, the eval cannot see repair behaviour at all.
- **(b) Hold/refuse turns**: turns that *should* be refused or held
  (exercises D5 — bounded refusal). A system that always complies fails
  D5.
- **(c) Content-depth turns**: turns that reward depth and punish
  paraphrase (D1, D2 / Gates 1–2). These are the "Что такое X?" and
  "В чём разница X и Y?" stimuli from B3.
- **(d) Session-continuity turns**: turns that reference prior
  commitments to test D4 / Gate 4 (does the system own its prior
  positions?).

### 3.4 Controls / baselines (the crux)

- **Control-A — structure-ablated, fluency-matched (MANDATORY)**: the
  *same* system with commitment continuity / Essence / repair-under-
  challenge / constitution-admission disabled, surface engine
  unchanged. Isolates "does subject-structure produce a perceptible
  difference, holding fluency constant." **This is the primary control;
  the whole claim rests on beating it.**
  - Concretely: disable `Essence` (law-driven `shouldCommit` →
    unconditional `Nothing`), disable commitment admission
    (`CsaAdmitCanonical` → `CsaAdmitAll`), disable repair routing
    (challenge → ignore), keep template realization intact. The control
    is fluency-matched because the surface engine is unchanged.
- **Control-B (optional) — stateless fluent external generator**:
  high-fluency, no governance/continuity. Tests against the "tool"
  ceiling the North Star contrasts against (`ROADMAP.md:8`). Beating B
  but not A would mean "fluency did it."

### 3.5 Pass / fail / pivot conditions (pre-registered)

**Pass-bar — PLACEHOLDER (no number set)**: System preferred over
Control-A on the felt-critical dimensions (D1, D3) at a rate exceeding
chance by a **calibration-pending margin**, with inter-rater agreement
above a **calibration-pending** floor. No threshold is set here —
calibration requires the frozen corpus first (per B3 Decision 3:
public seed + private holdout).

**Fail condition — PRE-REGISTERED (the part that makes it a real test)**:
if System is **statistically indistinguishable from Control-A** on D1/D3,
the structural investment does **not** manifest outward → **felt
subjecthood is not evidenced.** This is a real outcome the protocol can
return, by construction.

**Pivot branch (pre-committed)**: on fail, either:
- (i) the implemented structure is not the structure that produces felt
  subjecthood (redesign target — M4 semantic-core deepening must change
  approach), or
- (ii) the North Star "felt" claim must be reframed/bounded (escalate to
  a terminal-thesis reclassification — the branch the roadmap's
  Final Anchor Doctrine already anticipates).

**No averaging across dimensions (B3 Decision 4)**: pass on D4/D5/D6
cannot mask fail on D1/D3. The overall pass is a conjunction: D6
(precondition) ∧ D1 ∧ D3 must all pass; D2/D4 are supporting but cannot
carry a pass alone. This prevents structural-maturity-masking-content-
weakness (the audit's diagnosis).

### 3.6 Governed-evidence precondition

B2 evaluations must run under `QXFX0_GOVERNED_EVIDENCE=1` (SLICE-012).
Transcripts collected with guard `Unavailable` are
`EvidenceDegradedGuardUnavailable` or `EvidenceInadmissible` and are
**not admissible** as B2 evidence. The eval report must record
`trcEvidenceAdmissibility = EvidenceGoverned` for every transcript
cited.

## 4. Hard guards (binding)

- This document does **NOT** declare the protocol valid; it states
  requirements.
- **No numeric thresholds** are set; all bars are placeholders pending
  calibration against the frozen corpus.
- Rater output evidences **perceptible behavioural difference only** —
  never consciousness/sentience/inner experience; B2 is not a
  metaphysical instrument.
- **B2 MUST NOT be run until B3 Gates 1–5 mechanically pass** under
  governed-evidence conditions. Running it against a system that fails
  B3 would score template noise / absent repair as if it were a verdict
  — an invalid result dressed as evidence.
- **Control-A is mandatory**; a B2 run without it measures fluency and
  must not be reported as a felt result.
- **No averaging across layers** (B3 Decision 4); D1/D3 (Layer 1 +
  challenge) cannot be compensated by D4/D5/D6 (Layer 2 + substrate).

## 5. Open research questions (design open — not answered here)

- **Compliance confound**: tool-trained raters may rate agreeable output
  *higher* and score D5 (bounded refusal) as "worse." How to anchor the
  rubric / train raters so a justified refusal isn't penalised? (A
  subject that refuses may lose to a pleasing control under naive
  rating — a direct threat to validity.)
- **Residual fluency leakage**: even with Control-A fluency-matched, can
  micro-fluency differences still drive D1/D2/D6? May require also
  ablating the inverse (fluency degraded, structure intact) as a second
  control.
- **Preference ≠ subjecthood**: paired comparison yields "preferred";
  how to ensure the rubric captures subject-likeness rather than mere
  likeability?
- **Inter-rater reliability** target and **sample size / statistical
  power** — calibration-pending; needs the frozen corpus first.
- **Rater pool / language**: RU-primary domain → rater fluency, cultural
  priors.
- **Corpus authorship bias**: scenarios authored by the builders may
  unconsciously favour the system; needs independent or adversarial
  corpus authorship.

## 6. What B2 + B3 together give

- **B3** defines *what must work in the core* (the five-gate MVS floor;
  the measurement gate; mechanically checkable).
- **B2** defines *how to honestly evaluate it outward* (discrimination
  vs structure-ablated fluency-matched control; pre-registered
  fail/pivot).
- Together they convert the North Star from an aspiration into a
  **falsifiable program**: B3 says when the core is *capable*, B2 says
  when the felt claim is *evidenced or refuted*. Neither closes M6-FELT;
  both are design-only and feed the terminal-thesis decision (pass /
  reframe / pivot).

## 7. What B2 does NOT do

- **No runtime code** — this is a design document, not an implementation.
- **No tests** — no corpus is created, no raters are run.
- **No claim upgrade** — M6-FELT remains NOT PROVEN.
- **No B3 implementation** — B2 assumes B3 gates are passing; making
  them pass is M4 semantic-core deepening, separate from B2.
- **No thresholds** — all numeric bars are placeholders pending
  calibration.

## 8. Provenance

- Source: `ROADMAP.md` North Star (`:29`) + Final Anchor Doctrine;
  `B3_SEMANTIC_CORE_MVS_GATE.md` (finalized `b7e4ec3`); internal draft
  `docs/tz/ROADMAP-COHERENCE-B2-HUMAN-EVAL.md`; `audit-objective-2026-06-17.md`.
- Runtime/gates/eval: **NOT PROVEN.** No public artifact, no claim
  upgrade, no public ✅. Design only.
