# ADR-0055: Gated Cutover — Ownership Microworld Reads the IR

**Status:** Accepted
**Date:** 2026-10-07
**Accepted-By:** operator review (2026-10-07)
**Related:**
- ADR-0054 (Stage-1 shadow program — exit recorded below; this ADR is the cutover it made writable)
- `docs/closure/CALIBRATION_REPORT.md`: Stage-1 batches A–E landings, trace review (2026-10-07), human-leg packet (20/20 operator-confirmed)
- `data/semantic_ir/` (rules, compositions, ownership library, exit tasks, human-leg packet) + `qxfx0-stage1-traces` emitter

---

## 1. Context

Stage-1 exited: mechanical leg PASS (strict 17/17, defeasible
12/12, conflicts/presuppositions exact, scenarios 40/40,
measured by emitter 2026-10-07) + human leg CONFIRMED
(20/20 novel items, zero false-authority). The shadow stack
is complete: verdicts with boundaries (Batch A), epistemic
statuses with a leak ban (Batch B), typed composition
(Batch C), event-sourced state with lineage (Batch D), and
the ownership contract library with held-out application
proof (Batch E, including the lend→query→correct-to-give
demo path verbatim).

What does not exist yet: any runtime reader of this stack,
and any Russian-utterance → event parser. Cutover must build
both, bounded, without touching the existing definitional
path (172 corpus topics keep serving exactly as today).

## 2. Decision

### 2.1 Bounded domain

Ownership event histories over explicitly named participants:
give / lend / return / take / show / steal / return-right +
the borrower rule, exactly the Batch E library. Nothing else
reads the IR. The freedom-cluster definitional path, the
compositional fallback, and all guards keep byte-identical
behavior outside the gate below.

### 2.2 Entry gate (total, honest boundary)

The IR path fires only when ALL hold:

1. The utterance matches the ownership micro-grammar:
   pattern detectors (established style — cf. the 23-detector
   chain) for the 7 events over explicit entity mentions.
2. All event participants resolve to concrete entities
   (no pronouns, no bare roles — those abstain).
3. The resulting history evaluates without data errors
   (preconditions bind, no unbound variables).

Anything else — including ambiguous, pronominal, or
out-of-domain input — takes the legacy path unchanged. The
gate is total and logged per turn (fired/passed + reason).

### 2.3 Staged sequence

- **Stage 1 — shadow-compare** (no surface change): the IR
  path computes alongside the legacy path on gated inputs;
  the trace carries both surfaces + verdicts + lineage.
  Operator reviews divergence on a fixed battery (the Batch E
  demo path + minimal contrasts + correction cases).
- **Stage 2 — gated surfaces**: only after the review finds
  zero unattributed divergence, IR surfaces render through
  the Batch B contract (Grounded/Refuted/Hypothesis/Abstain
  templates), with status tags in the trace.
- **Rollback**: the wiring is additive behind one gate
  function; removal restores legacy behavior byte-identically.
  Nothing needs unwinding.

### 2.4 Standing rules (non-negotiable)

- Abstain-first: outside the gate, or on any data error
  inside it, the system abstains honestly (established
  abstain phrasing) — never falls back to inventing
  ownership content.
- Leak ban (Batch B) enforced at wiring: hypothesis and
  composition outputs never enter strict proof, never
  recorded as facts, never upgraded at render.
- Explain = links: every IR surface carries its proof /
  lineage references (Batch A proofs + Batch D lineage),
  not decorative justification.
- Success criterion (locked): Build / Distinguish / Apply /
  Revise / Explain / Abstain — each mechanically checked on
  the gate battery. Abstain is scored: over-refusal fails
  the gate the same way false authority does.

### 2.5 Exit criteria for the cutover itself (preset here)

- Shadow-compare battery: 100% agreement on verdicts, all
  divergences triaged with documented reasons.
- Live gate battery (fixed, in-repo): the Batch E demo +
  all minimal contrasts + 5 correction variants — all green,
  zero false-authority, abstain rate within the preset band
  (recorded in the landing, not fitted after).
- Full matrix green (unit/fast/core/property/integration;
  slow per discipline — the gate touches live surfaces).
- Two-round sunset: if either round breaches, the wiring is
  removed and the stack stays shadow permanently.

## 3. Alternatives

- **A. Big-bang rewrite** (all dialogue through IR now).
  Rejected: no RU→IR parser exists outside the microworld;
  kills the green matrix; violates every staged precedent.
- **B. Stay shadow forever.** Fallback, not plan: keeps
  honesty work without ever testing it live. Taken
  automatically if §2.5 fails twice.
- **C. LLM parser for the domain.** Rejected: nondeterministic
  input stage needs Stage-6 gates; the micro-grammar is
  deliberately boring and total.
- **D. Cut over the definitional path first** (172 topics
  through IR). Rejected: the microworld is the demonstrated
  domain; definitions already serve honestly.

## 4. Sunset clause

If the §2.5 criteria are unmet after two full rounds, the
gated wiring is removed: the IR stack stays shadow
permanently, no further cutover ADR may cite this one, and
effort returns to corpus-level and shadow work. Bounded cost,
no sunk-cost pressure.

## 5. Consequences

Additive only: one gate function + micro-grammar detectors +
wiring to the existing shadow modules + gate battery +
trace fields for the compare stage. Zero changes to legacy
paths (pinned byte-identical). Review load: the operator
reviews shadow-compare divergence and rates the live gate
battery under the landed rater doctrine. On exit, the domain
may widen by follow-up ADR; on sunset, deletion of the
wiring restores the status quo.

## 6. Quality Gate

- This ADR: operator review flips `Proposed` → `Accepted`
  before any wiring lands (ADR-0048 process).
- Pre-registration with locked rule + bar before each stage;
  operator confirms live wordings verbatim per doctrine.
- Mechanical gate numbers reproduced, not fitted; human
  rating per batch with honest abstain allowed and false
  authority failing the batch.
