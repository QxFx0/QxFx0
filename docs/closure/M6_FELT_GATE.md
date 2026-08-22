# M6-FELT Mechanical Evidence Gate

- **Front**: M6-FELT gate (felt-evidence gate)
- **Status**: IMPLEMENTED (2026-08-08) — the mechanical checker exists;
  the gate currently **fails fail-closed** on real data expectations
  (it only proves a session when the runtime record satisfies Gates
  1–5 under governed-evidence conditions)
- **Depends on**: SLICE-012 (`EvidenceAdmissibility`,
  `QXFX0_GOVERNED_EVIDENCE`, `trcEvidenceAdmissibility`) — closed
- **Module**: `QxFx0.Core.M6FeltGate`
- **Tests**: `Test.Suite.M6FeltGate` (13 cases, registered in
  `TestMain`, `TestMainFast`, `TestMainUnit`)

---

## 1. What the gate is

Per `M6_DECLARATION.md` §6(4) and `B3_SEMANTIC_CORE_MVS_GATE.md`:

> M6-FELT is proven means Gate 5 (precondition) ∧ Gate 1 ∧ Gate 2 ∧ Gate 3
> ∧ Gate 4 all pass under governed-evidence conditions
> (`QXFX0_GOVERNED_EVIDENCE=1`, guard Available, trace
> `EvidenceGoverned`), mechanically checked, with the public seed corpus
> — conjunction across both layers, not average.

This module is the **mechanical checker**: a pure, deterministic
function over a session's `[TurnReplayTrace]` that audits a session as
M6-FELT evidence.

## 2. The six gates

| Gate | Criterion (trace evidence) |
|---|---|
| FeltGateGovernedEvidence | every turn `trcEvidenceAdmissibility == EvidenceGoverned` (SLICE-012 precondition) |
| Gate 5 (non-fallback) | `trcAuthorityClass` in {Canonical, Shim}; `trcFallbackReason == Nothing`; `trcLinearizationOk == True`; `trcContentSource` in {covered_exact, covered_generic} |
| Gate 1 (definition) | ≥2 turns with non-empty `trcEmittedPredicates` and non-empty rendered text |
| Gate 2 (distinction) | ≥2 distinct `trcDialogueFocus` values on semantic turns |
| Gate 3 (repair) | some turn with `trcCommitmentEngaged > 0` ∧ (`trcCommitmentContradicted` ∨ `trcCommitmentStoreDecision ≠ CsaAdmitCanonical`) |
| Gate 4 (commitment) | ≥10 turns; final `trcSemanticCommitmentCount ≥ 1`; count never drops without a typed retraction turn |

## 3. Fail-closed discipline

- An **empty session** fails all six gates.
- A session where **any** turn is ungoverned fails the whole gate —
  no averaging, no partial credit.
- A gate that **cannot be mechanically established** from the trace
  fields is reported failed; the checker never manufactures evidence.
- The verdict type names every failed gate (`M6FeltNotProven [FeltGate]`)
  — diagnostics, not a boolean alone.

## 4. Relationship to B3 and B2

- `Test.Suite.B3MechanicalGateExecution` checks the **data-level
  substrate** (the content layer exists for all covered topics).
  This module checks the **runtime-level record** (a specific session's
  traces satisfy the gates under governed conditions).
- Per B3 Decision 4 and the B2 hard guard, this gate passing for a
  session still does **not** prove M6-FELT — B2 human-eval must also
  run and pass. This gate is the mechanical floor that B2 finally
  evaluates.

## 5. Status: PROVEN (bounded benchmark, 2026-08-08)

The bounded benchmark session now passes all six gates under governed
conditions on the production runtime; the recorded mechanical verdict is
`M6FeltProven`.  (Full M6-FELT status still requires the B2 human-eval
leg per B3 Decision 4 and the B2 hard guard — the mechanical gate is the
floor that B2 finally evaluates.)

## 6. Bounded benchmark result (2026-08-08)

