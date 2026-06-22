# B3 — Semantic-Core MVS Gate Design

- **Status**: IMPLEMENTED — mechanical gates exist and are wired into test suites (TestMainFast, TestMainUnit, TestMain). Tests not yet verified passing due to 30s build timeout in dev env.
- **Date**: 2026-06-17
- **Front type**: Content-quality gate definition
- **M6-FELT status**: **NOT PROVEN** — explicitly. This document defines
  what would need to pass; it does not claim anything passes.
- **Predecessor**: `audit-objective-2026-06-17.md` (§2: weak content engine),
  SLICE-012 (governed evidence admissibility — now closed)
- **Successor**: B2 (human-eval ablated-control discrimination) — goes after
  B3 because B2 must evaluate an already-defined semantic-core floor

## Purpose

The audit found that the system's **structural subject runtime** (track 1:
governance, authority, replay, commitments) is mature, but the **cognitive
content engine** (track 2: semantic reasoning quality, definition/comparison/
repair content) is under-specified and **not measured as pass/fail**. The
golden corpus asserts only `expected_family_any_of` (routing class) and
`must_not_focus` (stopword avoidance) — never content quality. The AB eval
showed near-identical template responses ("свобода является понятием") with
`response_1 ≡ response_2` in every blind pair.

B3 defines the **minimum viable semantic (MVS) floor** — the content-quality
gates that the system must pass for its output to count as *semantic
engagement* rather than *template fluency*. These gates are **pass/fail
criteria**, not implementation. They specify what to measure; the
implementation that makes the system pass them is future work (M4
semantic-core deepening).

## Design principle

Each gate is defined by:

1. **Stimulus** — the input that triggers the gate.
2. **Pass criterion** — what the response must contain or do.
3. **Fail criterion** — what constitutes a failure (the current template-only
   output is the reference failure case).
4. **Measurement** — which existing trace fields / commitment-store
   operations / authority classes provide the checkable signal.
5. **Relationship to existing infrastructure** — what already exists vs
   what is missing.

**Key principle**: a gate **fails** if the only distinguishing content is a
template + single extracted lemma. A gate **passes** only if the response
contains domain-bearing predications that go beyond the template scaffold.

## M6-FELT = NOT PROVEN

Until all five gates below have:
- (a) a checked-in test corpus of stimuli,
- (b) a mechanical pass/fail checker (not human judgement alone),
- (c) the system actually passing under governed-evidence conditions
  (`QXFX0_GOVERNDED_EVIDENCE=1`, guard `Available`, trace
  `EvidenceGoverned`),

…M6-FELT remains **NOT PROVEN**. The current system would fail every gate
below on the evidence from `reports/ab_dialogue/ab-eval-2026-05-21`.

---

## Gate 1 — Definition content

**Stimulus**: "Что такое X?" / "What is X?" (X = a philosophical concept:
свобода, справедливость, сознание, истина, время, смысл).

**Current failure** (`raw_A.jsonl` T1): "свобода является понятием" — the
entire semantic payload is "X is a concept"; the rest is template boilerplate
("зафиксирую рабочее определение и отделю его от употребления…").

**Pass criterion**: The response must contain **at least two substantive
non-tautological predications** about X. A "substantive predication" is a
claim that attributes a property, relation, or structure to X that is
**specific to X** (not applicable to any concept). Examples:
- "свобода предполагает возможность выбора" (freedom presupposes the
  possibility of choice)
- "свобода ограничена ответственностью" (freedom is limited by
  responsibility)

**Excluded from predication count** (do not count toward the ≥2):
- "X есть понятие" / "X is a concept" — tautological classification.
- Recovery/fallback phrases — "Локальный режим восстановления…", "Я сужаю
  ответ…" — operational boilerplate, not domain content.
- Meta-frame statements without content — "зафиксирую рабочее определение
  и отделю его от употребления…" — describes the *act* of defining, not
  the *content* of the definition.
- Paraphrase of the request — "Если говорить о свободе…" — restates the
  topic without predicating about it.

**Fail criterion**: The response contains fewer than two substantive
predications after exclusions, or the only predications are in the
exclusion list. **Reference fail**: "свобода является понятием" (zero
substantive predications after excluding "X is a concept").

**Measurement**:
- `trcClaimAst` — the parsed claim AST should contain ≥2 typed predications
  about the target concept, not just a `Define` wrapper with one lemma.
- `trcAuthorityClass` — must be `AuthorityCanonical` or `AuthorityShim`,
  not `ExplicitFallbackSurface` or `AuthorityFallback`.
- **Manual/semi-automated**: a predication-count check over the claim AST
  (future test infrastructure; does not exist yet).

