# QxFx0 — Objective Audit (2026-06-17)

Relative to the terminal goal as stated by the operator: *a system with
moderately human-like complexity of thought (an attempt to build the
complexity of consciousness)*, and relative to the roadmap's own terminal
anchor (`ROADMAP.md` Final Anchor Doctrine).

This audit is a synthesis-and-correction pass over the four prior audits
(`audit-comprehensive-2026-06-03`, `audit-proactive-2026-06-06`,
`audit-synthesis-2026-06-06`, `audit-round3*`). The prior audits assessed
production-readiness of the plumbing; none assessed **cognitive content**
against the North Star. This one does, then corrects its own earlier
overstatements using operator refinements.

---

## 0. The goal is split — name it first

The operator's phrasing ("complexity of consciousness") and the roadmap's
terminal anchor disagree, and the disagreement is load-bearing:

- **North Star** (`ROADMAP.md` top): a *digital subject* — stable identity,
  holds positions, accountable to its own commitments, "subjecthood must be
  *felt outward* in dialogue".
- **Final Anchor Doctrine** (same file, lower): "algorithmic subject
  structure **does not mean consciousness, personhood, unrestricted general
  intelligence, or anthropomorphic theater**". `THEORY.md` §5 and
  `M6_DECLARATION.md` §9 repeat this verbatim.

Across M0→M6 the project **retreated** from "subject" to "a bounded
evidence package that code can sustain an algorithmic subject *structure*
for meaningful dialogue". That is not a nuance; it is a different goal. Any
honest verdict must be given against both, separately.

---

## 1. What genuinely succeeded

Not decoration — real engineering:

- **150k LOC, 372 modules, 8-layer architecture** with mechanically
  checked dependency invariants (`scripts/check_architecture.sh`).
- **Discipline spine**: typed CTS admission chain (CTS-01…33+), commit/restore
  state machine, authority/projection/fallback/compatibility classification,
  replay traces, ~1217 unit + 135 slow + property tests. Library and
  `test-fast` build clean (73/73) on GHC 9.6.7 / cabal 3.14.
- **Pure Self algebra**, property-verified: `Holistic ⊣ Formal` adjunction
  with proven triangle identities, `Field` combination laws, Conatus
  scalar/gradient, `reconcile` with property locks. `audit-synthesis`
  confirms: "the philosophical core `Self/*` produced **zero** defects —
  bugs are all in serialization/persistence/IO."
- **Bidirectional GF parser** (words→atoms→families→words), ≥99% round-trip
  on `Move*` — a real formal-grammar result.
- **RGL morphology** (20k lemmas), **commitment store** with
  quarantine→promotion (CTS-42/43/44) — real accountable-revision mechanics.
- **Intellectual honesty infrastructure**: `THEORY.md` §5,
  `SELF_LAYER_STATUS.md` §6 (binary "core runtime today?" verdicts),
  `M6_DECLARATION.md` §4 (negative criteria). The project can say "this is
  not what we claim it is" — rare.

---

## 2. What did not succeed — relative to "complexity of thought"

**Correction of the earlier "empty core" framing (operator refinement 1).**
The core is not empty. There is real content machinery: semantic
decomposition into atoms/frames, typed routing (the golden corpus really
does classify syllogism / transitivity / negation into distinct
`CanonicalMoveFamily`), GF parser, morphology, commitment-store operations,
admission chain, learning fixtures. The accurate statement is:
**the content engine is *weak relative to the North Star*, not absent.**

What is hollow is specifically the **realization + argumentation** layer:
generation is template + one lemma per slot
(`data/semantic/realization_examples.jsonl`:
`{"template_role":"ask_specific","slots":{"nom:topic":"Смысл"}}`).
Decomposition/routing produce a *move family*; the family is then filled
with a template whose only domain token is a single extracted lemma. So
"свобода является понятием" ("freedom is a concept") is not a failure of
understanding — the router correctly chose `CMDefine` — it is a failure of
*content generation under that family*.