Per `M6_WITNESS_PROTOCOL.md` §7.3, the bounded benchmark is a real
12-turn domain-dialogue session (production runtime: real PGF, real
SQLite persistence) read back exactly as a replay consumer sees it
(`turn_quality.replay_trace_json`), evaluated by `evaluateM6FeltGate`.
Fixture: `Test.Suite.M6FeltBenchmark` — 12 turns over the definition
corpus (свобода, ответственность, истина) with a distinction turn, a
challenge turn, and follow-ups.

**Recorded mechanical verdict: `M6FeltProven`** with evidence
`feTurnCount = 12`, `feFinalCommitmentCount = 12`,
`feDistinctFocuses = 5`, `feRepairTurns = 2`.

- **All 12 turns** render on the semantic core path:
  `covered_exact` / `AuthorityCanonical` / `CsaAdmitCanonical` /
  `EvidenceGoverned`, `linearizationOk`, no fallback reason.
- **Gate 3 (commitment revision):** challenge turns 7–8
  (`контрпример…`, `я сомневаюсь, приведи контрпример к свободе`)
  engage a held claim with `trcCommitmentContradicted = True`,
  producing the required commitment revision; the store grows
  monotonically 1→12 without retraction.
- **C1–C4 contours:** definition turns 1–3/9 emit 3 predicates with
  rendered text; distinction turns 4/10 resolve
  `свобода / ответственность`; repair turns engaged; 5 distinct
  focuses; every turn governed-evidence admitted.

**How the blocker was closed (runtime defects fixed, 2026-08-08).**
The earlier `FeltGate5NonFallback` verdict traced to topic and intent
defects, not to a GF linearizer gap per se:

- **Topic extraction** (`Intent.Classifier.extractTopicAfter`): marker
  phrases like "что такое" were only matched at the start of the
  utterance; "объясни подробнее, что такое свобода" and
  "приведи пример, что такое ответственность" produced the whole raw
  phrase as the topic → `TopicNotCovered` → zero-proposition fallback.
  The marker is now searched anywhere in the utterance.
- **Topic case normalization** (new `normalizeIntentTopics` /
  `canonicalTopic` in the classifier): distinction candidates were raw
  surface forms ("ответственности", "ответственностью") that missed
  the nominative corpus keys.  Topics are now canonicalized to their
  lemma via full morphological analysis.
- **Comparison extraction** (`Semantic.comparisonCandidates`): the
  linkage pattern "как X связан с Y?" was not split as a distinction;
  added the `связан` split branch, and `связан` joined the comparison
  marks (`Features.extractHasComparisonMark`).
- **Challenge detection**: "контрпример", "докажи", "что если" are now
  challenge marks in the classifier and in
  `Effects.hasChallengeMarker` (family → CMConfront), so challenge
  turns build authoritative `GoalChallenge` plans on the engaged topic
  instead of definitional fallbacks.
- **Commitment-contradiction scoping** (`Semantic.Retrieve`): the
  contradiction atom's own tokens ("контрпример") did not word-overlap
  the held claim, so `trcCommitmentContradicted` stayed False.  The
  engagement topic (best topic ++ content nouns, choosing the one that
  overlaps a held commitment) now scopes the contradiction, letting a
  challenge aimed at "свобода" register as a genuine contradiction.
- **Content-source trace** (`Route.Render`): `trcContentSource` is now
  classified from the response-plan topic (the topic the response
  actually answers) rather than the raw best topic.

`Test.Suite.M6FeltBenchmark` pins this verdict as an anti-rot contract:
if the runtime regresses (any gate failing, or the evidence fields
shrinking below the contour minima), the test fails and the recorded
result must be updated deliberately.
## Re-run record (2026-08-22, П2 of the audit ТЗ)

The self-divergence window drop-oldest fix (canonical
`pushDivergenceSample`) changes runtime recovery behavior
(`RecoverySelfDivergence` / `StrategySelfReanchoring` can now fire on
sustained fresh divergence, which the pre-fix frozen window made
unreachable). Per the ТЗ the evidence gate was re-run on the fixed
runtime: `Test.Suite.M6FeltBenchmark` stays **M6FeltProven** with the
pinned contour (12 turns, ≥1 revision, ≥4 focuses, ≥1 repair) — no
contour values changed, so the pinned minimums remain as recorded
above. Full M6-FELT status still awaits the B2 human-eval leg.