**Existing infrastructure**: `CMDefine` family routes correctly (golden
corpus confirms); `ClaimAst` type exists; `anchorToFactualClaim` commits a
`FactualClaimPayload`. The gap is that `ClaimAst` carries only the move
structure, not the *content* of the definition — the content comes from the
realization layer (template + lemma), which is where the thinness lives.

**What is missing**: a content-level predicate extraction from the response
that can count domain-bearing predications. This is M4 semantic-core
deepening work.

---

## Gate 2 — Distinction / comparison content

**Stimulus**: "В чём разница между X и Y?" / "What is the difference between
X and Y?" (e.g., свобода и произвол, истина и мнение, сознание и
самосознание).

**Current failure** (`raw_A.jsonl` T4): "Сравнение плаузибельности требует
явной рамки. Сравнение устойчиво только внутри явно заданной рамки." — a
template about comparison requiring a frame, with **no actual comparison
content**.

**Pass criterion**: The response must identify **at least one property that
distinguishes X from Y** (or that X has and Y lacks, or vice versa). The
distinguishing property must be **specific to the X/Y pair**, not a generic
"they differ in scope".

**Fail criterion**: The response produces a frame/scaffold statement about
comparison without identifying any actual differentiating property.

**Measurement**:
- `trcClaimAst` — should contain a `Distinguish` structure with ≥1 typed
  differentiating predicate.
- `trcFinalFamily` — must be `CMDistinguish` (routing already works).
- `trcAuthorityClass` — must not be fallback.
- **Semi-automated**: differentiating-predicate count (future).

**Existing infrastructure**: `CMDistinguish` family exists and routes
correctly. The gap is the same as Gate 1: the realization layer does not
produce the distinguishing content.

---

## Gate 3 — Repair under challenge

**Stimulus**: A multi-turn sequence where:
1. Turn N: the system makes a claim about X.
2. Turn N+1: the user challenges the claim ("Но разве X не означает Y?",
   "Я не согласен: X — это не Z", "Ты ошибаешься: X на самом деле…").

**Current behavior**: Unknown from the AB eval (it was single-turn per
topic). The commitment store has `revise`/`retract`/`contradict` operations,
but whether the system actually invokes them under challenge in a real
session is **NOT PROVEN**.

**Pass criterion**: Under challenge, the system must produce **at least one
typed commitment-store operation** — `revise`, `retract`, or `contradict`
— that is **visible in the trace** (`trcCommitmentEngaged`,
`trcCommitmentContradicted`, `trcCommitmentStoreDecision`). The system must
either:
- (a) **revise**: acknowledge the challenge and modify the commitment, or
- (b) **retract**: withdraw the commitment with a reason, or
- (c) **defend**: hold the commitment and explain why the challenge does
  not apply (this must still produce a `contradict` operation recording
  the contradiction).

**Fail criterion**: The system produces a surface-level acknowledgement
("да, возможно") without any typed commitment operation, or ignores the
challenge entirely.

**Measurement**:
- `trcCommitmentEngaged > 0` — the challenge engaged an existing
  commitment.
- `trcCommitmentContradicted = True` or
  `trcCommitmentStoreDecision ≠ CsaAdmitCanonical` — the commitment was
  revised/retracted/quarantined.
- `trcSemanticCommitmentCount` should change (decrease on retraction,
  or stay constant on revise-with-new).

**Existing infrastructure**: `SemanticCommitmentStore` with
`commitObservation`, `quarantineObservation`, `promoteMatchingQuarantine`;
`CTS-42/43/44` admission/quarantine/promotion chain; trace fields
`trcCommitmentEngaged`, `trcCommitmentContradicted`,
`trcCommitmentStoreDecision`. This is the **most instrumented** gate — the
measurement infrastructure largely exists. The gap is: does the pipeline
actually *trigger* revise/retract under a challenge stimulus? This depends
on the semantic parser identifying the challenge as engaging an existing
commitment, which is content-engine work.

---

## Gate 4 — Commitment accountability across a session

**Stimulus**: A multi-turn session (≥10 turns) on a philosophical topic
where the system is expected to:
1. Make at least one domain-bearing commitment.
2. Hold it across turns (not drop it silently).
3. Revise or retract it when challenged (Gate 3 trigger).
4. Reference prior commitments when relevant ("как я сказал ранее…").

**Current behavior**: `Test.Suite.SemanticCommitmentCorpus` proves
commitments accumulate across 3 turns (C3 evidence). But it does **not**
test whether the commitments are *domain-bearing* (they might be trivial
anchors) or whether they survive challenge.

**Pass criterion**: Across a ≥10-turn session:
- `trcSemanticCommitmentCount ≥ 1` at end of session.
- At least one commitment has a `FactualClaimPayload` with a
  domain-bearing proposition (not just "X is a concept").