The cognitive "cores" by code reading:
- **Conatus** ("primary algorithm, precondition under which every other
  process makes sense", `THEORY.md` §4.3): `C = w_m·log(1+m) + w_c·log(1+c)
  + w_t·log(1+t) − λ|v|` — a weighted log of **three counters** (morphology
  size, identity-claim count, turn count). A bookkeeping scalar, not
  "striving".
- **Field**: a record of 5 hand-set `Double`s; the module states it "does
  NOT source values from the runtime".
- **"Consciousness"** (`ConsciousnessLoop` → `kernelPulse`): a
  keyword-driven stance classifier (`containsAnyKeywordPhrase`,
  `surfacingMarkerKeywords`) emitting a narrative fragment gated by
  salience. `SELF_LAYER_STATUS` itself flags `kernelPulse` as "the largest
  **observability-only** risk — produces text-shaped output that is not
  typed".
- **`reconcile`**: a 6-rule cascade selecting `Plan` fields by
  priority — arbitration, not thought.

**Decisive evidence — actual dialogue output**
(`reports/ab_dialogue/ab-eval-2026-05-21/raw_A.jsonl`), the very "felt
outward in dialogue" the North Star names:
- T1 "что такое свобода" → "…**свобода является понятием**. Локальный режим
  восстановления…". Entire semantic payload: "freedom is a concept"; the
  rest is boilerplate.
- T2 → substitutes the lemma "смысл" for the topic.
- T3 → breaks: "…**Ядро: Ядро ищ**" (truncated mid-word).
- T4 "в чём разница свободы и произвола" → "Сравнение плаузибельности
  требует явной рамки…" — a template, no comparison.
- **AB `blind_pairs`: `response_1` ≡ `response_2`** in every pair — the
  two "versions" are indistinguishable because the output is identical
  template text (and a Russian lemma leaks into the English answer).

**The corpus tests measure routing, not thought.** Golden corpus asserts
`expected_family_any_of` + `must_not_focus`, never content quality. All
four M6 evidence contours (C1–C4) are about continuity / trace-fields /
commitment-store mechanics / GF round-trip. **None measures quality of
thinking.**

---

## 3. The guard-unavailable finding — precisely stated

**Correction (operator refinement 3).** The `guard_status: "Unavailable —
nix evaluator unavailable: evaluation_failed"` in the 2026-05-21 AB report
is **stale evidence, not a present-tense-broken claim**. I did not re-run a
fresh turn this audit, so I cannot assert nix is unavailable *now*.

But the precise consequence is stronger than "old run was degraded": the
**evidence base for the felt-claim was collected in ungoverned mode**, so
it cannot prove "governed, checked conditions". The problem is not the
environment; it is that the evidence methodology did not guarantee guard
availability at collection time. Mechanically:

- `NixGuard.hs:63-64`: `runNixEval` failure → `Unavailable …`; success but
  unknown result → `Unavailable …`.
- `Prepare/Build.hs:101-103`: `Unavailable` → `nixAvailable = False`,
  `isNixBlocked = False`. So an unavailable guard is **fail-open
  degraded**, not fail-closed: the turn proceeds, `tdGuardStatus` is
  stamped `Unavailable`, and the route continues.
- `Cascade.hs:123`: only `isNixBlocked` (a `Blocked` verdict) forces
  `CMRepair`; `Unavailable` does **not**.
- `Route/Build.hs:292`: `not tiNixAvailable` → `ExplicitFallbackSurface`
  on the *authority surface*, but the turn still emits output.
- `docs/fallback_policy_classification.md` §86 confirms: "prepare missing
  nix result … **fail-open degraded** … turn continues with blocked guard
  status … not fail-closed in prepare stage".

So in the AB run, every turn ran **without constitutional governance**
and still produced the felt-evidence. `M6_DECLARATION.md` §2.1 item 4
("governed distinction … enforced by … the live CTS admission chain") is
not falsified by this — but the *felt-output* evidence that would make
subjecthood "felt outward" was gathered outside that enforcement. This is
**stale-evidence inadmissibility**: the old felt-claims cannot stand as
proof of governed conditions, independent of whether nix is up today.

**M6 evidence contours do not close this gap.** `Test.Suite.M6Witness` and
`Test.Suite.M5Regime` contain no assertion on guard availability
(grep-confirmed: no `nix`/`Available`/`Unavailable` references). The C1–C4
witness regime certifies trace-field presence, commitment-store
mechanics, GF round-trip, and architecture gates — none of which requires
the constitutional guard to have been `Available` at evidence time.

---

## 4. The two-track reframing (operator's main addition)

The cleanest statement of the diagnosis is not "discipline vs empty core"
but **two tracks with opposite maturity**:

| Track | Contents | Maturity |
|---|---|---|
| **Structural subject runtime** | governance, authority classification, replay, commit/restore, commitment store, admission chain, restart integrity, regime versioning | **mature** (M6-STRUCTURAL partial claim holds) |
| **Cognitive content engine** | semantic reasoning quality, definition/comparison/repair content, challenge-response argumentation, felt-output discrimination | **under-specified and not measured as pass/fail** |

The project spent ~2 years hardening track 1. Track 2 exists in pieces
(decomposition, routing) but has no quality gate and its realization layer
is template-thin. "M6 almost finished" (my earlier framing) is true **only
for track-1's M6-STRUCTURAL partial**; for the overall goal the remaining
track-2 items — semantic-core MVS, B2 human-eval, corpus/replay against
real output, calibration — are NOT PROVEN. Conflating the two was my
error; the split is the correct lens.

**Integration constraint (this audit's addition to the operator's
framing).** The content engine cannot be built *beside* the structural
runtime — its outputs must pass **through** the existing admission
chain, or it becomes a hidden second semantic ruler, which the doctrine
forbids (`ROADMAP` M4.5: "no live second semantic ruler … no live
co-rulership"). M4.5 `DreamPressure` already supplies the template: a
**typed correction-pressure that enters via governed acceptance**, not a
silent authority rewrite. So the real M4 semantic-core deepening is not
"build a separate engine" but "build an engine whose outputs are
admissible under CTS". The deferral rule ("semantic-core must not outrun
state/authority discipline") was a legitimate sequencing guard; with
state-discipline now mature, continued deferral has crossed from
protection into avoidance.

---

## 5. Concrete defects confirmed this session

### 5.1 Essence regime drift — TRIPLE (the cheapest real defect)

Three sources disagree about whether Essence commitment is active:

1. **Code, operational path** — `Finalize/State.hs:344` comment: "`shouldCommit`
   is always evaluated; **no feature flag**". `shouldCommit
   defaultEssenceModulation trajectory'` runs unconditionally every turn;
   `EssenceCommitted` is sticky and never reverted. So **Essence is
   operationally always-on**.
2. **Code, regime stamp** — `RuntimeRegime.hs:81`:
   `rrEssenceActive = True  -- ADR-0036 promoted 2026-06-04`. But `rrEssenceActive`
   is **write-only**: grep confirms it is set here and read nowhere (only
   the field declaration at `:56` and this assignment). It stamps the
   trace without gating anything.
3. **Docs/tests** — `AGENTS.md` and `SELF_LAYER_STATUS.md` state
   `essenceCommitmentEnabled = False` (flag-off, "not counted as active
   subject evidence"); `Test.Suite.PromotionFlagDiscipline` references an
   `essenceCommitmentEnabled` flag + `QXFX0_ESSENCE_COMMITMENT_ENABLED`
   env var that **do not exist in `src/`** (grep-confirmed). ADR-0036 lives
   in `docs/adr/proposed/` — i.e. **proposed, not accepted** — yet the code
   comment cites it as "promoted".

Net: Essence is always-on in behavior, stamped-on in regime, documented
-off, and gated by a nonexistent flag tested by a discipline test. This is
exactly the "claim ≠ reality" seam the project doctrine declares
inadmissible — sitting on the most load-bearing subjecthood assertion.
Front: **ESSENCE-REGIME-RECONCILE**.

### 5.2 Stale-evidence inadmissibility for felt-claims — §3 above.

### 5.3 Content engine has no pass/fail gate — §2/§4.

### 5.4 Prior-audit defects still open

From `audit-synthesis` / `audit-proactive` (not re-verified this session,
cited as still-relevant context): Class-I trust-boundary leaks, Class-II
encode/decode asymmetry (no `decode . encode == id` discipline), Class-III
half-migrated `*Error Text`/`*ErrorStructured` pairs, toxicity
fail-open-then-fixed (now fail-closed per README). The `ROADMAP` IH-1…IH-5
tail tracks these as the active hardening queue. They are track-1 work and
do not move toward track-2.

---

## 6. Verdict

The project built an **exceptionally elaborated legal code of a subject
without building the subject's mind**. The North Star explicitly rejected
the LLM path ("everyone else builds tools; we build a subject") — then
built the *legal code of the subject*, which is an orthogonal axis. An
ideal governance shell around a weak content engine (≈ where we are) and a
rich mind with poor governance (an LLM) are two independent axes;
discipline-first sequencing was justified, but it has passed its optimum:
discipline is mature, the mind never appeared, and the next CTS seam or
observability field will not move toward "moderately human complexity of
thought".

"Stop and publish the bounded result" — my earlier phrasing — is correct
**only for track 1** (M6-STRUCTURAL partial: stop polishing the carapace,
publish what is honestly proven). It is capitulation **for track 2**,
which is the actual goal. The operator's framing is right: the path
forward is not another governance layer, it is finally filling the
discipline with content — semantic-core deepening as M4, with felt-evidence
that can discriminate subjecthood from fluency.

---

## 7. Recommended fronts (ordered)

1. **ESSENCE-REGIME-RECONCILE** — collapse the triple drift (§5.1) to one
   truth across code-behavior, regime-stamp, docs, the nonexistent flag,
   and ADR-0036's status. Cheap; drift already confirmed; pure
   discipline-the-discipline. Precondition for any honest essence claim.
2. **SLICE-012 (environment / guard / GF / nix)** — make "governed,
   checked conditions" actually hold in real runs, and **gate
   evidence-collection on guard `Available`** so future felt-claims are
   gathered in governed mode. Without this, any track-2 evidence repeats
   the §3 inadmissibility.
3. **M6-FELT / B3 — semantic-core MVS gate** — a pass/fail gate on
   *content quality* (definition, comparison, repair, challenge-response),
   not on routing family. This is the missing measurement on track 2.
   Design constraint from §4: the richer engine must be admissible under
   CTS (M4.5 `DreamPressure` pattern), not a bypass.
4. **B2 — human-eval as discrimination against a fluency-matched ablated
   control** — methodologically the correct test *because* the project is
   anti-fluency by doctrine: if ablation (content engine off, fluency
   scaffolding on) is indistinguishable from full, the content engine adds
   nothing and the felt-claim is false. This is the external verdict on
   track 2; it is explicitly *not* a "consciousness" test.

Sequencing logic: RECONCILE is cheap and unblocks honest essence status;
SLICE-012 is the precondition for any future governed-evidence; M6-FELT
is the real content gate; B2 is the external verdict that closes track 2.
None of these is "another layer of governance" — RECONCILE and SLICE-012
are about making existing governance *true*, M6-FELT and B2 are about
finally measuring the mind.

---

## 8. Provenance

| Item | Value |
|---|---|
| Date | 2026-06-17 |
| Toolchain verified | GHC 9.6.7, cabal 3.14.2.0; `cabal build lib:qxfx0` up-to-date; `cabal build qxfx0-test-fast` 73/73 clean |
| Git HEAD | `c680b2c` (docs: SLICE-015 deferred) |
| Evidence basis | `ROADMAP.md`, `docs/THEORY.md`, `docs/closure/M6_DECLARATION.md`, `M6_CLAIM_PACKAGE.md`, `SELF_LAYER_STATUS.md`, `audit-synthesis/proactive/comprehensive`, `src/QxFx0/Self/*`, `src/QxFx0/Core/ConsciousnessLoop.hs`, `src/QxFx0/Bridge/NixGuard.hs`, `src/QxFx0/Core/TurnPipeline/{Prepare,Route,Finalize}/*`, `src/QxFx0/Types/RuntimeRegime.hs`, `reports/ab_dialogue/ab-eval-2026-05-21/raw_A.jsonl` + `blind_pairs.jsonl`, `test/golden/semantic_corpus.jsonl`, `data/semantic/realization_examples.jsonl` |
| Not re-verified | fresh-turn nix availability (§3 is stated as stale-evidence, not present-tense); full test-suite pass/fail (build only) |
| Supersedes | nothing; corrects the "empty core" / "almost finished" framings of this author's earlier verbal report |
| Operator refinements incorporated | (1) weak content engine, not empty core; (2) M6-STRUCTURAL partial ≠ overall goal; (3) stale-evidence inadmissibility, not present-tense broken; (main) two-track reframing; (fronts) RECONCILE / M6-FELT-B3 / B2 ablated-control / SLICE-012 |