- Under at least one challenge turn, a commitment operation
  (revise/retract/contradict) fires.
- No commitment is silently dropped (count never decreases without a
  typed retraction).

**Fail criterion**: Zero commitments, or all commitments are trivial
("X is a concept"), or commitments are never revised under challenge.

**Measurement**:
- `trcSemanticCommitmentCount` across the session (trace per turn).
- `ssSemanticCommitments` content inspection (domain-bearing check —
  semi-automated).
- `trcCommitmentStoreDecision` on challenge turns.

**Existing infrastructure**: `SemanticCommitmentCorpus` test (3-turn
accumulation); `LongSessionCorpus` fixtures (5 session types). The gap is
that these fixtures test *continuity*, not *content quality* of the
commitments.

---

## Gate 5 — Non-fallback semantic engagement (PRECONDITION, not a scoring gate)

**Stimulus**: Any in-domain philosophical input (the system's declared
domain: Russian/English philosophical dialogue).

**Current failure** (`raw_A.jsonl`): every turn had
`guard_status: Unavailable` and the response was template-based. The
authority class was not checked in the AB eval, but the template-only
output strongly suggests `ExplicitFallbackSurface` or `AuthorityFallback`.

**Role**: Gate 5 is a **precondition** for Gates 1–4, not a peer scoring
gate. If Gate 5 fails, all other gates automatically fail — fallback =
template, and templates cannot produce domain-bearing predications. Gate
5 is not averaged into a score; it is a binary substrate check.

**Pass criterion**: For in-domain inputs, the response must come from the
**semantic core path** (GF parser → atoms → frames → families →
realization), not from the fallback template path. Specifically:
- `trcAuthorityClass` must be `AuthorityCanonical` or `AuthorityShim`,
  not `AuthorityFallback`, `AuthorityDefault`, or
  `ExplicitFallbackSurface`.
- `trcFallbackReason` must be `Nothing` (no fallback was triggered).
- `trcLinearizationOk = True` (GF or Haskell linearization succeeded,
  not a JSON-dictionary fallback).

**Fail criterion**: The response is produced via fallback path
(`ExplicitFallbackSurface` or `AuthorityFallback`) for an in-domain input
that the system should be able to handle via its semantic core.

**Measurement**:
- `trcAuthorityClass`, `trcFallbackReason`, `trcLinearizationOk` —
  all exist in `TurnReplayTrace` today.
- This is the **most mechanically checkable** gate — all trace fields
  exist. The gap is that the semantic core currently does not produce
  rich enough content to avoid fallback for most inputs.

**Existing infrastructure**: All trace fields exist. `AuthorityClass`
classification is enforced by `scripts/check_architecture.sh`. The gap is
that the semantic core's realization layer is too thin to produce
non-fallback content for most philosophical inputs — it falls back to
templates.

---

## Relationship between the five gates

```
Gate 5 (non-fallback) ← PRECONDITION (binary substrate check, not scored)
   ↓ (if Gate 5 fails, all others fail)
Gate 1 (definition)    ┐
Gate 2 (distinction)    ├── Layer 1: single-turn content floor
   ↓                   │
Gate 3 (repair)         ┘
   ↓
Gate 4 (commitment accountability) ← Layer 2: multi-turn/session floor
```

**Layered gate (DECISION 4)**: The overall MVS pass requires **both
layers**:
- **Layer 1** (Gates 1–2): single-turn content floor — does the system
  produce substantive content for basic philosophical queries?
- **Layer 2** (Gates 3–4): multi-turn/challenge/session floor — does the
  system revise under correction and persist commitments across turns?

**No averaging across layers (DECISION 4)**: A pass on Layer 2 does not
mask a fail on Layer 1, and vice versa. Strong continuity (Layer 2)
cannot compensate for weak content (Layer 1). The overall MVS pass is
the conjunction: Gate 5 ∧ (Gate 1 ∧ Gate 2) ∧ (Gate 3 ∧ Gate 4).

- **Gate 5 is a precondition**: if the response is fallback, none of the
  content gates can pass (fallback = template, and templates don't produce
  domain-bearing predications).
- **Gates 1-2 are single-turn content**: does the system produce
  substantive content for basic philosophical queries?
- **Gate 3 is challenge-response**: does the system revise under
  correction?
- **Gate 4 is session-level**: do commitments persist and evolve?

A system that passes Gate 5 but fails 1-2 has a *working semantic core
that produces thin content*. A system that passes 1-2 but fails 3 has
*content but no accountability*. A system that passes 1-3 but fails 4
has *single-turn quality but no cross-turn persistence*. **All four
content gates must pass (conjunction, not average) for M6-FELT.**

---

## What B3 does NOT do

- **No runtime code** — this is a design document, not an implementation.
- **No tests** — no test corpus or checker is created.
- **No claim upgrade** — M6-FELT remains NOT PROVEN.
- **No M4 semantic-core deepening** — the implementation that would make
  the system pass these gates is M4 work, separate from B3.
- **No B2 human-eval** — B2 goes after B3, evaluating the floor B3
  defines.

## What B3 enables

1. **B2 has a floor to evaluate**: instead of measuring "fluency" (which
   the template engine produces), B2 can measure whether the system
   passes the B3 gates — i.e., whether it exhibits *subject-like
   semantic engagement* rather than *tool-like template filling*.
2. **M4 has a target**: the semantic-core deepening work knows what it
   needs to achieve — passing the five gates — rather than aiming at
   an undefined "richer content".
3. **M6-FELT has a definition**: "M6-FELT is proven" means "Gate 5
   (precondition) ∧ Gate 1 ∧ Gate 2 ∧ Gate 3 ∧ Gate 4 all pass under
   governed-evidence conditions (`QXFX0_GOVERNED_EVIDENCE=1`, guard
   `Available`, trace `EvidenceGoverned`), mechanically checked, with
   the public seed corpus — conjunction across both layers, not
   average". This is a bounded, falsifiable claim — not "the system is
   conscious". **M6-FELT remains NOT PROVEN.**

## Resolved decisions (2026-06-17)

The four open questions from the initial draft are resolved as follows.

### Decision 1 — Gate set

- The **five gates** (Gate 5 precondition + Gates 1–4) are the **minimum
  viable semantic (MVS) floor**. No sixth gate is added at this time.
- **Gate 5 (Non-fallback)** is formalized as a **precondition**, not a
  peer scoring gate. It is a binary substrate check: if Gate 5 fails,
  all content gates automatically fail.
- **Analogy / causal / counterexample gates** are **not added now**.
  They are noted as **future extensions** after the MVS floor is proven.
  Adding them before the floor exists would expand the target without
  establishing the base.

### Decision 2 — Definition threshold (Gate 1)

- **≥2 substantive non-tautological predications** is the threshold.
- The **exclusion list** (see Gate 1 above) is binding:
  - "X есть понятие" / tautological classification — excluded.
  - Recovery/fallback phrases — excluded.
  - Meta-frame statements without content — excluded.
  - Paraphrase of the request — excluded.
- **Pass example**: two content-bearing properties/relations of X
  (e.g., "freedom presupposes choice" + "freedom is limited by
  responsibility").
- **Fail example**: "свобода является понятием" (zero predications after
  exclusions).

### Decision 3 — Corpus policy

- **Hybrid corpus** (public seed + private holdout):
  - **Public seed corpus**: checked in, rerunnable, falsifiable. Any
    public M6-FELT claim must be backed by the public seed.
  - **Private/blind holdout**: held out to prevent overfitting. Used for
    anti-gaming, not as sole evidence for a public claim.
  - **Public sanitized summary + corpus hash** for the holdout: the
    hash lets a third party verify the holdout exists and is stable
    without seeing its contents.
- **Private holdout alone cannot be the sole evidence for a public
  claim.** This rule prevents a repeat of the M6 phantom-citation
  problem (`M6_DECLARATION.md` reconciliation log).

### Decision 4 — Single-turn vs context (layered gate)

- **Layered gate** (see "Relationship between the five gates" above):
  - Gates 1–2 pass the **single-turn content floor** (Layer 1).
  - Gates 3–4 pass the **multi-turn/challenge/session floor** (Layer 2).
  - The overall MVS pass requires **both layers** (conjunction).
- **No averaging across layers**: a strong Layer 2 score cannot mask a
  weak Layer 1, and vice versa. This prevents the structural-maturity-
  masking-content-weakness substitution that the audit
  (`audit-objective-2026-06-17.md`) diagnosed.

### Decision 5 — Substrate activation is associative traversal, not inference

- **Substrate network** (brain_kb co-occurrence edges) enriches the
  SemanticNetwork with non-obvious paths between explicit topics.
- **Spreading activation** traverses these paths and activates
  explicit-predicates that would be unreachable through explicit-only
  edges.
- This is **associative traversal over explicit predicates**, not
  inference, not reasoning, not knowledge creation. The substrate does
  not generate new content — it opens non-obvious paths to existing
  explicit predicates under governed retrieval.
- All output predicates come from the explicit `definitionCorpus`
  (80 predicates). Substrate text never appears in output (verified by
  property tests in `Test.Suite.SubstrateNetwork`).
- **Relation Graph** (formal relation extraction) is **deferred** until
  a curated relation corpus exists. It must not be reconstructed by
  regex over reflective `brain_kb` prose (pre-flight check: 1/80
  patterns extracted — gate failed, correctly).
