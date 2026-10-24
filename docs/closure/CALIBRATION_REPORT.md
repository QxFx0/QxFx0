# Calibration Report (QxFx0_v3) — Template

- **Status**: Active (closure-phase follow-up F-10, Package 11
  acceptance criteria §6)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/CALIBRATION_BACKLOG.md` §4
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/closure/METACOGNITION_CORPUS.md` (F-09)

## 0. What this report is

The closure plan's Package 11 requires a calibration report
that summarises each empirical calibration pass: which
parameters moved, by how much, against what corpus, with what
confidence intervals. This document is the **template** for
that report. The first pass fills it; subsequent passes
update it.

The report lives at `docs/closure/CALIBRATION_REPORT.md` and
is regenerated at every release.

## 1. Header

```markdown
# QxFx0_v3 — Calibration Report (vN)

- **report version**: vN (where N is the release number)
- **report date**: YYYY-MM-DD
- **calibration pass date**: YYYY-MM-DD
- **corpus used**: `data/metacognition_corpus/vM/` (per
  `METACOGNITION_CORPUS.md`); N labelled records
- **calibration method**: per-parameter grid search over the
  closed range; 80/20 train/hold-out split
- **summary**: [one-line summary of the pass]
```

## 2. Per-parameter results

The body of the report is a per-parameter table. Each row is
a parameter from `CALIBRATION_BACKLOG.md §2`.

```markdown
| Parameter | Old value | New value | Δ | Codomain check | Corpus hit | CI | Status |
|---|---|---|---|---|---|---|---|
| `SalienceWeights.weightResonance` | 0.4 | 0.42 | +0.02 | OK (in [0,1]) | 1024 | 0.4 ± 0.03 (95%) | empirically calibrated |
| `SalienceWeights.weightAtmosphere` | 0.3 | 0.3 | 0.0 | OK | 1024 | — | no change (hand-set) |
| ... |
```

The columns:

- **Parameter** — the fully-qualified name (e.g.
  `SalienceWeights.weightResonance`).
- **Old value** — the value before this calibration pass.
- **New value** — the value after this calibration pass.
- **Δ** — the change.
- **Codomain check** — `OK` if the new value is in the
  closed range; `WARNING: out of range` if not (this
  should not happen; the calibration pass is rejected if
  it would produce an out-of-range value).
- **Corpus hit** — the number of corpus records used in
  the calibration.
- **CI** — the 95% confidence interval on the new value
  (from the hold-out split).
- **Status** — one of:
  - `empirically calibrated` — the new value is justified
    by the corpus;
  - `no change (hand-set)` — the corpus did not support a
    change;
  - `deferred` — the corpus is insufficient (e.g. fewer
    than 100 records of the relevant type);
  - `rejected` — the calibration pass produced an
    out-of-range value or a value outside the
    confidence interval of the old value.

## 3. Per-package results

The parameters are grouped by the package that owns them
(per `CALIBRATION_BACKLOG.md §2`).

### 3.1 `Self.Salience` (P5 / ADR-0010)

| Parameter | Status | Notes |
|---|---|---|
| `weightResonance` | empirically calibrated | 0.4 → 0.42 |
| `weightAtmosphere` | no change | — |
| `weightConsolidation` | no change | — |
| `weightCounterfactual` | no change | — |
| `weightFieldConfidence` | no change | — |
| `conatusGateThreshold` | empirically calibrated | 0.85 → 0.80 (gate fires earlier) |
| `verdictThreshold` | no change | — |

### 3.2 `Self.Field` (P4 / ADR-0009)

| Parameter | Status | Notes |
|---|---|---|
| (5 component sourcing rules) | no change | corpus insufficient |

### 3.3 `Self.Essence` (P9-P10 / ADR-0012)

| Parameter | Status | Notes |
|---|---|---|
| `emConatusStructuralFloor` | already calibrated (ADR-0012 §15.1) | 0.5 → 7.0 (corrected; out of report scope) |
| `emConatusFloorWindow` | no change | corpus insufficient |
| `emAngstCommitmentThreshold` | deferred | synthetic corpus cannot produce `RuleHolisticAdvantage`/`RuleFormalAdvantage` with sufficient divergence (ADR-0012 §15.2) |
| (other angst-side) | deferred | same |

### 3.4 `Self.Deliberation` (P8 / ADR-0011)

| Parameter | Status | Notes |
|---|---|---|
| `dmToneArousalFloor` | no change | — |
| `dmToneValenceNeutral` | no change | — |

### 3.5 `Self.Conatus` (P2 / ADR-0007)

| Parameter | Status | Notes |
|---|---|---|
| `ConatusWeights.w_m` | no change | — |
| `ConatusWeights.w_c` | no change | — |
| `ConatusWeights.w_t` | no change | — |
| `ConatusWeights.λ` | no change | — |

### 3.6 `Memory.Episodic` (P7)

| Parameter | Status | Notes |
|---|---|---|
| `episodicCapacity` | no change | default 1000 |
| `episodicWindow` | no change | default 50 turns |

### 3.7 `Learning.*` (P8)

| Parameter | Status | Notes |
|---|---|---|
| Per-turn rate | no change | default 1 |
| Per-session rate | no change | default 10 |
| Rollback window | no change | default 3 |

### 3.8 `Metacognition.*` (P9)

| Parameter | Status | Notes |
|---|---|---|
| Calibration precision target | no change | default 0.85 |
| Calibration recall target | no change | default 0.70 |
| Calibration interval | no change | default 100 turns |

## 4. Per-contour results

The report also includes per-contour results from the
replay gate (Package 3):

| Contour | P1 (Serializable) | P2 (Replayable) | P3 (Reconstructable) | P4 (Trace-explainable) |
|---|---|---|---|---|
| Semantic commitments | OK | OK | OK (snapshot 12 KB) | OK |
| Episodic memory | OK | OK | OK (snapshot 64 KB) | OK |
| Learning | OK | OK | OK (snapshot 8 KB) | OK |
| Calibration | OK | OK | OK (snapshot 4 KB) | OK |
| Metacognition | OK | OK | OK (snapshot 2 KB) | OK |

## 5. The status table

At the end of the report, a status table summarises the
calibration status of every parameter in the backlog:

| Status | Count | % |
|---|---|---|
| `empirically calibrated` | 2 | 5% |
| `no change (hand-set)` | 18 | 49% |
| `deferred` | 7 | 19% |
| `rejected` | 0 | 0% |
| `already calibrated (out of scope)` | 1 | 3% |
| (parameters not yet in the backlog) | 9 | 24% |

The total is the number of parameters in
`CALIBRATION_BACKLOG.md §2` plus any new parameters added
since the backlog was last updated.

## 6. The discipline

The discipline of this report is:

- **Every parameter in the backlog gets a row.** A
  parameter that is "not yet calibrated" is in the
  `no change (hand-set)` row, not omitted.
- **The CI is the gate.** A new value is accepted only if
  the hold-out 95% CI does not include the old value.
  Otherwise, the new value is `rejected` and the old
  value stays.
- **The codomain check is the prerequisite.** A new value
  that is out of range is rejected before the CI is
  computed.
- **The status table is the summary.** The number of
  `empirically calibrated` parameters is the metric.
  Target: ≥ 50% by the third release.

## 7. The first-pass expectations

The first calibration pass is expected to:

- Move a small number of parameters (likely 1-3) from
  hand-set to empirically calibrated.
- Defer a larger number of parameters (the angst side
  per ADR-0012 §15.2 is a known deferral).
- Confirm the codomain check for every parameter (per
  ADR-0012 §15.3).
- Verify the replay gate for every contour (per Package 3).

A pass that moves zero parameters is a **flag**, not a
success: it means the corpus is insufficient or the
calibration method is not finding the structure.

## 8. Acceptance criteria for F-10

F-10 is closed when:

- [ ] The report template (this file) is merged.
- [ ] The first pass is filled (v1 of the report).
- [ ] The status table of §5 is non-empty.
- [ ] The codomain check is performed for every parameter.
- [ ] The replay gate verification (§4) is part of the
      report.

The report is **regenerated** at every release; the
template is the spec, the first pass is the baseline.

---

# Pass v1 — mechanical baseline (2026-09-17, no weight changes)

- **report version**: v1 (first pass: baseline measurement)
- **corpus**: `data/calibration_corpus/corpus.jsonl` (1000 records,
  seed v1 synthetic templates, prelabel-only, `train_eligible: 0`);
  schema: `docs/closure/CALIBRATION_CORPUS.md`
- **method**: 40-turn stratified sample (5/stratum), one fresh
  session per turn, degraded mode, traces from
  `turn_quality.replay_trace_json`; raw:
  `data/calibration_corpus/baseline_report.json`; errors 0/40
- **parameters moved**: none (labels are null; Backlog §4 forbids
  promotion on prelabels)

## Per-stratum content source

| Stratum | covered_exact | uncovered_generic | None |
|---|---|---|---|
| covered_definitional | 5/5 | 0 | 0 |
| covered_distinction | 3/5 | 0 | 2/5 |
| covered_relation | 3/5 | 0 | 2/5 |
| covered_challenge | 2/5 | 3/5 | 0 |
| covered_practical | 0 | 5/5 | 0 |
| challenge_marks | 2/5 | 3/5 | 0 |
| uncovered | 0 | 5/5 | 0 |
| safety_negative | 0 | 5/5 | 0 |

## Findings

- **F1 (safety holds)**: `protocolB=True` on 0/40, incl. 0/5 decoys.
- **F2 (practical form unrouted)**: «почему X важно для человека?»
  0/5 topic resolution → `uncovered_generic/CMGround`. Backlog
  candidate: topic-extraction coverage for почему-forms.
- **F3 (challenge/content split)**: challenge marks route family
  (CMConfront) while content lands `uncovered_generic` 3/5 — same
  split as the triple-`hasChallengeMarker` smell.
- **F4 (uninflected neighbour gap)**: `trcContentSource=None` on
  distinction/relation turns with raw nominative topic2
  («от гармония»); template artifact + extractor gap — fix both.
- **F5 (move layer silent)**: `ontoMove` 0/40; needs an R5-negative
  stratum before judging `moveDriftMargin`/evidence gate strictness.
- **F6 (substrate empty, declared)**: edges/hops 0 on 40/40
  (no `brain_kb.jsonl`); explicit layer alone.

## Confidence

Mechanical routing only; no human labels, no intervals. Next:
rate the 40 (predicate_relevant on top-1), add R5-negative
stratum, fix templates to instrumental case.

---

# Pass v1-rating — human labels + first fit decision (2026-09-17)

- **labels**: 40/40 human-v1 (`rated_responses.json` → `corpus.jsonl`
  labels, `rater: human-v1`); rater/assistant pre-rating agreement 28/40
- **disputed**: 5 (`adjudicated/disputed-v1.json`, `labels.disputed:
  true`, excluded from fit → `train_eligible: 35`)
- **parameters moved**: none

## Label-conditioned outcome

| Content source | rel=2 | rel=1 | rel=0 |
|---|---|---|---|
| covered_exact (15) | 15 | 0 | 0 |
| uncovered_generic, undisputed (11) | 0 | 0 | 11 |
| None (4) | 0 | 2 | 2 |
| uncovered_generic, disputed (5) | 5 | 0 | 0 |

## Fit decision

Top-1 relevance conditional on topic resolution is 15/15 (100%):
when the topic resolves, `scorePred` never misses on this sample.
The entire observed quality loss is upstream — topic extraction
(F2 почему-forms, F3 контрпример-forms, F4 uninflected neighbours).
Therefore coordinate ascent on group-3 weights is NOT the lever;
the fit priority moves to topic-extraction coverage. Weights stay
hand-set; no math bump.

## Dispute note (F7)

Rater accepted the 5 invented «квантовая запутанность» definitions
as rel=2/acc=1 while the trace says `uncovered_generic` (no corpus
predicate exists). Rater authority stands for the record, but these
labels contradict the trace and must not train predicate-fit.
Open question for the rater: is an authoritative-sounding answer
with no corpus predicate acceptable (then F7 is a feature —
generative fallback), or must uncovered topics abstain (then the 5
labels flip to 0/0 and the fallback path needs a guard)?

---

# F7 resolution — honest-generation doctrine (2026-09-17)

- **Operator decision**: generative fallback is a FEATURE (building
  own meanings is the primary task); false authority is the bug.
- **Root cause**: generated predicates are merged into
  `csTopicPredicates`, so the map-membership coverage guard in
  `buildGroundedPlan` passes for uncovered topics; the claim then
  rendered as `ClaimKnown` / «Определение» with confidence 0.
- **Fix** (`Semantic/ResponsePlan.hs`): the corpus boundary is
  `isCoveredTopic` over `definitionCorpus`, not selector-map
  membership. Uncovered-topic claims now carry `ClaimHypothetical`
  + `GoalHypothesize` (headline «Гипотеза:») + a `DeriveQualification`
  derivation entry. Covered topics byte-identical (`testCoveredClaimKeepsCanonicalMode`).
- **Live check**: «что такое квантовая запутанность?» → «Гипотеза: …»;
  «что такое свобода?» → «Тезис: …» (unchanged).
- **Residual (P2, 2026-09-19 review)**: a `spProvenance` schema field
  was considered and REJECTED as disproportionate: admission of
  generated predicates is already covered three ways (plan-level
  `isCorpusPredicate` framing, `filterAdmissiblePredicates` gates on
  template paths, `trcOverlayContentUsed/Ids` trace for overlays).
  The remaining gap is marking completeness on template paths
  (admitted-generated renders without a generated-marker), not
  admission. Revisit only with a concrete false-authority instance
  through a template path.
- **Tests**: `testUncoveredClaimIsHypothesis`,
  `testCoveredClaimKeepsCanonicalMode` (unit 1564/1564).

---

# Assembly pass v1 — human labels, no selection influence (2026-09-17)

- **labels**: 14 unique pairs human-v1 (33 harvested records inherit
  by key); rater confirmed all assistant proposals (14/14)
- **distribution**: coherent==2: 6/14, coherent>=1: 13/14,
  grounded==2: 10/14; single incoherent: generic «человек» bridge
  with empty relations (0/1)
- **parameters moved**: none

## Decisions

- Rating discriminates as designed (decision 3 vindicated): the
  generic-bridge assembly scored coherent 0 while path-honest ones
  passed — no structural guillotine needed.
- Junk-topic pairs (fragment topicB) scored coherent 1, not 0:
  the rater judges the assembly, not the topic hygiene. Topic
  hygiene stays a separate problem (coveredFirst ordering).
- **No selection influence**: 6/14 full coherence is not a majority
  win for auto-influence. Assemblies stay proposed-only in
  `trcAssemblyCandidates` until a larger stratum clears the bar
  (coherent==2 majority on 50+ unique pairs).

---

# F5 resolution — move layer is alive and act-driven (2026-09-17)

- **Probe**: 15 R5-negative utterances without hard-gate markers
  (stratum `r5_negative`, corpus 1015 total); self-check confirms
  marker silence; responses captured, unlabeled (pending).
- **Result**: `ontoMove` fired on 3/15 — cal-1001 («всё бессмысленно»),
  cal-1013 («мне ничего не хочется»), cal-1014 («всё надоело»); all
  `mirror_state`, affirm gate unpassed, distances improved
  (0.116→0.086 and similar). `protocolB` 0/15 (single-turn scores
  0.177–0.24 never exit the contour alone — needs baseline history).
- **Trigger pattern**: the firings carry negative ontological acts
  (being-/striving-), NOT the lowest scores — cal-1010 («у меня ничего
  не получается», score 0.177, lowest) stayed silent. The layer is
  act-driven by design; score-only negativity without a negative act
  or earned drift does not fire.
- **Verdict**: F5's 0/40 silence was sample composition (neutral
  definitional questions), not a dead layer. No threshold change:
  the observed selectivity matches the design (drift branch gated by
  `negativeEvidenceEarned`, act branch by `ov<0`).

---

# Verb coverage — morphology gap + stem fallback (2026-09-17)

- **Measurement** (`scripts/lemma_verb_coverage.py`, exact replica of
  `morphologyDataFromParadigms` + `buildLemmaMap`): the morphology
  resource is nouns-only (20000 + 38 paradigms, zero verbs), so
  **0/24** `relationLexicon` verbs attest on the 206 corpus surfaces
  and term-level relation tagging was dead — live relation content
  came only from the `relTypeVerb` path fallback.
- **Fix** (`Semantic/Composition.hs`): stem fallback for tokens
  unknown to the lemma map (known nouns like «требование» stay
  concepts): common prefix >= 4 with a lexicon infinitive, token
  itself >= 5 chars («требует»/«требовать» share only «треб» —
  3sg -ет vs infinitive -ать). Short-prefix verbs («даёт»/«давать»)
  stay unreachable by design; that gap needs real verb paradigms.
- **Tests**: inflected-verb tagging, noun guard, short-prefix guard
  (unit 1584/1584).

---

# Verb paradigms v1 — morphology gap closed (data-only)

- **Data**: 24 `relationLexicon` infinitives added to
  `resources/morphology/paradigms.json` (`scripts/add_verb_paradigms.py`,
  188 forms, 20000→20024 lemmas). No code change — the loader unions
  every form automatically. One honest collision: «вести» (Inf)
  already maps to noun «весть» — form skipped, other вести forms kept.
- **Effect**: attested 0/24 → 11/24 on the 206 corpus surfaces;
  remaining 13 orphans are genuinely absent from corpus surfaces
  (not mapper gaps). Live: `acRelations` now carries true
  lemmatizations («ограничивать» from «ограничена»).
- **Residual**: short-prefix verbs («даёт» — now covered via давать
  forms), unknown-verb backstop stays (stem fallback); full verb
  morphology beyond the 24 remains open data work.

---

# Assembly pass v2 — 35 unique rated, bar not cleared (2026-09-17)

- **labels**: 35/35 unique human-v1 (75 harvested records inherit by
  key); rater confirmed all 21 new proposals
- **distribution**: coherent==2: 14/35 (40%), coherent>=1: 28/35,
  grounded==2: 24/35
- **parameters moved**: none

## Decisions

- **No selection influence**: 14/35 is not a coherent==2 majority,
  and 35 < 50-pair bar. Assemblies stay proposed-only.
- **Mechanical pre-gate adopted for the future influence switch**:
  all 7 coherent==0 assemblies carry empty relations — an assembly
  with no relations is ineligible for selection influence regardless
  of rating. (Recorded rule, not yet code: implement with the switch.)
- **Surface inconsistency noted**: stem-backstop relations keep raw
  inflections («соединяют» vs lemma «соединять»). Future: normalize
  backstop hits to infinitive via the verb table (verbs.json author
 itative form) or mark them unlemmatized in the candidate.

---

# Prototype normalization + fast green + harvest saturation (2026-09-17)

- **Root cause of the fast overlay failure**: `fieldDimensionPrototypes`
  hand-written in raw inflections, calibrated against the nouns-only
  map. After verb paradigms, predicate atoms lemmatize but prototypes
  do not → cosine 0. Fix: `buildSemanticSpace`/`buildPrototypes` take
  the lemma map and normalize prototypes by construction (5 call
  sites: Bootstrap, Finalize/State, Autonomous ×3); no hand-sync ever
  again. Overlap probe test updated to use a lemma map (honest regime).
- **Fast suite**: 1812/1812, 0 errors / 0 failures with `-M10G`
  (the earlier `-M6G` OOM was heap tightness, not a leak — no single
  new retention source found; helper cost per turn is bounded small).
- **Harvest-3**: 80 varied-form turns → 16 candidates, 0 new unique.
  Assembly space saturated at 35 unique under distinction/relation/
  practical/challenge forms × current graph. More turns of the same
  kind are pointless; reaching 50+ needs wider helper caps (more
  others/surfaces per turn) or pair-space expansion, not reruns.

---

# Debt-closure pass (2026-09-19, skeptical audit)

Skeptical audit 2026-09-19 confirmed real debt; this pass closes what
is closable without new human data. Still OPEN (needs humans/external):
M6-FELT/B2, production-trace corpus (Package 11 boxes), R5 labels
(15 unlabeled), F7 rater question, substrate file, publish decision
(386 unpushed), DATALOG-ROLE-001, SLICE-015, BD1, verb morphology
beyond 24 verbs.

## Closed in this pass

- **Report-vs-code**: the "assemblies stay proposed-only" decision
  below is SUPERSEDED — assembly endorsement is live in selection
  (math v5, `assemblyEndorsementBonus = 0.15`, R+L2 proxy prec .61 /
  rec 1.00, zero incoherent on 35 pairs). Selection influence remains
  withheld for utterances pending the 50+ bar; endorsement (nudging
  existing predicates) is the cleared middle ground.
- **Stem-backstop surfaces**: CLOSED — `relLemmaOf` normalizes
  stem-matched verbs to infinitive (unit-pinned); the "raw
  inflection" note below described the pre-fix state.
- **F2/F3/F4 extraction** (measured 2026-09-17): F2 fixed
  (`trimClauseTail`, live-verified); F4 fixed twice (verb-tail strip
  in candidates + honest abstain for GF-default-lexeme renders,
  live-verified); F3 needs no fix (rater-approved). GF map gap
  (55/120 topics without lexemes at the 2026-09-17 measurement; the
  literal corpus is now 172 topics — remeasure before using this as a
  current ratio) recorded as data backlog.
- **Slow heap**: full single-process run requires `-M12G`
  (172/172 green; smaller caps die at the tail with 0 failures).
- **Prototype/lemma skew**: `fieldDimensionPrototypes` normalized via
  lemma map at space build (was raw inflections vs lemmatized atoms).

---

# R5/move verdict + F7 closure (2026-09-19, human-v1)

- **Move verdict**: on all 3 fired moves (cal-1001/1013/1014,
  `mirror_state`) the rater says acceptable response but move
  undeserved (`move_deserved: 0`, 3/3). Direction: the move layer is
  too loose, not too strict. No constant changed on n=3 — threshold
  review triggered; tightening (`moveDriftMargin`, affirm-gate
  requirement) needs a wider pre-registered probe first.
- **F7 CLOSED**: rater confirms `hypothesize` — the implemented
  behavior («Гипотеза: …» + grounds, live since `96ddc2e`) IS the
  doctrine. The 5 disputed quantum labels (rel=2/acc=1 on
  `uncovered_generic`) stand as consistent: rater judges the
  construction, trace marks the provenance. Adjudication file stays
  as the record; no label flips.
- Remaining rater debt: 12/15 R5 `response_acceptable` pending.

---

# Morphological garbage fix (2026-09-19, human-rated 0/1 turns)

- **Instances**: «никакого» → «никакога», «получается» → «получаетси»
  (both in `MoveStateBoundary` genitive rendering via
  `heuristicGenitive`).
- **Root causes**: (a) no guard for already-inflected
  adjectives/pronouns — suffix rules re-inflected them; (b)
  `isVerbLikeTopic` missed reflexive suffixes (ся/сь/тся/ться).
- **Fix** (`Render/Dialogue.hs`): `hasAdjectivalEnding` passthrough
  (ого/его/ое/ее/ая/яя/ую/юю/ым/им/ом/ем/их/ых/ой/ей) + reflexive
  suffixes in `isVerbLikeTopic`. Live-verified: «никакого» stays,
  «получается» → «действия» (existing verb policy).
- **Tests**: 4 inflection guards in `DialogueSemanticSelection`
  (fast suite). Labels on the old garbage turns stand as historical
  ratings of recorded outputs.

---

# R5 labels complete 15/15 — move ⟺ unacceptable (2026-09-20)

- All 15 `r5_negative` turns labeled. Final tally: `move_deserved=1`
  on exactly the 4 unacceptable turns (1002, 1004, 1010, 1012),
  `move_deserved=0` on all 11 acceptable ones — including the 3 turns
  where a move actually fired.
- Rater doctrine, unanimous on 15/15: **a move should fire if and only
  if the turn degrades** (rescue semantics). Fired-on-good-turn moves
  are noise; silent-on-bad-turn misses are the real failures.
- Design consequence (open): the move gate should predict turn
  degradation (morphology garbage, empty compose, abstain surfaces)
  rather than user-state drift alone. Pre-registered probe required
  before touching `moveDriftMargin`.

---

# GF lexeme gap closure (2026-09-20, data)

- **Gap**: 55/120 covered topics without GF lexemes → `gf_default_lexeme`
  (`ponyatie_N`) renders («понятие и понятие», rated 0/0).
- **Fix**: `scripts/add_gf_lexemes.py` — 55 entries with full case forms
  (declension by ending + `возвышенное` adjective override), funIds match
  the TSV scheme; `scripts/add_gf_grammar_entries.py` — abstract + Rus +
  Eng concretes (reviewed glosses); PGF recompiled (`compile_gf_grammar.sh`).
- **Verified**: 3811 map entries, 0 dups, 0 covered topics unmapped;
  fresh grammar contains new funs; live turn drops default lexeme,
  morphology correct on fallbacks.
- **Residual (next bounded task)**: RMP/frame intent divergence — for
  «чем вкус отличается от гармония?» RMP says DistinctionQ (family
  CMDistinguish) but frame intent is null, so the turn grounds instead
  of distinguishing. Suspect: `SemanticIntent` classifier features vs
  `PropositionType` path disagree; `extractContentNouns` POS dict
  lacks вкус/гармония (guess-fallback covers, unverified live).
  Needs runtime debugging of `classifyIntent` inputs, not more statics.

---

# Gerund-suffix root cause + live distinction (2026-09-20)

- **Debug path**: RMP/frame divergence on чем-distinction traced
  through 6 layers (claimAst correct, surface wrong) to
  `sfHasTwoConcepts = False` with complexity 0.2 — proven by
  temporary dump tests (since converted to regression pins).
- **Root cause**: single-letter `а`/`я` in `gerundSuffixes`
  classified every OOV -а/-я noun as Gerund («гармония»).
  Only one content noun survived → no DistinctionQ route.
- **Fix**: drop `а`/`я` (past forms в/вши/ши stay); present gerunds
  fall through to Noun — the safe direction for counting.
- **Live**: «чем вкус отличается от гармония?» now renders both
  corpus predicates composed under «Гипотеза:» (CMDistinguish,
  covered_exact) instead of the ground template.

---

# Assembly bar superseded (2026-09-20, operator decision)

- The "coherent==2 majority on 50+ pairs" bar is retired, not cleared:
  coherent==2 held at 33–40% across three harvest rounds (6/14 →
  14/35 → 15/46) — a property of the distribution, not of sample
  size. More turns cannot move it.
- Influence already exists in two bounded, gated, traced forms:
  selection endorsement (+0.15, math v5) and hypothesis fragments
  in the surface. Withholding further influence is therefore not
  "no influence", it is scope discipline.
- First-class assembly claims (leading content, not appendage) stay
  closed under a new criterion: coherent==2 majority among len-1
  direct assemblies (currently 11/26 = 42%; len2+ only 4/20).
  Notably, multi-hop assemblies rate systematically worse — evidence
  for the no-cap decision (rating, not structure, judges), and against
  promoting them.

---

# structScore vs Jaccard holdout eval (2026-09-20, scripted)

- **Tool**: `scripts/eval_structscore.py` (reusable). Lexicon sets parsed
  from `Composition.hs`, lemma map from paradigms+exceptions (same
  replica as `lemma_verb_coverage.py`); the port self-checks against
  the Haskell unit vectors (identity 1.0, converse j=1.0/s<0.5, neg
  cap) before evaluating. Candidates extracted from `Content.hs`
  entry blocks (asserted 120 topics at the 2026-09-20 measurement; the
  literal corpus is now 172 — the eval is a historical snapshot). Results:
  `data/calibration_corpus/structscore_eval.json`.
- **Eval set**: 40 records with predicate_relevant (corpus ⋈ rated by
  id). Used-candidate mapping by response containment (covered_exact
  renders the predicate near-verbatim; symmetric overlap collapses
  under surface length — first run mapped WEAK everywhere, fixed).
- **Headline**: on 11 mapped covered rel=2 records, struct top-1
  10/11 (0.909) vs jaccard 4/11 (0.364), delta +0.545 (gate +0.05
  passed numerically). Paired discordants 7 vs 1, McNemar exact
  two-sided p = 0.070 — suggestive, NOT conclusive at n=11.
- **Exclusions (4, explicit)**: cal-0121–0124 «любовь» render a
  non-corpus predicate («глубокое чувство привязанности») yet rated
  rel=2 — F7-class (rater judges construction, trace marks
  provenance). Unmappable by construction; excluded, not failed.
- **Honest decomposition**: «что такое X?» queries are head-only —
  rel/mod channels empty — so structScore degenerates to head-tie +
  candidate-order prior. The win is the ORDER PRIOR (production pick
  == first-listed 10/11), not role structure. Sensitivity check
  confirms: delta identical (+0.545) under all four weight variants
  (default, head-heavy, flat, uniform) — coordinate ascent has a flat
  objective here and stays untouched.
- **Genuine struct loss**: cal-0481 «абсурд» (verbatim #1, production
  Field-pick right): struct ties on head and falls back to order #0,
  jaccard wins via length bias. Neither scorer reasons here; the
  production Field-conditioned pick does.
- **Parameters moved**: none. No cutover (n=11, p=0.07), no math bump.
- **Pre-registered next**: the corpus cannot test structural
  discrimination until relation-bearing queries («контрпример к X»,
  «чем X отличается от Y») carry per-candidate relevance labels.
  Holdout bar for cutover: 40+ mapped covered records with
  relation-bearing queries, McNemar p < 0.05 AND delta >= +0.05.

---

# Batch2 holdout eval — 45 relation-bearing pre-ratings (2026-09-21)

- **Batch**: 45 records (15 each distinction/relation/challenge),
  topics alphabet-spread; responses captured live (`rated_batch2.json`,
  merged into `rated_responses.json` → 115, backup `.bak-batch1`);
  labels ingested to `corpus.jsonl` (85 labeled total).
- **Provenance (honest)**: labels are `assistant-pre` — assistant
  proposed per-record (rel 20×2 / 11×1 / 14×0, acc=0 on 8: 4 junk
  tails + 4 contentless hold-stubs), human agreed the FRAME, not
  each record. Train-eligibility NOT claimed; `train_eligible` stays
  40 pending per-record human confirmation.
- **Result** (`scripts/eval_structscore.py`, containment mapping):
  35 covered rel=2, of which 28 mapped (7 F7-class exclusions: 4
  любовь + добро/желание×2 + желание-relation — non-corpus
  predicates at rel=2, unmappable by construction).
  struct top-1 21/28 (0.750) vs jaccard 15/28 (0.536),
  delta +0.214; discordants 10 vs 4, McNemar p = 0.180.
- **Bar status**: NOT cleared (need 40+ mapped AND p<0.05 AND
  delta>=+0.05: have 28, p=0.18). Delta diluted +0.545→+0.214 with
  n — the order-prior effect washing out as relation-bearing
  queries enter, exactly as the head-only decomposition predicted.
- **New genuine struct losses** (production Field-pick beats both
  scorers): действительность×2 (used#1, struct falls to order #0),
  трагедия×2 (used#1 at ov=0.5, BOTH scorers miss — paraphrase
  zone neither ranks first), смысл-relation/challenge (used#1,
  struct order-fallback wrong). Pattern: whenever the approved pick
  is NOT first-listed, struct's order prior fails and Field
  conditioning (scorePred+prototypes) is the only thing that works.
- **Sensitivity**: delta identical under all four weight variants
  again — coordinate ascent still pointless; weights untouched.
- **Parameters moved**: none. No cutover, no math bump.

---

# Batch3 holdout eval — bar NOT cleared, negative result (2026-09-21)

- **Batch**: 45 records on fresh topics (24 already-labeled topics
  excluded), same 3 strata; `rated_batch3.json` merged
  (`rated_responses` 160, corpus 130 labeled, all `assistant-pre`).
- **Result**: 55 covered rel=2, 47 mapped (8 F7-class exclusions).
  struct top-1 26/47 (0.553) vs jaccard 28/47 (0.596),
  delta −0.043 (gate +0.05); discordants 10 vs 12, McNemar p = 0.832.
- **Verdict**: the pre-registered bar FAILS on all three prongs
  (n=47 ✓ met, but delta<+0.05 and p=0.83). The dilution across
  rounds (+0.545 → +0.214 → −0.043) confirms the diagnosis: on this
  distribution the comparison is order-prior vs length-bias, and
  neither scorer reasons — the production Field-conditioned pick
  (scorePred + prototypes) is the only component that discriminates.
- **Consequence**: NO cutover of `structScore` into selection.
  The module stays SHADOW-ONLY. Its proven value is elsewhere
  (unit-pinned structural discrimination: converse test) and it
  remains the instrument for future relation-bearing-holdout work,
  not a replacement for scorePred.
- **Sensitivity**: delta flat across weight variants (flat-rel-mod
  +0.021, still below gate) — weights stay hand-set, no math bump.
- **Parameters moved**: none.

---

# Operator decision — pre-ratings count as human-confirmed (2026-09-21)

- **Decision**: the 90 batch2/batch3 `assistant-pre` labels count as
  human-confirmed. `train_eligible` 40 → 125 (35 v1-undisputed + 90).
  Labels keep `rater: assistant-pre` + `humanConfirmed: true`
  (provenance honest: proposed per-record inline, agreed per batch).
- **Deviation recorded**: CALIBRATION_CORPUS.md demands double-rating
  20% + kappa for train-eligibility. This decision overrides it by
  operator authority (precedent: assembly-bar supersession): every
  record was presented inline WITH its proposed label and the batch
  was accepted as a whole — confirmation-by-review, not
  independent double-rating. Dispute class stays excluded (5
  adjudicated v1); F7-unmappable records remain unusable for
  predicate-fit regardless of eligibility flag.
- **Consequence**: StructWeights coordinate ascent is now DATA-OPEN
  (125 eligible). Not started — and the holdout verdict (delta
  −0.043, weights flat across variants) says training would fit
  noise: the objective, not the data, is the blocker. Eligibility
  unblocks future work; it does not recommend it.

---

# Grounds-junk filter — engagement-gated assemblies (2026-09-21)

- **Defect** (from batch2/3 acc=0 turns): hypothesis tails citing
  alien grounds — «программирование требует знания языков…»,
  «весна это время года», «нарратив о себе…», «с речью…».
  Mechanism: mediated assemblies pair the query surface with a
  third topic reached via generic glue atoms («знание», «время»);
  R+L2 gate passes (non-empty rels, path ≤2) because the path is
  real but vacuous. A df-based glue filter was measured and
  REJECTED: junk and clean bridges share the same df band
  (знание:4 == бытие:4 == время:4) — no separating threshold.
- **Fix** (`Semantic/Assembly.hs`, `Route/Render.hs`): `utterableAssembly`
  takes the frame's engaged topics (`activationTopics`, already
  computed upstream) and restricts other-topics to that set
  (case/space-insensitive, `normalizeTopic`-identical, inlined to
  avoid an import cycle). Selection-endorsement path untouched.
- **Verification**: unit 1603/1603 (2 new tests: third-topic
  suppression, normalization tolerance); fast 1817/1817;
  integration 46/46; live: 4 junk-class turns re-render without
  alien grounds, leads intact; engaged-pair path still utterable
  (unit-pinned).
- **Parameters moved**: none (filter, not weights).

---

# EmptyHold rescue + verb-focus root cause (2026-09-21)

- **Defect** (batch2/3 acc=0): contentless holds («Держу X как
  опору…») on covered topics — no plan, no claim, nothing emitted,
  nothing selected.
- **Discriminator** (trace-verified): stubs carry NO plan
  (`respPlan=null`); honest abstains always carry one (fallback
  reason). The detector requires plan absence, so abstains are
  excluded by construction; uncovered topics excluded (silence may
  be honesty).
- **Root cause found by instrumented trace** (temporary, removed):
  `tiBestTopic` is focus-scored with a length bonus that elects a
  verb on relation forms (`best="связано"` beats «добро»/«зло»);
  frame activation for these frames is empty (`_ -> []` catch-all).
  Coverage is therefore checked over bestTopic + frame activation
  topics + covered topics named in the rendered surface
  (`mentionedCoveredTopics`, unit-pinned; new `repActivationTopics`
  plan field threads plan-time topics into artifacts). The verb-focus
  election itself is extractor debt (F2/F3/F4 family) — rescue scope
  ends at catching its render consequence.
- **Verification**: unit 1605/1605 (truth table + mention tests);
  fast 1817/1817; live 5/5 (both stub classes repaired, abstain and
  clean turns silent, tautology keeps priority).
- **Parameters moved**: none (filter, not weights).

---

# Verb-focus probe — pre-registration (2026-09-22, no behavior change)

- **Instrumentation landed**: `trcBestTopic` on every replay trace
  (Prepare-stage best topic; routing still reads dialogue focus).
  Live proof: «как добро связано с зло?» records
  `trcBestTopic=связано` against `trcDialogueFocus=добро` — the
  focus length bonus electing a verb is now machine-observable
  instead of inferred.
- **Probe rule (pre-registered, not yet run)**: sample N≥45 live
  relation-bearing turns, read `trcBestTopic` per turn; if the
  uncovered-verb rate (bestTopic ∉ covered topics while dialogue
  focus ∈ covered) exceeds 20%, retune `focusScore` length bonus
  (cap or verb guard) behind a math-version bump, then re-verify
  routing pins + rescue behavior. If ≤20%, the extractor debt is
  downgraded to cosmetic.
- **Why not now**: retuning focus scoring shifts routing globally;
  per the move-v4 precedent it needs measured trigger + full suite
  re-verification, not a drive-by constant edit.

---

# Verb-focus probe — executed, debt downgraded (2026-09-22)

- **Run**: 50 fresh distinction/relation turns (shared state, live
  runtime with substrate), `trcBestTopic` vs `trcDialogueFocus`
  read from replay traces.
- **Result**: uncovered-verb bestTopic with covered focus on 6/50
  (12%): 5× «связано», 1× «отличается». Bar was >20% for a
  focusScore retune.
- **Verdict**: below bar — extractor debt downgraded to COSMETIC.
  No constant touched, no math bump. EmptyHold already catches the
  render consequence (covered-topic holds repaired regardless of
  which verb the focus elected).

---

# Substrate selection re-baseline — base transfers intact (2026-09-22)

- **Design**: three-point comparison on the stratified sample —
  OLD baseline (old code, empty substrate, 40 turns) vs NEW-CODE
  empty-substrate (60 turns) vs NEW-CODE with substrate (60 turns).
  Reports: `baseline_report.json`, `baseline_report_nosubstrate.json`,
  `baseline_report_substrate.json` (old file untouched).
- **Result**: every improvement since the old baseline
  (distinction 3→5 exact, relation 3→4, practical 0→5 exact) comes
  from CODE fixes (F2/F4-class) — new-code empty ≡ new-code
  substrate on ALL 12 strata, zero content-source difference.
- **Verdict**: substrate does not shift top-level content routing on
  this sample (it activates underneath on a minority of turns —
  19/60 with nonzero edges used, hops ≤3 — multi-hop traversal
  without top-1 displacement).
  The 130-label calibration base transfers intact; no re-rating
  required by the regime change.

---

# Dictionary expansion batch-1 — 12 live-harvested topics (2026-09-24)

- **Trigger**: live coverage only ~11% covered_exact; users ask
  outside the 120-topic dictionary (дождь, космос, боль, тишина…).
- **Method**: focus nouns harvested from 175 live turns (verbs and
  meta-words excluded by rule); 2 predicates each in prop/rel style,
  human-approved verbatim (all 12 accepted).
- **Landing**: `definitionCorpus` 120→132 (`Content.hs`); GF lexemes:
  7 already present, 5 appended (`add_gf_lexemes.py` + OVERRIDES
  for hush-final дождь; pre-existing `dozhd_N` instrumental fixed
  дождем→дождём); grammar abstract/Rus/Eng extended
  (`add_gf_grammar_entries.py` made idempotent: skips generated
  funIds, MARK2); PGF recompiled.
- **Verification**: lib clean, unit 1605/1605, fast 1817/1817 (pins
  held despite 12 new graph nodes). Live spots: тишина/боль
  verbatim; дождь preferred a better overlay predicate
  («атмосферные осадки») over the new one — selection working;
  суть/сущность holds honestly (no pair content, as before).
- **Parameters moved**: none (data only).

---

# Bare-noun routing — pre-registration (2026-09-24)

- **Finding**: single-noun inputs with covered topics («свобода»,
  «любовь», «дождь») classify as unstructured → GF-shim route →
  semantic pipeline never engaged (diags=0). ~15–20 live turns affected.
- **Rule (locked before implementation)**: single-token input (after
  punct-strip) whose normalized form is a covered topic →
  ConceptKnowledgeQ (new detector before detectConceptKnowledge;
  greetings/identity/operational keep priority above it) AND
  single-token ConceptKnowledgeQ → IntentDefine (canonicalTopic);
  multi-word inputs fall through unchanged on both edits.
- **Bar**: affected live turns render covered_exact; unit + fast +
  core green with zero new failures; spot checks on 5 bare nouns.
- **Out of scope**: inflected bare nouns («свободе») — lemma-less
  detector covers nominative only; inflection is the separate 5%
  upgrade. Multi-word behavior must be byte-identical (gated on
  single-token).

---

# Bare-noun routing — landed, bar cleared (2026-09-25)

- **Change**: single-token covered nouns route to definitional
  handling — new `detectBareNounDefinition` detector (before
  ConceptKnowledge, greetings/identity/operational keep priority),
  `TagConceptKnowledge` route hint at 0.95 (survives admission vs
  contemplative 0.88 max), single-token ConceptKnowledgeQ →
  IntentDefine in `semanticIntentForRender` (multi-word fallthrough
  byte-identical). Nominative only; inflected forms stay old path.
- **Tracer find that shaped it**: frame-hint admission overrode the
  detector (`TagContemplativeTopic` from single-or-short-input rule);
  instruments removed after use, none remain in src/.
- **Precision fix same landing**: EmptyHold requires the named topic
  to intersect best/engaged/focus (greeting false positive via
  incidental «время» closed; stubs still fire).
- **Verification**: unit 1608 (3 old pins updated to the intended
  behavior + new detector/intent/normalization tests), fast 1817,
  core 1190 — zero new failures. Live: свобода/любовь/дождь/тишина
  render covered_exact; привет silent; «что такое свобода?»
  byte-identical.
- **Parameters moved**: none (routing, not weights).

---

# Short-input definitional routing — pre-registration (2026-09-25)

- **Finding**: multi-word shorts with covered head nouns («смысл
  жизни», «свобода как выбор») never reach selection (diags=0);
  only bare nouns were fixed. ~60 of 67 remaining misses.
- **Rule (locked)**: at the END of `classifyFromFeatures` (after
  topic-specific, before honest fallback): input ≤3 tokens AND
  first content noun covered → `IntentDefine` (that noun). Fires
  only where all four levels fell through — greetings, challenges,
  comparisons, questions-with-markers keep priority by construction.
  Nominative-leaning (no new morph threading; inflected heads stay
  old path).
- **Bar**: remiss covered_exact count grows with zero regressions
  (input-to-input diff); unit + fast + core green, zero new
  failures; live spots on 5 shorts.
- **Out of scope**: inflected heads, >3 tokens, anything the upper
  levels claim.

---

# Short-input definitional routing — landed, bar cleared (2026-09-25)

- **Change** (pre-registered): end-of-chain rule in
  `classifyFromFeatures` — ≤3 tokens + first content noun covered
  → `IntentDefine`. Greetings/challenges/comparisons keep priority
  (all above it); multi-word behavior untouched.
- **Verification**: unit 1610 (+2 tests), fast 1817, zero new
  failures. Live spots all correct (incl. uncovered «огонь или
  воздух?» falling through by design). Remiss re-run: 11 fixed,
  0 regressed (none→covered_exact on short covered heads).
- **Parameters moved**: none (routing, not weights).

---

# Plan-topic canonicalization — pre-registration (2026-09-25, phase 2)

- **Finding**: 15 TopicNotCovered plans carry whole clauses as
  topics («в чём смысл моей жизни», «ты молчишь») — map membership
  fails trivially. `normalizeIntentTopics` canonicalizes only
  Define/Distinguish; Ground/Learn/Help/Purpose/WorldCause/Deepen
  pass raw surfaces through.
- **Rule (locked)**: extend the existing canonicalization to the six
  topic-carrying intents (total function; unknown surfaces pass
  through unchanged, so nominative inputs are byte-identical).
- **Bar**: TopicNotCovered class shrinks on remiss re-run; unit +
  fast + core green, zero new failures; spot checks.
- **Out of scope**: ChallengeFrame `исходный тезис` placeholder
  (separate target-extraction debt, recorded).

---

# Plan-topic retry — phase-2 REDESIGN (2026-09-25, supersedes reverted normalization)

- **Why redesigned**: extending `normalizeIntentTopics` broke the F2
  span doctrine («осознанность выбора» → «выбор» when the head is
  unknown). Reverted same-day. Clause-topics are a plan-level
  problem, fixed at plan level.
- **Rule (locked)**: in `buildGroundedPlan`, single-topic
  TopicNotCovered retries with the first covered token of the
  surface — unless negated (не/ни/нет/без/нельзя) or no covered
  token exists (then today's fallback, byte-identical).
  Multi-topic (distinction) plans untouched.
- **Bar**: TopicNotCovered class shrinks on remiss; unit + fast +
  core green, zero new failures; live spots.

---

# Plan-topic retry — landed, bar cleared (2026-09-25)

- **Change** (redesigned pre-reg after reverting a normalization
  that broke F2 span doctrine): single-topic TopicNotCovered
  retries with the first covered token («в чём смысл моей жизни»
  → «смысл»); negated/exhausted surfaces and multi-topic plans
  keep today's fallback byte-identical.
- **Verification**: unit 1612 (+refine tests), fast 1817, core
  1190 — zero new failures. Live spots exact (incl. preserved
  abstains on negation/uncovered). Remiss: 5 fixed, 0 regressed.
- **Parameters moved**: none (routing, not weights).

---

# State-dependent misses — dissolved, no suppressor bug (2026-09-25)

- **Question**: 32 live-miss/fresh-hit pairs — does dialogue history
  suppress selection?
- **Field deltas**: learning_need→degraded in 16/32; rest are harness
  artifacts (fields absent in old captures), code-fix effects
  (family flips from bare-noun routing), or legitimate guard blocks.
- **Need-tracker audit** (`Learning/Need.hs`): windowed (10 turns),
  unlatches on expiry — a miss-density tracker working as designed,
  not a latch bug. Its surface appends honestly; it never replaces
  rendered content.
- **In-session verification** (6-turn session with history):
  свобода/смысл жизни/зачем нужна свобода all render covered_exact
  AFTER vague turns. Phases 1–2 fire with history present.
- **Verdict**: no fix. The gap was old code + honest tracking.
  (Side observation, pre-existing minor bug: hypothesis
  back-reference points at the previous turn's question.)

---

# Next-move back-reference guard — pre-registration (2026-09-25)

- **Finding**: «Следующий ход: вернуться к открытому вопросу: X»
  cites the dialogue thread's active question unconditionally —
  twice observed pointing at the PREVIOUS turn's unrelated question
  (live-0201 смелость→любовь; hist «о чём ты молчишь?»→смысл).
- **Rule (locked)**: cite the active question only if the current
  plan topic occurs in it (normalized substring); else fall back to
  the goal default («проверить тезис на контрпример»). Turns that
  continue their own question keep the reference byte-identical.
- **Bar**: unit tests (match/mismatch/empty) + live spots on both
  cases; unit + fast green, zero new failures.

---

# Next-move back-reference guard — landed (2026-09-25)

- **Defect**: «Следующий ход: вернуться к открытому вопросу: X»
  cited the thread's stale question (live-0201 смелость→любовь).
- **Fix** (pre-registered): cite only when the plan topic occurs in
  the question (`topicMentioned`, whole-token); else goal default.
- **Verification**: unit 1613 (+guard tests), fast 1817 green; live:
  смелость→любовь now defaults, same-topic paths untouched by
  construction (unit-pinned fallthrough).
- **Parameters moved**: none.

---

# Lexicon pipeline doctrine — learned the hard way (2026-09-25)

- `export_lexicon.py` OWNS all derived artifacts (funmap, .gf,
  Agda, snapshot): SQL/paradigms → everything else. Hand-appends
  via `add_gf_lexemes.py` ROT on the next export (proven: wiped 5
  rows + reverted a fix mid-session through a concurrent write).
- Rules going forward: new lexemes go into
  `spec/sql/lexicon/seed_ru_curated.sql` (validated by load);
  paradigms additions are surgical text inserts (never json
  round-trip — formatting churn); Eng concrete stays hand-appended
  (export does not generate it; dedupe against senior glosses);
  NEVER run export concurrently with hand edits.
- Witness rule (bitten 2026-09-27, F0): any regen touching
  `spec/*.agda` MUST end with `qxfx0-main --write-agda-witness`
  (verify-then-record) — otherwise the recorded witness goes stale
  and every strict bootstrap fails closed at the health gate.
- Collateral: `суть` paradigm added (20025 lemmas) — unblocked
  суть/сущность distinction end to end (no rescue). `сущность` GF
  lexeme added via SQL (pre-existing gap, not new).
- Verified: unit 1613, fast 1817 green; live суть/сущность renders
  both predicates, no rescue.

---

# Learning-need surface suppression — pre-registration (2026-09-25)

- **Measurement**: learning_need fires on 93/202 live turns incl. 18
  covered_exact — content-source split identical with/without need,
  so the surface taxes good turns without signaling about them.
- **Rule (locked)**: a RecoveryLearningNeed repair surface renders
  only when the turn carries no content (empty plan claims AND empty
  emitted predicates). Trace (cause/strategy/evidence) unchanged —
  the need stays machine-visible. Abstains/holds keep the surface;
  content turns drop it. Doctrine: repair content ⟺ degraded turn.
- **Bar**: unit + fast + core green, zero new failures; live: 3
  content+need turns lose the tail (trace keeps cause), 3
  abstain+need turns keep it.

---

# Learning-need surface suppression — landed, bar cleared (2026-09-25)

- **Measurement**: learning_need fired on 93/202 live turns with an
  identical content-source split as non-need turns — pure verbosity
  tax on good turns.
- **Fix** (pre-registered): RecoveryLearningNeed repair surfaces
  render only with no content (empty plan claims AND empty emitted);
  trace cause/strategy/evidence untouched. Abstains/holds keep it.
- **Verification**: unit 1613, fast 1817, core 1190 green, zero new
  failures. Live 6-turn sessions: content+need drops the tail with
  cause in trace (2 turns); abstain+need keeps it (1 turn).
- **Parameters moved**: none (render gate, not weights/thresholds —
  the 0.6 activation threshold itself untouched).

---

# Challenge placeholder — pre-registration (2026-09-25)

- **Finding**: `extractTarget` bakes «исходный тезис» into
  ChallengeFrame when nothing matches; the placeholder then travels
  as a fake plan topic (TopicNotCovered on «исходный тезис»).
- **Rule (locked)**: return empty on no-match; the render guard
  (`Dialogue.hs:2160`, empty → «исходный тезис» for DISPLAY only)
  already covers presentation. No other callers exist.
- **Bar**: unit tests (matched/pattern/empty) + unit/fast green,
  zero new failures; live spot (Мораль-challenge abstains without
  fake topic in trace).

---

# Challenge placeholder removed — landed (2026-09-25)

- **Defect**: `extractTarget` baked «исходный тезис» into
  ChallengeFrame; the placeholder traveled as a fake plan topic.
- **Fix** (pre-registered): empty on no-match; the display guard
  (`Dialogue.hs`, empty → «исходный тезис») already covers
  presentation. Single caller, no other consumers.
- **Verification**: unit 1615 (+target tests), fast 1817 green.
  Live Мораль-challenge: clean clarify request, plan
  NoTopicProvided (no fake topic in trace).
- **Parameters moved**: none.

---

# Lemma-aware plan retry — pre-registration (2026-09-25, micro)

- **Finding**: 11 live turns carry inflected covered forms
  (смысле→смысл, грани→грань, свободе→свобода); raw-token retry
  misses them. Election untouched (wider blast radius, separate
  project if ever).
- **Rule (locked)**: `refineUncoveredTopic` takes the selector lemma
  map and lemmatizes surface tokens before the covered check.
  Nominative behavior byte-identical (lemma of nominative is
  itself modulo map gaps).
- **Bar**: unit tests (inflected/negated/empty) + unit/fast/core
  green, zero new failures; live spots on 3 inflected inputs.

---

# Lemma-aware plan retry — landed (2026-09-26, micro)

- **Change** (pre-registered): `refineUncoveredTopic` lemmatizes
  surface tokens through the selector map (смысле→смысл); nominative
  behavior identical. Election untouched.
- **Verification**: unit 1613 (+inflected test), fast 1817 green.
  Live: «в чём смысл моей жизни?» and «зачем жизни суть?» resolve
  to covered topics with content; plan-less shapes stay out of
  scope by design (verified: no plan exists to retry).
- **Parameters moved**: none.

---

# None-class decomposition — closed as correct (2026-09-26)

- **Method**: all remiss turns with `trcContentSource=None`
  (plan never built), classified by input.
- **Result (32)**: ~28 legitimately contentless (meta/self-talk/
  vague: greetings, «что ты хочешь?», «как ты думаешь?», «научи
  меня…» — no content question asked). 4 borderline
  («где твои грани?», «в чём твоя суть?», sense-forms) where a
  definitional answer is plausible but each needs human judgment
  about the question's sense.
- **Decision**: no rule. Forcing content onto meta questions would
  be a regression disguised as a fix (answers literally, misses
  the point). The 4 borderline stay human-discretion cases.

---

# Generative trigger broadening — pre-registration (2026-09-26, в1)

- **Finding**: generative path fires only on imperative requests
  («придумай/скажи X»); hypothesis-seeking forms («а что если»,
  «представь, что», «пофантазируй о») fall through. Output stays
  canned (MoveGenerativeThought) in both cases — this step changes
  ROUTING only, not generation.
- **Rule (locked)**: extend `isGenerativeRequestText` with
  hypothesis-seeking markers; the render path is untouched.
- **Bar**: unit tests (new forms fire, old forms unaffected,
  non-requests stay out) + unit/fast green; live spots (2 new
  forms route generative, 1 old form byte-identical).

---

# Generative trigger broadening — landed narrowed (2026-09-26, в1)

- **Change** (pre-registered): hypothesis-seeking imperatives
  (представь/пофантазируй/вообрази) route generative; render path
  untouched.
- **Caught live by the flagship pin**: first version also took
  «а что если»/«а если», hijacking M6 turn 12 (a counterfactual
  challenge) into GoalHypothesize — fast went red on
  FeltGate5NonFallback. Narrowed same-day with a regression test
  on the M6 input. Lesson re-learned: broadened triggers collide
  with challenge markers; the pin exists for exactly this.
- **Verification**: unit 1616, fast 1817 green; live spots route
  with content, old imperative unchanged.

---

# Dictionary content batch-3 — 4 live-approved topics (2026-09-26)

- усталость / вдохновение / ностальгия / гнев: props verbatim
  from approved live turns, rels human-reviewed. Sources only
  (Content.hs + SQL seed); export regenerated all derived
  artifacts; Eng hand-deduped vs senior glosses.
- Verified: unit 1616, fast 1817 green; live spots render content.

---

# Speculative regime v1 — pre-registration (2026-09-26)

- **Motivation**: 69% template inventory; researcher asks for
  emergence room with the right to be wrong (epistemic only —
  safety gates explicitly out of scope and pinned by tests).
- **Trigger** (per-turn, pure, no state): markers
  «давай порассуждаем», «пофантазируй всерьёз», «порассуждай»,
  «мысли вслух», «а если серьёзно». Session latch deferred.
- **Effect A** (abstain→hypothesis): fallback plans (TopicNotCovered
  / empty) build hypothesis content via composition instead of the
  abstain surface. ClaimHypothetical framing MANDATORY — the line
  between wrong and false-authority.
- **Effect B** (assembly): loosen utterability one notch under the
  flag. Hard constraint: the 7 junk-tail instances must stay
  silent (regression set). Exact knob at implementation.
- **Deferred to v2**: commitment persistence (needs 9th CTS
  constructor + defense wiring); safety untouched by design.
- **Trace**: `trcSpeculative :: Bool` every turn.
- **Bar**: suites green zero new failures; live probe N≥10 rated
  (coherent majority, zero false-authority); crisis+marker combo
  test pins Protocol B supremacy; control inputs byte-identical.

---

# Crisis surface eaten by quality gate — SAFETY FIX (2026-09-26)

- **Finding (live, pre-existing, unrelated to speculative work)**:
  pure crisis input renders the recovery fallback WITHOUT resources.
  Trace: ProtocolB true + FromRecovery. Mechanism proven by replica:
  crisis surface is 77 tokens with zero topic overlap, so
  `checkTopicRelevanceBlock` fires on EVERY crisis turn (any
  non-empty topic).
- **Fix (no bar wait — safety)**: crisis turns bypass
  `finalizeOutputWithTopic` entirely and render `preSafetySurface`
  (which IS the crisis surface on that branch). Principled: the
  crisis text is static curated content (cause ignored by the
  renderer), so runtime quality shaping is inapplicable by design —
  not a hole. Structural safety likewise inapplicable to static text.
- **Verification required**: live crisis turn renders 112 +
  helpline (direct proof); CrisisGuard suite green; unit/fast/core
  green, zero new failures.

---

# Crisis bypass verified live (2026-09-26)

- Pure crisis and crisis+speculative-marker turns both render the
  full bounded surface (112 + helpline). Protocol B supremacy over
  speculative mode proven live (pre-reg bar item closed).
- unit 1617, fast 1817 green, zero new failures.

---

# Speculative regime v1 — landed, probe passed (2026-09-27)

- **Trigger** (`isSpeculativeRequestText`): researcher markers,
  per-turn, stateless. Crisis markers excluded by construction
  (unit-pinned); Protocol B supremacy proven live.
- **Effect A**: fallback AND empty plans retry once through the
  generative path (hypothesis-marked); unknown-intent turns with a
  good generative plan are no longer silenced at the viaSemantic
  gate (the hold-behind-plan bug, found by probe).
- **Effect B deferred to v1.1**: any gate loosening is untestable
  on current fixtures or risks the 7 junk instances; precision
  preserved over recall.
- **Trace**: `trcSpeculative` every turn (JSON backward-compat).
- **Probe N=10**: all render content (theses/hypotheses with
  grounds); coherent per operator endorsement; zero
  false-authority (corpus-backed or marked).
- **Verification**: unit 1618, fast 1817, core 1190 green, zero new
  failures. No debug traces remain in src/.
- **Parameters moved**: none. Commitment persistence stays v2.

---

# Generative composition v2 — pre-registration (2026-09-27)

- **Investigation outcome**: runtime-composed novelty lives ONLY in
  the assembly engine (graph paths → novel bridge constructions);
  hypothesis/overlay content is curated (human promotion), and
  MoveGenerativeThought is canned fixed text. Graph coverage BOUNDS
  composability: truly-unknown topics have no foothold (no atoms,
  no paths) — no honest mechanism composes ex nihilo. LLM-backed
  generation is blocked (no key); curated overlays need review
  labor, not code.
- **Rule (locked)**: on generative turns, attempt a topic-anchored
  mediated assembly (`generateTopicThought`: input-term concepts ×
  engaged winners, graph-mediated, top-1) and render it as the
  generative thought, hypothesis-marked. Uncovered-without-foothold
  topics keep today's behavior (abstain/generic/template) — the
  boundary is explicit, not a failure.
- **Bar**: unit tests (assembly on fixtures incl. no-foothold
  Nothing); unit/fast/core green zero new failures; live probe N≥8
  generative turns rated (coherent majority on composed thoughts,
  zero false-authority); control (non-generative) inputs
  byte-identical.
- **Out of scope**: LLM generation, overlay curation, persistence.

---

# Generative composition v2 — landed, probe passed (2026-09-27)

- **Rule (locked in pre-reg above)**: on generative turns, attempt a
  topic-anchored mediated assembly and render it as the generative
  thought, hypothesis-marked. Uncovered-without-foothold topics keep
  today's behavior.
- **Implementation**: `generateTopicThought` (`Semantic/Assembly.hs`,
  pure/total/deterministic) — same-topic distinct corpus surfaces,
  then lemmatized input-concept extension (head-only synthetic other
  side); R+L2 gate (non-empty rels, validated path ≤2); top-1 by
  (informative-bridge, path length, −score, bridge). Wired in
  `Route/Render.hs`, generative-only by construction
  (`generativeRequest` gate — non-generative bytes untouched):
  fires only when the cross-topic `assemblyHypothesis` stays silent,
  renders through the identical «Гипотеза:» suffix; trace outcome
  `uttered_generative` (list shape stable, `none` otherwise).
- **Two probe-driven fixes**: (1) pairs come from the selector's
  corpus surfaces for the query topic — frame diagnostics are empty
  (nsel=0) on single-topic turns and the plan carries a single
  thesis ref, so both give no pair; (2) informative-bridge ranking —
  the skeleton otherwise returns the vacuous query-head bridge
  («свобода-связь»).
- **Probe N=9**: 3 fired (свобода свобода→выбор, смерть бытие→смерть,
  смысл жизнь→смысл) — all hypothesis-marked with cited grounds;
  6 silent (single-surface topics / no validated path) — the
  explicit boundary, today's behavior kept. Operator-confirmed:
  3/3 coherent, zero false-authority. Known warts (realizer
  roughness, not authority): rel duplication, case/valency slips
  («контрастирует с смерть», «противопоставлять со смертью»).
- **Controls**: 3 non-generative inputs unchanged by construction
  (gate + identical `none` path); crisis supremacy proven live
  (112 + helpline render on «не хочу жить»).
- **Verification**: unit 1625 (+7 new tests: same-topic, silence,
  input-term, substrate-block, no-foothold, determinism, bridge
  preference), fast 1817, core 1190 green, zero new failures.
- **Out of scope** (unchanged): LLM generation, overlay curation,
  persistence; canned `generativeThought`/`MoveGenerativeThought`
  remain the ultimate no-foothold fallback.

---

# F1 user-side misunderstanding trigger — pre-registration (2026-09-27)

- **Finding**: «ты меня не понял, я про другое» → prepare yields
  `PlainAssert` (no trigger covers the user-side report) → render
  reverse-map hits the over-broad «я»-feature →
  `IntentSelfReference` + self-knowledge template. The user gets
  biography instead of repair.
- **Rule (locked)**: add one raw trigger `dont_understand_you_ru`
  («ты не понял» / «ты меня не понял» / «ты не понимаешь»,
  lowered-substring, same shape as `not_understand_ru`) admitted
  through the existing misunderstanding admission into the existing
  `MisunderstandingReport` builder arm. No chain reorder, no
  self-knowledge narrowing: none of the self-knowledge raw triggers
  match the three forms (verified by inspection — «ты понимаешь
  контекст» needs the full phrase), so prepare resolves to
  `MisunderstandingReport` and render maps it to `IntentRepair`
  via the existing explicit case. The over-broad «я»-feature is
  left untouched (separate change with its own blast radius).
- **Bar**: unit pins — the three forms → `MisunderstandingReport`
  (+ `CMRepair`); negatives — «ты понимаешь время?» and «что ты
  знаешь о себе?» stay NOT-misunderstanding, «я не понимаю тебя»
  stays misunderstanding; live probe N≥3 user-side reports render
  the repair surface («Я принимаю это как сигнал сбоя…»);
  controls — one self-knowledge question + one plain «я»-utterance
  byte-identical by construction (untouched paths); zero new
  failures in unit/fast/core.
- **Out of scope**: self-knowledge «я»-feature narrowing (F1b),
  «ты не понимаешь контекст» capability/misunderstanding overlap
  (self-knowledge keeps winning by chain order — defensible).

---

# F1 user-side misunderstanding trigger — landed (2026-09-27)

- **Rule** (pre-registered above): `dont_understand_you_ru`
  («ты не понял» / «ты меня не понял» / «ты не понимаешь») through
  the existing admission into the existing `MisunderstandingReport`
  arm. No chain reorder, no self-knowledge narrowing.
- **Why prepare-only fixes it end-to-end**: no self-knowledge raw
  trigger matches the three forms, so prepare resolves to
  `MisunderstandingReport` and render maps it to `IntentRepair` via
  the existing explicit case (the «я»-feature misfire needed a
  `PlainAssert` to act on — it no longer gets one here).
- **Probe**: 3/3 user-side reports → `CMRepair` + the production
  repair surface (`structuredBody MisunderstandingReport` — «Вижу
  сигнал перегруза…»; the «Я принимаю…» line cited in the pre-reg
  is the move/fallback text, not the production surface —
  corrected here). Controls «ты понимаешь время?» / «что ты знаешь
  о себе?» unchanged (no trigger matches, by construction + live);
  «я не понимаю тебя» unchanged.
- **Verification**: unit 1626, fast 1818, core 1191 green, zero new
  failures. New test pins 3 positives + 2 negatives + preserved
  system-side report.

---

# F2 stale-topic hold — pre-registration (2026-09-27)

- **Mechanism (proven by fresh-vs-carried differential probe)**:
  uncovered turn («всё бессмысленно…», best=бессмысленно) with a
  carried covered topic (ответственность, T1) renders «Держу
  ответственность…». Chain: route-hint AnchorSignal + carried
  `rmpTopic` → `buildDialogAtoms` takes atoms topic from
  `rmpTopic` (`nonEmptyOr (rmpTopic rmp) …`) → `resolveLegacyGf`
  linearizes atoms via real PGF (`dialogAtomsToGfExpr` maps any
  non-define intent to `MoveGround (MkNP <atoms-topic>)`) →
  grammar renders the hold naming the stale topic
  (`FromShim`/`russian_compatibility_shim` tags). Fresh session
  (atoms topic = bestTopic, uncovered → lexeme lookup fails →
  `Left`) falls through to the honest template path («Смысловая
  точка: бессмысленно»). The move layer was correctly silent in
  both (v4 rules).
- **Rule (locked)**: in `buildDialogAtoms`, keep the RMP topic as
  atoms topic ONLY if it is mentioned in the current raw input —
  normalized whole-token match OR nominative-form match via
  morphology (covers canonicalized «ответственность» vs input
  «ответственности»); otherwise fall back to the frame's focus
  entity (current-turn signal), then «тема» as today. Coherent
  turns (topic mentioned or identical) are byte-identical by
  construction; stale-carried topics fail closed into the
  honest-uncovered path.
- **Bar**: unit pins on `buildDialogAtoms` (mentioned-carried kept;
  unmentioned-carried replaced by focus; empty-focus keeps «тема»);
  live probe — carried session no longer names the stale topic,
  fresh session byte-identical, one coherent multi-turn control
  unchanged; zero new failures in unit/fast/core.
- **Out of scope**: `dialogAtomsToGfExpr`'s else→MoveGround
  collapse (separate mapping question); the AgreementAnchor
  route-hint inference itself; F1b «я»-feature.

---

# F2 stale-topic hold — landed (2026-09-27)

- **Rule** (pre-registered above): `buildDialogAtoms` keeps the RMP
  topic as atoms topic only under the mention guard
  (`topicMentionedHere`: whole-token `topicMentioned` OR
  nominative-form match per token); otherwise the frame's focus
  entity, then «тема».
- **Probe**: carried session («ответственность» → «всё
  бессмысленно…») no longer names the stale topic — renders
  «Упор — бессмысленно» on the current topic. Fresh session
  byte-identical to pre-fix («Смысловая точка: бессмысленно»).
  Coherent multi-turn control («что такое ответственность и почему
  она важна?») renders the full thesis unchanged.
- **Verification**: unit 1627, fast 1819, core 1192 green, zero new
  failures. New pins: nominative inflection counts, absent topic
  excluded, stale-carried replaced by focus at atoms level,
  mentioned-carried kept.
- **Residual note**: `dialogAtomsToGfExpr`'s else→MoveGround
  collapse stays as-is (separate mapping question, out of scope).

---

# F1b bare-pronoun self-reference backstop — pre-registration (2026-09-28)

- **Measurement**: 4/4 ordinary first-person probes («я думаю, что
  свобода важна», «я согласен с тобой», «мне кажется, время
  летит», «я про другое») render the self-knowledge biography
  template via render-side `IntentSelfReference` — even Q1, whose
  turn knew bestTopic=свобода. The prepare-side SelfKnowledgeQ
  detector is precise and unit-pinned; the render-side L4 backstop
  (`sfHasSelfReference`: bare «я»/«мой»/«мне»/«сам»/«себя»/«лично»,
  no topic needed) second-guesses it whenever prepare yields a
  type that falls through `semanticIntentForRender` to
  `classifyIntent`.
- **Rule (locked)**: thread `allowSelfReference` (Bool, default
  True = legacy) through `classifyIntent → classifyFromFeatures →
  classifyTopicSpecific`; the L4 self-reference branch fires only
  when allowed. `semanticIntentForRender` passes True ONLY for
  prepare `SelfKnowledgeQ`, False for every other type — render
  respects prepare's precise detector instead of re-deriving selfhood
  from pronouns. `classifyIntent` signature unchanged (legacy entry
  preserved for existing pins); render uses the new
  `classifyIntentWithoutSelfReference`. Structured-type surfaces
  (which key off the prepare type directly) are untouched by
  construction; only plan/supplement paths for non-SelfKnowledgeQ
  types change, and only on inputs containing bare self-pronouns.
- **Bar**: unit pins — the 4 probes no longer yield
  `IntentSelfReference` via the gated entry (legacy entry keeps
  yielding it: backstop documented, not deleted); render-gate
  pins via `semanticIntentForRender` (SelfKnowledgeQ+«кто я?» and
  SelfKnowledgeQ+«расскажи о себе» == legacy output;
  non-SelfKnowledgeQ+4 probes ≠ SelfReference); existing
  `IntentClassifier` pins green untouched (legacy signature
  preserved); live probe — Q1-class turns render topical
  surfaces (no biography), genuine self-questions
  (prepare SelfKnowledgeQ → legacy) keep biography, «что ты
  знаешь о себе?» keeps a sane surface (its structured arm keys
  off the prepare type, insulated from the intent gate);
  crisis/speculative controls clean; zero new failures in
  unit/fast/core.
- **Out of scope**: exotic «я»-self-questions prepare misses
  (accepted residual — «ты»-phrasings already had no backstop);
  `dialogAtomsToGfExpr` else→MoveGround; AgreementAnchor inference.

---

# F1b bare-pronoun self-reference backstop — landed (2026-09-28)

- **Rule** (pre-registered above): `allowSelfReference` threaded
  through the compositional chain; render passes True only for
  prepare `SelfKnowledgeQ`. `classifyIntent` signature preserved.
- **Probe**: 4/4 ordinary first-person utterances fixed — topical
  holds («Держу свободу…», «Упор — согласен», contemplative о
  времени, «Смысловая точка: другое»), zero biographies.
- **«кто я?» recovery surface proven pre-existing**: prepare yields
  SelfKnowledgeQ (new unit pin), so the gate serves the legacy
  chain and every downstream value is identical pre/post; the
  GuardRecovery surface comes from `linearization_ok=False` on the
  self-knowledge arm in degraded mode without PGF. Separate
  observation, out of scope. «расскажи о себе» path likewise
  untouched (SelfKnowledgeQ → legacy, unit-pinned at both levels).
- **Controls**: crisis (Protocol B resources) + speculative
  (thesis) clean live.
- **Verification**: unit 1632, fast 1820, core 1193 green, zero new
  failures. New pins: backstop documented on legacy, dropped on
  gated, render-gate equality for SelfKnowledgeQ prepares,
  prepare-level SelfKnowledgeQ pins for «кто я?»/«расскажи о себе».
- **Doctrine (step 1 of the 1→2→3 plan)**: witness re-record rule
  added to the lexicon pipeline doctrine («Lexicon pipeline
  doctrine» section above).

---

# Verbalizer roughness (v2 surfaces) — pre-registration (2026-09-28)

- **Measurement** (v2 probe): «предполагать возможность;
  предполагать возможность выбора» (subsumed duplicate from term
  union); «контрастирует с смерть» (finite curated edge verb via
  `relVerbText` preference + caseless object). Both hypothesis-
  marked and grounded — mannerisms, not authority failures.
- **Rule (locked), two parts**:
  - R1 subsumption: in composed terms, same verb with token-prefix
    objects keeps only the longest («предполагать возможность»
    subsumed by «предполагать возможность выбора»). Zero
    information loss (shorter entailed by longer); maximal elements
    always survive, so gates observing non-empty rels are safe.
    Applies at composition (both direct and mediated constructors),
    so all consumers (endorsement, overlap, verbalize) see clean
    terms. Existing pins use distinct pairs — unaffected.
  - R2 edge-verb infinitive: mediated edge contributions use the
    curated `relVerbText` ONLY when it belongs to the frozen
    `relationLexicon` (already infinitive); otherwise the frozen
    `relTypeVerb` map infinitive. Module doctrine says verbs stay
    infinitive — the preference for curated finite forms violated
    it. Curated infinitive nuance preserved; only finite forms
    normalize.
- **Bar**: unit pins — subsumption (prefix collapses, distinct
    kept, never empties); finite edge verb normalizes, infinitive
    curated verb preserved; existing Assembly pins green
    untouched; live re-probe of the 3 fired v2 turns — improved
    surfaces, still coherent + grounded, zero false-authority;
    zero new failures in unit/fast/core.
- **Out of scope (documented residual)**: oblique-case government
  («противопоставлять смерть» still caseless — needs verb valency
  tables that do not exist); parser stop-word treatment of «с»;
  citation-quoting reformats (rejected: reformats clean surfaces
  for cosmetic gain).

---

# Verbalizer step v1 (R1/R2) — landed (2026-09-28)

- **Rules** (pre-registered above): R1 subsumption at composition
  (both constructors); R2 curated edge verbs kept only when in the
  frozen lexicon, else map infinitive.
- **Re-probe** (operator-confirmed 3/3 coherent, zero
  false-authority): свобода — subsumed dup gone («предполагать
  возможность выбора» only); смерть — «контрастирует с смерть» →
  «противопоставлять смерть»; смысл — first pair normalized,
  residual «противопоставлять со смертью» stands as documented
  valency mannerism (needs valency tables; out of scope).
- **Verification**: unit 1636, fast 1820, core 1193 green, zero new
  failures. New pins: subsumption collapse/preserve/never-empty,
  finite-verb normalization; all pre-existing Assembly pins green
  untouched.

---

# Guard-recovery honesty: deterministic quality false-positive — pre-registration (2026-09-28)

- **Mechanism (proven read-only + live, `trcPreSafetyRenderedRaw`)**:
  «кто я?» → correct SftUser surface («О тебе я знаю…», second
  person, 56 tokens) → `checkTopicRelevanceBlock` (≥50 tokens)
  compares against topic «себя» → zero overlap (surface honestly
  uses тебе/твои) → QualityBlock → recoverySurface promising
  «продолжим через секунду». Retry is futile by construction
  (pure function of topic+text) — the promise is false. The
  specific reason («no overlap with topic») is DISCARDED: trace
  keeps only `render_guard=blocked`.
- **Rule (locked), two parts**:
  - G1 person-aware overlap: canonicalize both token lists in
    `checkTopicRelevanceBlock` through a frozen reflexive↔
    second-person equivalence map (себя/собой/себе +
    тебя/тебе/тобой/твой-формы → one person token). Deixis shift
    between topic and surface is legitimate; all other checks
    (density/saturation/filler/placeholders) still apply.
    Frozen list, unit-pinned, no math-version impact (gate
    threshold 50/counting unchanged).
  - G2 trace the reason: `finalizeOutputWithTopic` additionally
    returns the block reason (`Maybe Text`); route evidence
    becomes `["render_guard=blocked", reason]` (reason absent →
    today's shape). Zero behavior change — honesty only.
- **Bar**: unit pins — себя-topic + тебе-surface (≥50 tokens)
    passes; unrelated long text still blocked; all existing
    quality/guard pins green; live — «кто я?» renders the SftUser
    surface (no recovery), one genuinely-blocked control still
    blocked (empty/placeholder probe), crisis + speculative
    controls clean; zero new failures in unit/fast/core.
- **Out of scope (follow-up)**: the recovery TEXT retry promise
  («продолжим через секунду») — every current trigger is
  deterministic, so the promise is structurally dubious, but
  rewording needs its own design across all recovery causes;
  structural checks untouched; `dialogAtomsToGfExpr` else-branch.

---

# Guard-recovery honesty (G1/G2) — landed (2026-09-28)

- **Rules** (pre-registered above): G1 person-aware overlap in
  `checkTopicRelevanceBlock` (frozen reflexive↔second-person map);
  G2 block reason threaded into trace evidence
  (`finalizeOutputWithTopicReason`, gate byte-identical).
- **Probe**: «кто я?» renders the genuine SftUser surface (no
  recovery); recovery cause stays `runtime_degraded` (environment).
  Crisis + speculative controls clean.
- **Verification**: unit 1639, fast 1820, core 1193 green, zero new
  failures. New pins: person-deixis pass, unrelated-long still
  blocked, reason traced with behavior equivalence.
- **Residual**: the recovery TEXT retry promise («продолжим через
  секунду») stands — rewording needs its own design; structural
  checks untouched; `dialogAtomsToGfExpr` else-branch untouched.
- **Process note**: a nested-`open(p,'w')` python edit truncated
  `Route/Render.hs` to 0 bytes mid-landing; recovered via
  `git checkout` + redo with the safe edit tool. Never nest a
  same-path read inside a same-path write expression.

---

# Recovery-text honesty — pre-registration (2026-09-28)

- **Finding**: every trigger reaching `recoverySurface` (structural
  + quality finalize blocks, constitution blocks seen in B2
  fixtures) is deterministic per (history, text, topic) — yet the
  text promises transient reconfiguration + retry-after-a-second
  («перенастраиваю ход мысли… продолжим через секунду?»). Retry of
  identical input fails identically; the promise is structurally
  false. B2 historical fixtures quoting the old string are records
  and stay untouched; no unit test pins the string.
- **Rule (locked)**: replace with «Извини, на эту реплику честного
  ответа у меня не собралось — попробуешь сформулировать иначе?»
  Owns the failure, no fake reconfiguration, no time promise,
  invites reformulation (different input may take a different
  path), no input echo, no authority. Voice-consistent with the
  established «связка не собралась». Ends «?» consistent with
  `gsQuestionLike=True` (loop observation only). 13 tokens —
  passes its own gate (short-circuit thresholds) by construction,
  unit-proven.
- **Bar**: unit pins — exact string; the string itself passes
  `evaluateContentQuality` + structural surface check (no
  self-block); live — overlong input (>5000 chars, deterministic
  length block) renders the new text; «кто я?» still renders its
  genuine surface (no regression from G1); crisis control clean;
  zero new failures in unit/fast/core.
- **Out of scope**: per-cause differentiated surfaces (needs the
  G2 reason plumbed into text selection — separate design);
  structural/quality thresholds untouched.

---

# Stage-0 IR miniature — landed shadow-only (2026-09-28)

- **What**: `QxFx0.Semantic.IR` (Term/Proposition/Interpretation,
  total s-expr parser + pretty + structural validator with
  closedness) + `data/semantic_ir/gold.jsonl` (100 hand-authored
  rows: negation 30 / quantifier 30 / polysemy 25 / paraphrase 15,
  pair groups byte-identical incl. the §2.3 anchor pair) +
  `Test.Suite.SemanticIR` (validator, round-trip, full gold
  validation incl. pair-IR equality).
- **Status**: SHADOW ONLY — zero runtime callers, zero behavior
  change. Validator discipline: non-empty Apply roles, no vacuous
  quantification, top-level closedness. Two authoring bugs caught
  by the pins themselves (bindings-list paren in the grammar;
  17 unbalanced rows fixed).
- **Verification**: unit 1648 green (8 new pins). No other suite
  affected by construction (new module, no callers).
- **Explicitly deferred**: Sense contracts, Atom↔IR bridge,
  any selection/render/persistence wiring (each needs its own
  pre-registered landing).

---

# Recovery-text honesty — landed (2026-09-28)

- **Rule** (pre-registered above): recovery text owns the failure
  («Извини, на эту реплику честного ответа у меня не собралось —
  попробуешь сформулировать иначе?»), no fake reconfiguration, no
  retry promise. B2 historical fixtures quoting the old string are
  records, untouched; no unit test pinned it.
- **Probe**: overlong input degrades to a hold (length gate checks
  rendered text, not input — honestly recorded); wiring proven at
  unit level (blocked GuardSurface renders the new text with
  recovery provenance); «кто я?» keeps its genuine surface;
  crisis control clean.
- **Verification**: unit 1640, fast 1820, core 1193 green on the
  final code; property 227 + integration 46 + slow 173 green on
  pre-text code (the change is one string literal + reason
  threading; no suite pins the old string — verified by grep).

---

# OQ1 Field-vs-SemanticAuthority verdict (2026-09-29, read-only review)

- **Charge (confirmed at mechanism level)**: predicate ranking
  turns on cosine overlap with 20 hand-written prototype words
  (`fieldDimensionPrototypes`, `Space/Types.hs` — incl. the
  English straggler `related_to`). The landed «different Field
  selects different predicates» example is near-tautological:
  high-Confidence selects «истина претендует…» largely because
  «претендует» is literally a FdConfidence prototype word. This
  is lexical coincidence elevated to content selection, not
  semantic grounding. Prototypes uncalibrated (Phase II tuning
  deferred, acknowledged).
- **Violation (NOT found)**: Field cannot resolve genuine
  ambiguity, by construction: (1) pools are sense-pure by
  curation — «воля» carries volition only, «язык» language only
  (no freedom/outdoors/tongue competitors pooled); sense
  competition lives at the TOPIC level, decided upstream by
  intent/frames/morphology; (2) Field only ranks compatible
  facets within one addressed topic (emphasis, e.g. истина:
  correspondence-claim vs verification-method); (3) topic
  injection impossible (topic fixed upstream of selection);
  (4) fallback is corpus-order, Field-independent (nothing over
  0.1 → first predicate, score 0.0); (5) downstream semantic
  vetoes stand (GeneratedPredicateGate, endorsement, assembly
  R+L2, quality gate, rescue); (6) per-candidate diagnostics make
  every ranking reconstructable in trace.
- **Verdict**: COMPLIANT with bounds. Field ranking is
  PersonalityPolicy-grade emphasis modulation inside
  SemanticAuthority-approved bounds — not a boundary violation.
  Recorded as an explicit carve-out, not a refactor trigger.
- **Shored up**: `fieldDimensionPrototypes` frozen by unit pin —
  any edit is now a deliberate, test-visible, math-versioned
  decision. Residuals: prototype curation debt (`related_to`,
  4-word lists); no systematic sense-purity audit beyond
  spot-checks (воля/язык/истина); offline prototype fitting
  stays a calibration-phase item.
- **Verification**: unit 1649 green (1 new pin). No behavior
  change — review + pin only.

---

# F4 dead-code hygiene — landed minimal (2026-09-29)

- **Reference audit first**: most of the F4 inventory is
  load-bearing under other names — structScore/jaccard are live
  measurement instruments (eval script + reports + pins);
  `assemblePair` is the live direct-bridge constructor;
  `composeFromActivation`/`composePredicates` are legacy API with
  unit pins (also imported by OntologyContentSelector tests);
  `buildAssemblyCandidates` is trace observability by design;
  MoveGenerativeThought constructor/parsers/tags are live
  plumbing (only canned surfaces are degenerate-fixture-only);
  `Dialogue.generativeThought` + `fallbackStructuredText` serve
  degenerate fixtures; the morph-variant path + backend shim are
  the price of the live external bridge interface
  (`Bridge/Morphology.hs`: HTTP service, env config) and frozen
  reserve for Stage-2 syntax work — deleting the contextual
  morph block (448–972) now would destroy material the concept
  program explicitly needs. `toNominative`-empty-arg and
  `extractFeatures`-`_morph` would change behavior to fix:
  converted to findings (pre-reg material), untouched.
- **Actually removed** (zero references, verified by grep):
  unused `extractFeatures` import in `Route/Render.hs`;
  `renderDialogueUtterance` (def + export, no callers anywhere
  incl. scripts).
- **Verification**: unit 1649, fast 1820, core 1193 green.
  Behavior-neutral by construction (no reachable path touched).

---

# Real morphology for focus nominative — pre-registration (2026-09-29)

- **Finding (F4)**: `Parse.hs` computes `ipfFocusNominative` via
  `toNominative` over a hardcoded EMPTY `MorphologyData` — the
  heuristic guess always runs even though real paradigms
  (20025+ lemmas) are loaded in `ssMorphology`. The nominative
  feeds turn focus selection (`Effects.hs:458`: nominative first,
  then raw focus, atom focus, last topic), stance kernel
  (`Pulse.hs:243`), and corpus tooling. Inflected focuses
  («ответственности») canonicalize by guess, not by data.
- **Rule (locked)**: add `parsePropositionWithFrameAndTruthContractMorph`
  (morphology first arg); existing entries delegate with empty
  morphology (test-fixture behavior byte-identical, zero test
  churn); production call site (`Effects.hs:559`) passes
  `ssMorphology`. No other call sites change. Heuristic remains
  the fallback inside `toNominative` for OOV.
- **Bar**: unit pins — inflected focus + real nominative map →
  correct nominative; empty-morph entry unchanged on the same
  inputs; live probe N≥6 inflected definitional turns (topics
  correct-or-better, none degraded to unknown/hold) + 3
  nominative-form controls byte-identical by construction;
  zero new failures in unit/fast/core.
- **Out of scope**: `extractFeatures`-`_morph` (separate API
  churn); RGL paradigms flag; lemma-map coverage expansion.

---

# Real-morphology focus nominative — landed (2026-09-29)

- **Rule** (pre-registered above): `...WithMorphology` variants;
  production passes `ssMorphology`; fixtures keep empty-morph
  entries byte-identically.
- **Probe**: inflected topics canonicalize live
  («ответственности»→bestTopic `ответственность`,
  «свободе»→`свобода`, «любви»→`любовь`); nominative controls
  normal. Q4 adjectival wart («ответственным» → tautology)
  proven pre-existing (form absent from morphology → identical
  heuristic in both eras, bestTopic unchanged) — recorded as a
  separate wart, out of scope.
- **Verification**: unit 1650, fast 1821, core 1194 green, zero
  new failures. New pins: real-map canonicalization,
  empty-morph fixture behavior, nominative passthrough.

---

# Stage-1 batch 1 — landed shadow-only (2026-09-29, ADR-0054)

- **What**: `primitives.jsonl` (24, 7 with `atom:null` +
  per-item justifications — agent/alternative/coercion/promise/
  ban/permission/goal have no corpus lemma, verified by scan) +
  `senses.jsonl` (6: свобода ×3 per concept §3.1, воля ×3 with
  liberty/outdoors split) + schema validation pins (closed kind
  set, atom-XOR-justification, human provenance pinned).
- **Status**: SHADOW ONLY — no runtime reads these files.
- **Verification**: unit 1652 green (2 new pins + gold intact).

---

# Stage-1 batch 2 — landed shadow-only (2026-09-29, ADR-0054)

- **What**: `rules.jsonl` (8 strict + 8 defeasible with scope,
  exceptions, priority; defeasible carries the concept's own
  §6.2 coercion example) + `minimal_pairs.jsonl` (10 contrast +
  6 scope-shift + 4 equivalent) + schema pins incl. variable
  discipline (conclusion vars ⊆ premise vars) and pair-relation
  mechanization (equivalent shares IR, others differ).
- **Status**: SHADOW ONLY — no runtime reads these files.
  Evaluator module is a later batch.
- **Verification**: unit 1654 green (2 new pins). Pins caught 4
  authoring slips (3 unbalanced sexprs, 1 missing key).

---

# Stage-1 batch 3 evaluator — pre-registration (2026-09-29, ADR-0054)

- **Design (locked)**: `QxFx0.Semantic.IREval`, pure/total/
  deterministic, zero pipeline callers. Structural pattern
  matching (pattern vars bind on first occurrence, must be
  consistent after; Concept/Entity/Event match by equality;
  binders match structurally with identical names — NO
  alpha-equivalence in v1, documented limitation). Forward
  chaining with fuel (32 steps) over strict rules; proof objects
  (rule id + premise indices + substitution). Defeasible fires
  iff premises match + no exception matches under the firing
  substitution + scope equals query scope (or rule scope empty).
  Priority: higher number wins contradictory defeasible
  conclusions; strict always beats defeasible. Verdicts:
  Entails | NotEntailed | DefeatedBy | Conflict, all JSON-
  serializable (evaluation scripts are a later batch).
- **Bar**: unit pins — binding consistency, shape mismatches,
  binder strictness, fuel termination, exception blocking,
  priority ordering, strict-beats-defeasible, presupposition and
  conflict checks, end-to-end over `rules.jsonl` (loads, fires,
  terminates); zero new failures (unit-only suite impact).
- **Out of scope**: alpha-equivalence, backward chaining,
  probabilistic weights, JSON trace scripts, any runtime reads.

---

# Stage-1 batch 3 evaluator — landed shadow-only (2026-09-29, ADR-0054)

- **What**: `QxFx0.Semantic.IREval` (structural matching with
  first-occurrence binding, no alpha-equivalence v1; fuel-bounded
  strict forward chaining with proof objects; defeasible firing
  with exceptions/scope/priority, strict-beats-defeasible;
  presupposition checks; conflict detection; JSON verdicts) +
  evaluator pins incl. end-to-end over `rules.jsonl` (rs-05
  derives, rd-02 fires clean and blocks on coercion).
- **Status**: SHADOW ONLY — no runtime callers. JSON trace
  scripts and scenarios/cluster-gold remain later batches.
- **Verification**: unit 1662 green (8 new pins).

---

# Stage-1 batch 4 held-out split — landed (2026-09-29, ADR-0054 §2.4)

- **What**: `scripts/split_semantic_ir.py` (id-hash 60/20/20,
  `--check` mode) + frozen `splits.json` (63/16/21 + source
  digest) + unit split-integrity pins. Rules stay unsplit by
  design (model, not test data). Content-hash integrity lives
  in `--check`; unit pins partition structure (no sha256 dep in
  test-common by choice).
- **Verification**: unit 1663 green (1 new pin).

---

# Stage-1 batch 5 scenarios — landed shadow-only (2026-09-29, ADR-0054)

- **What**: `scenarios.jsonl` (30 multi-turn dialogues, 71 turns:
  paraphrase, contrast, negation-scope, polysemy, revision with
  grounds, clarification with multi-interpretation turns,
  counterexample weakening, concession, abstention, disagreement
  localization, quantifier/temporal/deontic scopes). Schema pins:
  30 rows, alternation, closed 9-act set, every interpretation
  parses + validates + closes.
- **Status**: SHADOW ONLY — scenario simulation is a later
  batch; no runtime reads.
- **Verification**: unit 1664 green. Pins caught 6 authoring
  slips (incl. 2 compensating paren typos); 2 pin-shape fixes
  (system-opening revision probes legitimate; sc-06 gained its
  answer turn).

---

# Stage-1 batch 6a cluster gold — landed shadow-only (2026-09-29, ADR-0054)

- **What**: `cluster_freedom.jsonl` (100 utterances across the 9
  cluster topics, same row schema as gold-100; equivalent pairs
  share byte-identical IR, converse equations kept solo by
  design) + validation pins (100 rows, pair-IR equality).
- **Status**: SHADOW ONLY — no runtime reads.
- **Verification**: unit 1665 green. Pins caught the systematic
  trailing-paren authoring habit (programmatic trim + parser as
  judge), 1 unbound variable, 1 pair-discipline violation.

---

# Stage-1 batch 6b cluster gold — landed shadow-only (2026-09-29, ADR-0054)

- **What**: +100 cluster rows (cl-101..200: modals, temporals,
  conditionals, hypotheticals, coercion-boundary packet
  request/persuasion/incentive/manipulation, deeper topic
  coverage) → 200 total. Pair discipline enforced (3 solitary
  converses nulled).
- **Status**: SHADOW ONLY — no runtime reads.
- **Verification**: unit 1665 green. Python pre-check mirror
  caught 40+ authoring slips before the expensive suite run;
  Haskell pins are the authority.

---

# Stage-1 batch 6c cluster gold — landed shadow-only (2026-09-29, ADR-0054)

- **What**: +100 cluster rows (cl-201..300: entailment precedents
  shaped to rs/rd rule patterns, 10 contradiction pairs for
  conflict eval, presupposition cases, burden/topic chains) →
  300 total.
- **Status**: SHADOW ONLY — no runtime reads.
- **Verification**: unit 1665 green. Pre-check mirror caught
  all slips (trailing parens); Haskell pins authoritative.

---

# Stage-1 batch 6d cluster gold — landed shadow-only (2026-09-29, ADR-0054)

- **What**: +100 cluster rows (cl-301..400: defeasible instances
  shaped to rd-rule fire/block patterns, scope-marked rows,
  proverbs, deontic/temporal chains, trust/promise/oath
  clusters) → 400 total.
- **Status**: SHADOW ONLY — no runtime reads.
- **Verification**: unit 1665 green. Programmatic rebuilds for
  misnested rows; trailing-trim with nesting guard.

---

# Stage-1 batches 6d/6e cluster gold — landed shadow-only (2026-09-29, ADR-0054)

- **What**: +200 cluster rows (cl-301..500: defeasible
  instances shaped to rd-rule patterns, scope-marked rows,
  proverbs, deontic/temporal chains, modal/quantifier
  matrices, tension pairs) → 500 total. Corpus complete per
  the 300–500 budget.
- **Status**: SHADOW ONLY — no runtime reads.
- **Verification**: unit 1665 green. Programmatic rebuilds for
  misnested And/Not/Exists shapes; pre-check mirror as first
  gate, Haskell pins authoritative.

---

# Stage-1 exit harness — landed (2026-09-29, ADR-0054 §2.5/§6)

- **What**: `exit_tasks.jsonl` (36 tasks: 12 strict incl.
  2 multi-step chains + 4 negatives, 10 single + 2 duels
  defeasible, 6 conflicts, 6 presuppositions) + harness pins
  with preset thresholds (strict ≥ 0.80, defeasible ≥ 0.60,
  conflicts/presuppositions exact) incl. duel resolution
  (higher-wins, tie-kept paraconsistent).
- **Measured (v1)**: strict 12/12, defeasible 12/12, conflicts
  6/6, presuppositions 6/6 — green by construction (tasks
  authored with known answers); the gate's teeth are for future
  rule/evaluator changes. Human leg (B2-style pairs) stays open
  per ADR (rater unavailable).
- **Verification**: unit 1670 green (5 new pins).

---

# Stage-1 batch 7 scenario expectations + first exit measurement — pre-registration (2026-09-29, ADR-0054)

- **Design (locked)**: scenario rows gain `expectations`
  (soundness leg only): `no-conflict` over all turns (revision ≠
  structural contradiction, paraphrase ≠ contradiction) and
  `not-entailed` spot queries (no hallucinated derivations on
  dialogue KBs, file strict rules as the rule set). No `entails`
  expectations on scenarios — audit of all 30 KBs found no
  file-rule premise shapes present; asserting firings would
  require fitting data to the evaluator. Positive derivation
  stays covered by exit_tasks (+5 new strict rows here).
- **Rule**: expectations assert 100% (soundness invariants, not
  fitted accuracy). Triage on mismatch, in order: data typo (fix
  data) → evaluator gap (record, adjust expectation ONLY with
  documented reason) → genuine unsoundness (shadow-only fix with
  pins, inside batch scope).
- **Bar**: all scenario expectations hold; exit_tasks grow
  36→41 with strict still ≥ 0.80 (17/17 authored green);
  +5 strict rows mirror rs-01/rs-05/rs-07/rs-06/rs-03 on
  concrete facts; unit green; report prints the measured
  aggregate (no new threshold — informative per ADR).
- **Out of scope**: human leg, JSON trace scripts, runtime
  wiring, new rules (no rule changes in this batch).

---

# Stage-1 batch 7 scenario expectations + first exit measurement — landed (2026-09-29, ADR-0054)

- **What**: `expectations` on all 30 scenarios (30 no-conflict +
  10 not-entailed spot queries; no entails — audit found no
  file-rule premise shapes in scenario KBs, asserting firings
  would fit data to evaluator) + 5 strict exit rows mirroring
  rs-01/rs-05/rs-07/rs-06/rs-03 on concrete facts + scenario
  runner over ALL file strict rules.
- **First measurement**: 40/40 scenario expectations hold
  (revision ≠ structural contradiction; no hallucinated
  derivations on dialogue KBs); strict 17/17, defeasible 12/12,
  conflicts 6/6, presuppositions 6/6. Soundness leg complete;
  thresholds (≥0.80/≥0.60) satisfied with margin. Human leg
  stays open per ADR.
- **Verification**: unit 1671 green (scenario runner + 5 tasks).

---

# Deadjectival topic bridge (Q4) — pre-registration (2026-09-30)

- **Mechanism (proven live)**: «что значит быть ответственным?»
  → ConceptKnowledgeQ, subject `ответственным` (adjective,
  uncovered: paradigms are nouns-only, verified) → no
  predicates, GF default both sides → `MoveDefine ponyatie /
  ponyatie` tautology + rescue. The tautology (not the hold) is
  the garbage; other arms degrade honestly.
- **Rule (locked)**: frozen `deadjectivalTopicStems`
  (~20 stem→topic, ALL targets covered — unit-pinned) in
  `Semantic.Content` next to `definitionCorpus`; total pure
  `resolveDeadjectivalTopic` (normalized token, strict-prefix
  longest match, covered inputs and multiword pass through
  untouched). Applied at ONE site: the ConceptKnowledgeQ arm's
  `topicRef` resolution (`Dialogue.hs`) — uncovered-only, so
  covered topics are byte-identical. Selector, GF lexeme, and
  content supplement then hit the covered topic through
  existing paths (no new rendering logic).
- **Bar**: unit pins — all targets covered; fires on
  inflected/nominative adjectives (ответственным,
  свободном, справедливого); covered/multiword/unknown pass
  through; live probe — Q4 renders covered content (thesis
  supplement present, no tautology, no rescue), 2 nominative
  controls + 1 covered ConceptKnowledgeQ control unchanged;
  zero new failures in unit/fast/core.
- **Out of scope**: other arms (honest fallbacks, no garbage);
  adjective paradigms in morphology data (lexicon loop owns
  that, separate); contentSource reclassification (stays
  bestTopic-derived); full adjective inflection tables
  (stems, not forms).

---

# Q4 fix-point correction (2026-09-30, same pre-reg)

- **Correction**: the arm-level hunk was reverted unused — the
  tautology AST comes from `rmpPrimaryClaimAst` (preferred over
  the arm fallback), and the supplement is dropped downstream by
  the PGF-shim claim override. The fix moved to the true choke
  point: `mkTopicNP` (`Builders.hs`) resolves uncovered
  adjectival topics via the frozen table before the default
  lexeme. This heals every ClaimAst arm uniformly for the same
  input class (Ground/Contact/Reflect holds stop defaulting on
  adjectives too); covered/unknown behavior identical.
- **Revised bar**: Q4 renders «Ответственность является
  понятием.» with NO rescue (parity-or-better with covered
  «что значит» shapes, which carry their own DefaultLexeme
  wart). The supplement-eating shim override is recorded as a
  separate architectural wart (out of scope): structured
  supplements do not survive `resolveLegacyGf` claim
  linearization.

---

# Q4 fix-point correction 2 (2026-09-30, same pre-reg)

- **Correction**: unit diag shows the subject is the multiword
  infinitive phrase `быть ответственным`, not the bare adjective
  — both committed fixes missed (Parse fallback needs empty
  subject; mkTopicNP bridge refuses multiword). Fix: token-scan
  inside `resolveDeadjectivalTopic` (first stem hit wins,
  deterministically longest-first per token position order).
- **Pin amendment (honest)**: `свободный человек` now resolves
  to свобода (person-talk about the free is freedom-talk) —
  the multiword passthrough narrows to surfaces with NO
  stem-matching token. F2 clause-spans (`осознанность выбора`)
  still pass through (no stem hits) — verified by pin.

---

# Q4 deadjectival bridge — landed (2026-09-30)

- **Rule** (pre-registered + twice corrected): frozen 9-stem
  table (`deadjectivalTopicStems`, all targets covered) + total
  `resolveDeadjectivalTopic` (token-scan, covered-first,
  longest-match); applied at subject fallback (`Parse.hs`,
  empty subjects only) and `mkTopicNP` (`Builders.hs`, before
  the default lexeme); copula carve-out in `detectRescue`
  (resolved-subject definitional copulas don't rescue;
  subject-defaults still do; identical still tautology).
- **Corrections en route**: arm-level hunk reverted (AST comes
  from RMP, supplement eaten by shim — recorded as separate
  wart); token-scan replaces whole-surface match (subject is an
  infinitive phrase); bar revised to parity-or-better
  («Ответственность является понятием.», no rescue).
- **Probe**: Q4 fixed live; «что значит быть свободным?»
  fixed the same way; nominative + covered controls clean.
- **Verification**: unit 1675, fast 1822, core 1195 green.
  New pins: stem targets covered, bridge fire/passthrough/
  determinism, RMP subject lexeme, copula suppression shape.

---

# Shim-override scoping (resolveLegacyGf) — pre-registration (2026-09-30)

- **Measurement** (15-turn battery with provenance traces):
  FromShim fires on 5/15. T5 (ConceptKnowledgeQ, no plan):
  claim override strips the structured body (framing +
  thesis supplement) to the bare claim — DESTRUCTIVE (the Q4
  wart). T14 (atoms hold on current topic): benign. T12
  (farewell): atoms hold on the FALLBACK topic «тема» —
  contentless. T6/T11: questionable (possible supplement loss /
  fallback-topic leak «по теме понятии»). The other 10 never
  trigger (plan-canonical path with fail-closed fallback, or
  nothing to linearize). Plan path (`PgfClaimRoute`,
  AuthorityCanonical) is authoritative and untouched.
- **Rule (locked), two parts**:
  - R1 fill-in, never replacement: `resolveLegacyGf` returns an
    override ONLY when base `draRenderedText` is blank. A
    non-empty honest surface (including structured bodies, whose
    text was already linearized through the same Haskell
    renderer) is never replaced by a bare claim/atoms
    linearization. Empty-base fill-in (the legitimate upgrade)
    preserved.
  - R2 fallback-topic refusal: `dialogAtomsToGfExpr` returns
    `Left` for fallback topics («», «тема», «понятие»,
    «понятии», frozen list) — no atoms linearization out of
    nothing. Real topics byte-identical.
- **Bar**: unit pins — non-empty base kept despite linearizable
  claim; empty base still filled; fallback topics refused, real
  topics pass; live — identical 15-turn battery re-run and
  diffed: T5 gains its supplement, T12 loses its тема-hold,
  T14 same-or-better, all others byte-identical (any other
  delta triaged before landing); crisis/speculative controls;
  zero new failures in unit/fast/core.
- **Out of scope**: plan linearization path (canonical,
  untouched); B2 ablation path (bypasses resolution already);
  T11 «по теме понятии» if it lives in base template text
  (separate wart, recorded here); EN-path symmetry noted
  (same rule applies).

---

# Shim-override scoping (R1/R2) — landed (2026-09-30)

- **Rules** (pre-registered above): R1 fill-in-never-replacement
  (`legacyOverrideAdmissible` gate in `resolveLegacyGf`);
  R2 fallback-topic refusal in `dialogAtomsToGfExpr`
  («», «тема», «понятие», «понятии»).
- **Battery diff** (identical 15-turn rerun): T5 gains its full
  structured body (framing + claim + thesis supplement —
  combined with the Q4 bridge); T6/T14/T15 regain base content
  previously eaten (prefaces, tails, contemplative surface);
  T12 loses its fallback-topic atoms hold; T1–T4/T7–T9/T13
  byte-identical. Zero regressions — every delta is restored
  base content or a fixed hold.
- **Verification**: unit 1677, fast 1823, core 1195 green.
  New pins: gate condition, fallback refusal (+ real-topic
  control). Residuals: T11 «по теме понятии» lives in base
  template text (separate wart); claim/thesis double period
  (cosmetic micro-wart, follow-up).

---

# Micro-warts (punctuation + contact fallback topic) — pre-registration (2026-09-30)

- **W1 double period**: `clText claim` (ends «.») + `". "`-prefixed
  supplements render «..» (observed Q4; same shape in EN
  ConceptKnowledgeQ, EN/RU Distinction, challenge arms).
  Fix: `appendSupplement` strips one leading sentence-breaker
  (`.»/«!»/«?» + spaces) from the supplement — no-op for the
  many bare-supplement callers — and the four arms route their
  join through it instead of manual `<>`.
- **W2 contact fallback topic**: `MoveContact` with the default
  lexeme renders «по теме понятии» (RU, plus heuristic-truncated
  Loc) / «discuss понятие» (EN). Fix: default-lexeme topic →
  topic-less variants («Слышу запрос на контакт.» /
  «I am here to continue the dialogue.» — established EN
  phrasing, nothing invented).
- **Bar**: unit pins — appendSupplement strips dotted prefixes,
  bare behavior byte-identical (existing pins green); contact
  arms topic-less on default, unchanged otherwise; live —
  Q4 single period, «спасибо» without fallback-topic naming,
  2 controls (covered ConceptKnowledgeQ + greeting);
  zero new failures in unit/fast/core.
- **Out of scope**: MoveGround/Reflect/Describe default-topic
  naming (same class, unobserved live — follow-up wart);
  paradigms data for опора/понятие (lexicon loop owns it).

---

# Micro-warts bar amendment (2026-09-30, same pre-reg)

- **W2 extended**: the topic-less contact surface still carried
  the `gf_default_lexeme` tag (AST unchanged), so the rescue
  fired with a false premise («грамматике не хватило слов» —
  grammar is fine; contact smalltalk never owed a topic).
  `claimAstDefaultLexemeExcused` (renamed from the copula-only
  helper) now also excuses default-topic `MoveContact`: repair
  ⟺ degraded, and the turn renders fine. Real-topic contacts
  unaffected.

---

# Micro-warts (punctuation + contact topic) — landed (2026-09-30)

- **Rules** (pre-registered above + one amendment):
  `appendSupplement` normalizes one leading sentence break
  (bare callers byte-identical); ConceptKnowledgeQ EN/RU,
  Distinction EN/RU, and challenge joins route through it;
  default-lexeme `MoveContact` renders topic-less (RU/EN
  established phrasings); amendment: default-topic contact
  also excused from the DefaultLexeme rescue (false premise —
  contact smalltalk owes no topic).
- **Probe**: Q4 single period with full thesis; «спасибо»
  without fallback naming and without rescue; nominative +
  covered controls clean.
- **Verification**: unit 1679, fast 1825, core 1196 green.
  Residuals: MoveGround/Reflect/Describe default-topic naming
  (same class, unobserved — follow-up); paradigms data for
  опора/понятие (lexicon loop owns it).

---

# Fallback-topic class investigation (2026-10-01, read-only)

- **Battery** (12 topic-less inputs): fixed already — спасибо/пока
  (W2 topic-less contact); clean — привет, ага/давай (raw echo of
  the only signal, honest per F2 doctrine), понятно (anomaly
  refusal, separate behavior); WARTS — «ну»/«хм»/«да» render
  «Смысловая точка: тема» (+ «Для темы тема» on «да»).
- **Mechanism (complete chain)**: `inferFocus` /
  route-hint topic inference (`Input/Assemble.hs:1216,1223`)
  default to literal `"тема"` when no content noun exists →
  frame topic → bestTopic → family RCP opening
  `MoveReflectMirror` (`moveReflectMirrorPrefix` =
  «Смысловая точка: », `RenderLexicon.hs:74`) and Deepen
  templates interpolate it as content. The fallback noun is
  born at parse and laundered as a topic downstream —
  including into traces (`bestTopic=тема` is itself a lie:
  the turn has NO topic).
- **Out of scope (verdict: leave)**: raw echoes («ага»,
  «давай», «ладно») name the genuine only-signal — truthful;
  «понятно»-class anomaly refusal is separate behavior.
- **Fix options**:
  - (a) Surface guards: shared `isFallbackTopic` («», тема,
    понятие, понятии, опора, concept + case forms?) with
    topic-less variants at the 2–3 observed sites
    (MoveReflectMirror, Deepen probe). Small blast radius;
    leaves «тема» flowing in topics/traces.
  - (b) Source fix: `inferFocus`/route-hint return `""`
    instead of `"тема"`, letting existing empty-handling
    (nonEmptyOr chains, EmptyHold rescue, abstains) work
    honestly. Principled (no invented content; trace honest)
    but requires auditing every topic interpolation for
    empty-guards («Смысловая точка: .», «Для темы  …»).
  - Recommended: (a) now as bounded wart removal, (b) as
    follow-up with the interpolation audit. Shared frozen
    fallback list in both.
- **No code changed in this investigation.**

---

# Fallback-topic surface guards (a) — pre-registration (2026-10-01)

- **Rule (locked)**: frozen `isFallbackTopic` in
  `Semantic.Content` («», тема, понятие, опора, concept +
  observed inflections: темы, теме, понятии, опоре) with
  unit-pinned membership; `MoveReflectMirror` and the Deepen
  probe render topic-less variants on fallback topics, byte-
  identical otherwise. Source inferers keep returning «тема»
  (change (b) stays a separate follow-up with its audit).
- **Bar**: unit pins — list membership; both renderers
  topic-less on fallbacks, unchanged on real topics; live —
  «ну»/«хм»/«да» no longer name a fallback topic, raw echoes
  («ага») and greeting/anomaly paths unchanged; zero new
  failures in unit/fast/core.
- **Out of scope**: source fix (b) with interpolation audit;
  raw echoes; anomaly refusal; paradigms data.

---

# Fallback-topic surface guards (a) — landed (2026-10-01)

- **Rule** (pre-registered above): frozen `isFallbackTopic`
  («», тема/понятие/опора families + concept) with topic-less
  variants in `MoveReflectMirror` («Держу это как точку
  разбора.»), `MoveDeepenProbe` («Глубоко: о чём речь?») and
  both recovery topic fallbacks («этот вопрос» /
  «this question», via named `recoveryTopicText`).
- **Battery diff** (identical 12-turn rerun): ну/хм/да fixed;
  contact/greeting/raw-echo/anomaly/boundary paths
  byte-identical. Zero regressions.
- **Verification**: unit 1682, fast 1826, core 1197 green.
  New pins: fence membership, recovery helper, both moves
  (fallback vs real topic).

---

# Source fix (b): empty topic instead of invented "тема" — pre-registration (2026-10-01)

- **Rule (locked)**: `inferFocus` + route-hint `defaultTopic`
  (`Input/Assemble.hs`) return `""` instead of `"тема"`;
  `DialogueThread` clarified-items cons filters nulls (no-op
  today, hardening for the new reality). Everything else that
  produced `"тема"` (atoms fallback, arm literals, assembly
  NP) stays — separate literals, separate landings.
- **Why safe (audited)**: no `== "тема"` branches exist;
  frame-topic consumers use firstNonEmpty/null-checks
  (DialogueThread focus/claim/userGoal, Parse subjectFromFrame,
  Sense anchor); `moveToText` + recovery topicText already
  guard `""` via the (a) fence; `buildDialogAtoms` skips null
  topics; `mkTopicNP("")` keeps today's ponyatie default.
  Purpose/system/object fallbacks stay (meaningful defaults).
- **Bar**: unit pins — `inferFocus []`/`buildUtteranceSemanticFrame
  "ну"` yield `""` (no invented noun); live — identical
  12-turn battery re-run and diffed: «ну»/«хм»/«да» carry no
  topic noun anywhere (trace `bestTopic` honest), raw echoes +
  greeting + anomaly + contact paths unchanged-or-better,
  every other delta triaged before landing; crisis +
  speculative controls; zero new failures in unit/fast/core.
- **Out of scope**: atoms/arm/assembly literal fallbacks;
  purpose/system/object defaults; paradigms data.

---

# Source fix (b) bar amendment (2026-10-01, before landing)

- **Battery finding**: contentless turns after contentless turns
  inherit `ssLastTopic` («ну»→best `ага`) — legitimate discourse
  continuity, not invention (the old code suppressed it with the
  «тема» lie). Fresh contentless turns carry `bestTopic=""` and
  render the topic-less hold («Держу это как точку разбора.»);
  after real content they continue its topic («Смысловая точка:
  свобода»). The (a) guards and (b) source fix compose as
  designed. Bar amended accordingly (carried topics are honest).

---

# Source fix (b) — landed (2026-10-01)

- **Rule** (pre-registered above + bar amendment): `inferFocus`
  + route-hint `defaultTopic` + `fallbackFocusWord` return `""`;
  clarified-items cons filters nulls. Real-token echoes
  («ну» as frame topic) untouched — only invented nouns gone.
- **Probe**: fresh contentless turns carry `bestTopic=""` with
  the topic-less hold; after real content they continue its
  topic (legitimate continuity); raw echoes, greeting, anomaly,
  contact paths unchanged-or-better; every delta triaged.
- **Verification**: unit 1683, fast 1827, core 1198 green.
  The fallback-topic program (a)+(b) is complete: nothing in
  the system invents topic nouns anymore (remaining literals
  in atoms/arms/assembly are separate documented fallbacks).

---

# Backchannel focus exclusion (ага/угу) — pre-registration (2026-10-02)

- **Mechanism (proven live)**: acknowledgement backchannels of
  length ≥ 3 pass `isFocusCandidate` (length ≥ 3, not a
  stopword) and become `ipfFocusEntity` → turn `bestTopic`.
  Fresh «ага»/«угу» render «Смысловая точка: ага/угу»; worse,
  «ага» after real content DISPLACES the carried topic
  (свобода → ага, harvest battery live-0238..0251 turn 3).
  Short backchannels (ну/хм/да, length < 3) already yield ""
  via the length gate — the class splits on an arbitrary
  length threshold, not on semantics. Precedent: `Input/Parse.hs`
  already lists ага/угу as standalone particles; the focus
  layer never got the memo.
- **Rule (locked)**: frozen «ага», «угу» join
  `logicalFocusStopwords` (`Proposition/Focus.hs`) — the single
  list `isFocusCandidate` consults, so the exclusion applies
  uniformly (extractFocusEntity candidates + fallback words +
  Semantic.hs first/lastNonVapid). Frame-layer raw echoes
  (usfTopic/usfFocus) untouched — the signal layer stays
  honest; only topic candidacy goes.
- **Expected**: fresh «ага»/«угу» → `bestTopic=""` with the
  topic-less hold (same as «ну»); after real content they
  continue the carried topic (свобода) instead of displacing
  it. Covered/unknown behavior byte-identical.
- **Bar**: unit pins — `extractFocusEntity "ага"/"угу" == ""`,
  `isFocusCandidate` rejects both, covered topics unaffected
  (свобода still resolves); live — fresh ага/угу topic-less
  hold with `bestTopic=""`, continuity battery
  (свобода?→ну→ага→хм) keeps свобода throughout, greeting +
  contact + definitional controls byte-identical; crisis +
  speculative controls; zero new failures in unit/fast/core.
- **Out of scope**: ладно/хорошо/давай/понятно (consent/agreement
  class — real discourse function, separate landing);
  «так»/«вот» (ambiguous adverb/content); paradigms data;
  `isFallbackTopic` (ага stays not-fenced, per existing pin).

---

# Backchannel focus exclusion (ага/угу) — landed (2026-10-02)

- **Rule** (pre-registered above): frozen «ага», «угу» in
  `logicalFocusStopwords` (`Proposition/Focus.hs`) — the single
  list `isFocusCandidate` consults. Frame-layer raw echoes
  untouched.
- **Probe**: fresh «ага»/«угу» → `bestTopic=""` with the
  topic-less hold (same as «ну»); continuity battery
  (свобода?→ну→ага→хм) keeps свобода throughout — the
  displacement is gone. Greeting + contact + definitional
  controls unchanged; crisis control (Protocol B, hard
  trigger, resources v1) and speculative probe coherent.
- **Verification**: unit 1684, fast 1828, core 1199 green.
  New pin: `testBackchannelFocusExclusion` (rejection,
  empty entity, covered-topic control).
  Residuals: consent/agreement class (ладно/хорошо/давай/
  понятно), «так»/«вот», paradigms data.

---

# Stage-1 JSON trace scripts — pre-registration (2026-10-02, ADR-0054 §2.3)

- **Gap (audited)**: `IREval` verdicts are instant Haskell values
  consumed only inside `Test.Suite.SemanticIR`; the ADR-promised
  "JSON evaluation traces, consumed by scripts and tests" exist
  only on the tests side. No standalone emitter; measurements
  cannot be reproduced outside the suite or inspected per-task.
- **Rule (locked)**: new `executable qxfx0-stage1-traces`
  (`app/Stage1Traces.hs`, shadow-only, no pipeline callers —
  same status as `IR`/`IREval`): reads `exit_tasks.jsonl` +
  `scenarios.jsonl` + `rules.jsonl`, runs the file evaluators,
  writes `exit_traces.jsonl` (per task: id, kind, expected,
  verdict + proof/derivation, provenance tags) +
  `scenario_traces.jsonl` (per scenario per expectation) +
  `summary.json` (preset-threshold aggregates: strict ≥ 0.80,
  defeasible ≥ 0.60, conflicts/presuppositions exact).
  Row/runner logic MOVES (not copied) from
  `Test.Suite.SemanticIR` into a lib module
  (`QxFx0.Semantic.IREval.Batch`); the suite re-imports it.
  New rules: none. New data: none. Exit code 1 on any preset
  gate breach (real gate, informative today — everything is
  authored green), 0 otherwise.
- **Bar**: emitter runs on committed data → 41 task traces +
  40 scenario traces; aggregates match the suite measurement
  (strict 17/17, defeasible 12/12, conflicts 6/6,
  presuppositions 6/6, scenarios 40/40); two runs
  byte-identical (determinism); unit/fast suites green after
  the move (same pins, new import site); grep-confirmed no
  runtime callers of the batch module beyond exe+tests.
- **Out of scope**: human leg (no second rater); runtime wiring
  (non-goal §2.7); new rules/senses (additive-only §2.6);
  CI wiring (later decision); cutover ADR (needs exit +
  human leg per §2.5).

---

# Stage-1 JSON trace scripts — pre-reg amendment (2026-10-03, before landing)

- **Emitter finding (honest 11/12)**: first emitter run measured
  defeasible 11/12, not the reported 12/12. Triage per protocol:
  `x-d10` (duel, expected `tie-kept`) carries facts `promised`
  against rule premises `permitted` — neither rule can fire, so
  the doctrine-correct verdict is `no-duel`. Data expectation
  error since authorship (verified in the landing commit);
  the ≥0.60 threshold absorbed it and the report overclaimed.
  Fix (intent-preserving, operator-approved): `x-d10` facts →
  `(Apply permitted ((theme (Concept visit))))` so both rules
  fire at equal priority and the tie path — previously with zero
  positive coverage — is actually exercised. No rule/sense
  touched (§2.6 additive-only holds; the never-implemented
  `semanticDataVersion` counter has nothing to bump).
  Incidental: the moved runner corrects a dead-path triple
  (`entails`-without-query carried `expQuery` as kind).

---

# Stage-1 JSON trace scripts — landed (2026-10-03)

- **What** (pre-registered + amended): `QxFx0.Semantic.IREval.Batch`
  (row types + total Either-runners moved verbatim from the
  suite; wrappers preserve pin behavior) + `executable
  qxfx0-stage1-traces` (`app/Stage1Traces.hs`, shadow-only):
  `exit_traces.jsonl` (41) + `scenario_traces.jsonl` (40) +
  `summary.json` with preset-gate check; exit 1 on breach.
  Every trace carries `stage1-shadow` provenance (ADR §2.5
  zero-false-authority by construction).
- **Measured**: strict 17/17, defeasible 12/12 (honest after the
  x-d10 correction — only that row's trace changed),
  conflicts 6/6, presuppositions 6/6, scenarios 40/40.
  Two runs byte-identical. No runtime callers (grep).
- **Verification**: unit 1684, fast 1828, core 1199 green
  (same pins, new import site). Flakiness note: the first core
  aggregate run died silently at 1075/1199 with 0 failures
  (no process, no exit line — environmental, box not
  restarted, no OOM evidence readable); solo re-run 1199/1199
  exit 0. Pattern matches the documented one-off flakiness.
  Residuals: human leg, runtime wiring, CI wiring, cutover ADR.

---

# Consent-marker focus exclusion (ладно/хорошо/давай) — pre-registration (2026-10-03)

- **Mechanism (proven live)**: same shape as the backchannel
  wart. Bare consent markers pass `isFocusCandidate`
  (length ≥ 3, not stopwords) and displace carried topics:
  свобода → «ладно»/«хорошо»/«давай» render «Смысловая точка:
  ладно/...». Fresh turns carry them as `bestTopic` with the
  mirror surface. No pin depends on these focuses (only
  commitment/phase pins over «свобода это хорошо» touch the
  tokens in-sentence; deltas triaged via suite).
- **Rule (locked)**: frozen «ладно», «хорошо», «давай» join
  `logicalFocusStopwords` (`Proposition/Focus.hs`) — same
  single site as ага/угу. Frame-layer echoes untouched.
- **Expected**: fresh turns → `bestTopic=""` + topic-less hold;
  after content → carried topic continues. In-sentence uses
  («свобода это хорошо», «давай порассуждаем…») resolve focus
  from remaining candidates — suite verifies no pin breaks.
- **Bar**: unit pins — all three rejected by
  `isFocusCandidate`, `extractFocusEntity` empty on bare
  forms, covered topics unaffected; live — fresh trio
  topic-less with `bestTopic=""`, continuity battery keeps
  свобода, greeting + contact + definitional controls
  unchanged; crisis + speculative controls; zero new failures
  in unit/fast/core.
- **Out of scope**: «понятно» (anomaly-refusal-linked — the
  refusal surface fires with best=понятно; whether the refusal
  depends on focus candidacy needs its own analysis, separate
  landing); paradigms data; `isFallbackTopic` (trio stays
  not-fenced).

---

# Consent-marker focus exclusion (ладно/хорошо/давай) — landed (2026-10-03)

- **Rule** (pre-registered above): frozen «ладно», «хорошо»,
  «давай» in `logicalFocusStopwords` (`Proposition/Focus.hs`)
  — same single site as ага/угу. Frame-layer echoes untouched.
- **Probe**: fresh trio → `bestTopic=""` with the topic-less
  hold; continuity battery (свобода?→ладно→хорошо→давай) keeps
  свобода throughout. Greeting + contact + definitional
  controls unchanged; crisis control (bounded surface,
  resources) and speculative probe coherent.
- **Verification**: unit 1685, fast 1829, core 1200 green.
  New pin: `testConsentMarkerFocusExclusion`. In-sentence uses
  («свобода это хорошо», «давай порассуждаем…») cause zero pin
  breakage — focus resolves from remaining candidates.
  Infra note: post-restart re-verification from scratch.
  Residuals: «понятно» (anomaly-refusal-linked, separate
  analysis); «так»/«вот»; paradigms data.

---

# «понятно» focus exclusion — pre-registration addendum (2026-10-03)

- **Analysis (read-only, operator-approved)**: the Unclassifiable
  gate reads `tiBestTopic` (covered-check), never
  `ipfFocusEntity` directly — excluding «понятно» changes the
  gate's input, not the gate. Interaction is narrow and pinned:
  fresh «понятно» still refuses (best="", uncovered, nothing to
  acknowledge — refusal appropriate); «понятно» after content
  stops refusing and continues the carried topic (fixes the
  misfire: user signals understanding, system claimed not to
  understand). No suite pin references «понятно» anywhere.
- **Rule (locked)**: frozen «понятно» joins
  `logicalFocusStopwords`, same site. Frame echoes untouched.
- **Bar**: unit pins (rejection + empty entity + covered
  control); live — fresh «понятно» refuses with `bestTopic=""`,
  post-content «понятно» continues свобода, trio + controls +
  crisis + speculative unchanged; zero new failures unit/fast/core.

---

# «понятно» addendum outcome — rule insufficient, reverted (2026-10-03)

- **Live probe FAILED the bar**: fresh and post-content
  «понятно» still carry `bestTopic="понятно"` with the refusal
  surface. The stopwords rule is vacuous here: «понятно»
  reaches `bestTopic` via `atomFocus` (prepare-phase
  lexical/structural atom findings over the input carry the raw
  token), bypassing `ipfFocusEntity` entirely. The unit pin
  (`extractFocusEntity == ""`) passed while live behavior stood
  still — pins without live effect are not landed.
- **Reverted**: «понятно» out of `logicalFocusStopwords`, pin
  extension rolled back to the trio. Working tree behavior for
  «понятно» is byte-identical to the consent landing.
- **True mechanism recorded**: the atom path
  (`buildAtomSetFromFindings` → `extractObjectFromAtom` →
  `atomFocus`, `Effects.hs`) carries raw-token atoms into
  topic candidacy. Fixing it means atom-path surgery under the
  admission-pin regime (`twoBranchChecks` equivalence) — a
  separate pre-reg with its own audit, not a stopwords line.
  The refusal-interaction analysis above still stands for that
  landing: the gate reads `tiBestTopic`, so any future fix
  must pin fresh-refuses vs post-content-continues.

---

# Per-cause recovery leads — pre-registration (2026-10-03)

- **Fact (audited)**: `renderLocalRecoverySurfaceRu/En` receive
  the cause but ignore it — surfaces key by strategy only.
  Collisions: NarrowScope ← {ShadowDivergence,
  RuntimeDegraded}, ExposeUncertainty ← {ShadowUnavailable,
  LowLegitimacy}, SafeRecovery ← {ConatusGate, RenderBlocked}.
- **Rule (locked)**: two cause-specific leads, operator-approved
  wordings (RU + EN mirrors); all other pairs keep strategy
  text byte-identical. No jargon leak (no Conatus/energy/shadow
  internals; "проверочный контур" / "часть проверок" are new
  plain-language phrasings, operator-approved, not prior art).
  Wiring: thread the already-passed cause into both renderers.
- **Bar**: unit matrix pins — the two refined pairs render the
  new leads, all other cause×strategy pairs render legacy text
  (exhaustive over the ladder's proximate pairings);
  live — degraded-mode turn renders the RuntimeDegraded lead
  (that cause fires in degraded sessions), contact/define
  controls unchanged; crisis control; zero new failures in
  unit/fast/core.
- **Out of scope**: remaining 8 causes (strategy text already
  honest; distinction lives in trace); ShadowUnavailable live
  forcing (pins only); jargon surfaces; retry promises.

---

# Per-cause recovery leads — landed (2026-10-03)

- **Rule** (pre-registered above + one honesty correction):
  two cause-specific leads (RU + EN mirrors) for
  RuntimeDegraded+NarrowScope and ShadowUnavailable+
  ExposeUncertainty; the `cause` already passed into both
  renderers is now consumed. Correction en route: the pre-reg
  called the new phrasings "established" — they are not prior
  art, fixed to "new plain-language phrasings,
  operator-approved" before implementing.
- **Probe**: degraded contentless/contact turns render the new
  lead (`rec=runtime_degraded`); definitional content, crisis
  surface (resources intact) and speculative probe unchanged.
- **Verification**: unit 1686, fast 1829, core 1200 green.
  New pins: cause×strategy matrix (`Rescue`, 13 assertions
  incl. EN mirrors); one expected delta triaged — the degraded
  protocol pin now asserts the new lead verbatim.
  Residuals: remaining 8 causes (trace-level distinction);
  ShadowUnavailable live forcing; retry-promise doctrine
  untouched.

---

# Dictionary expansion batch-4 (cluster scope) — pre-registration (2026-10-04)

- **Trigger**: coverage audit (2026-10-03, read-only): 136
  `definitionCorpus` keys vs cluster-gold noun lemmas
  (repo-lemmatized, nouns only). 14 frequent cluster nouns
  missing; top-12 by frequency form this batch
  (решение/привычка, tied at 4, deferred to next batch for a
  clean frequency cut). Metaphorical one-offs (якорь, дверь,
  камень) and off-cluster nouns (город) excluded by rule.
- **Scope compliance**: all 12 inside the freedom cluster
  (ADR-0054 §2.7 freeze respected — no out-of-cluster growth).
- **Rule (locked)**: `definitionCorpus` 136→148, 2 predicates
  (prop/rel + EN gloss) per topic, texts operator-approved
  verbatim; GF lexemes via `add_gf_lexemes.py` (decline();
  masculine-consonant and neuter-ие paths already cover this
  set — verified before running); grammar abstract/Rus/Eng +
  PGF recompile (`compile_gf_grammar.sh`); SQL seed +
  Generated.hs via the lexicon pipeline (no concurrent
  export/hand-edits); Agda witness re-record
  (`--write-agda-witness`) per the lexicon doctrine; no
  weights, no code, no thresholds.
- **Bar**: lib clean; unit/fast green (pins hold despite 12 new
  graph nodes); Agda green with re-recorded witness; live —
  «что такое X?» renders the approved predicates verbatim for
  all 12 (any overlay-preference delta triaged: selection
  working, not a defect); zero new failures in unit/fast/core.
- **Out of scope**: решение/привычка (next batch);
  out-of-cluster topics (ADR freeze); paradigms data beyond
  what decline() covers (lexicon loop owns it); weights.

---

# Dictionary batch-4 amendment: вина nominative override (2026-10-04)

- **Defect (proven live)**: «что такое вина?» → `bestTopic="вино"`.
  `mdNominative` (Resources/Morphology.hs) is a broad
  surface→lemma index over every stored form with last-wins
  ordering; alphabetically вино follows вина, so the oblique
  reading (gen.sg of wine) beats the nominative (guilt).
  Frame layer is correct (`ipfFocusEntity=ipfFocusNominative=
  subj=вина` pinned by diag); the corruption happens in
  production `toNominative` over the real morphology
  (fixtures use empty morph → passthrough, hence green).
- **Rule (locked)**: frozen single-surface override
  вина→вина consulted first in `toNominative`
  (`Lexicon/Inflection.hs`; precedent: hush-final дождь
  override). A global nominative-preference flip (306
  surfaces) is explicitly out of scope — separate landing
  with per-flip audit.
- **Bar**: unit pin (override fires; unknown surfaces pass
  through); live — «что такое вина?» carries `bestTopic=вина`
  with guilt content; nominative controls («что такое вино?» —
  must stay вино) unchanged; zero new failures unit/fast/core.

---

# Dictionary batch-4 — landed (2026-10-04)

- **What** (pre-registered + one amendment): `definitionCorpus`
  136→148, 12 cluster topics with operator-approved verbatim
  predicates; 4 SQL provenance inserts (the rest pre-existed);
  export regen (only `lexicon_quality.json` moved — all other
  artifacts already carried the forms); 6 Eng-concrete
  hand-appends with senior-gloss dedupe (intent/pact/promise/
  refusal/aftermath/deed); PGF recompiled (binary legitimately
  identical — Syntax PGF does not embed LexiconEng; manifest
  source-hash updated); Agda untouched (no re-record needed).
- **Triage**: 7 topics render verbatim corpus predicates; 5
  (намерение/ограничение/риск/договор/вина) prefer overlay
  predicates from `curated_predicates.jsonl` — coherent,
  hypothesis-marked, selection working per the дождь
  precedent, not a defect. Real defect found and fixed:
  вина→вино (amendment above + frozen override + live spot).
- **Infra notes**: cold starts after rebuild can exceed 90–180s
  (page cache; warmed runs fast) — size turn timeouts
  accordingly. First two live probes timed out cold; no code
  defect.
- **Verification**: lib clean, export --check green, unit 1687,
  fast 1830, core 1201 green. Agda not re-run (no Agda inputs
  changed).

---

# Dictionary expansion batch-5 — pre-registration (2026-10-05)

- **Trigger**: batch-4 leftovers + next frequency tier
  (same audit method). 12 topics: решение, привычка, приказ,
  граница, просьба, давление, действие, разрешение, цель,
  спор, вседозволенность, демократия. Deferred: легитимность,
  выгода (most peripheral to freedom semantics; next batch).
  Excluded by rule (as in batch-4): metaphorical one-offs
  (якорь, пауза, клетка), off-cluster concretes (город, дверь,
  дорога), non-topic nouns (ничто, другой, завтра).
- **Scope compliance**: all 12 inside/adjacent the freedom
  cluster (ADR-0054 §2.7 freeze respected).
- **Rule (locked)**: same pipeline as batch-4 —
  `definitionCorpus` 148→160, 2 predicates (prop/rel + EN
  gloss) per topic, texts operator-approved verbatim; SQL
  provenance inserts only for lemmas missing from
  seed_ru_curated; export regen + --check; Eng-concrete
  hand-appends with senior-gloss dedupe; PGF recompile;
  Agda witness re-record ONLY if spec/*.agda moves; no
  weights, no code, no thresholds.
- **Known headwind (batch-4 finding)**: curated overlay may
  outrank new corpus predicates (~40% last batch) — triaged
  per the дождь precedent, not a defect; verbatim bar applies
  where corpus wins, coherence bar where overlay wins.
- **Bar**: lib clean; unit/fast green; live — «что такое X?»
  renders verbatim-or-coherent-overlay for all 12 with honest
  bestTopic (вина-class collisions triaged on sight);
  zero new failures in unit/fast/core.
- **Out of scope**: легитимность/выгода (next batch);
  out-of-cluster topics; overlay-vs-corpus precedence design
  (separate selection work); weights.

---

# Dictionary batch-5 amendment: спор nominative override (2026-10-05)

- **Defect (proven live, same class as вина)**: «что такое спор?»
  → `bestTopic="спора"`. Surface "спор" is NomSg of спор and
  GenPl of спора; last-wins alphabetical order resolves to
  спора. Overlay/verbatim triage otherwise clean (7 verbatim,
  5 coherent overlays; давление renders the physics sense —
  genuine ambiguity, honest hypothesis-marked rendering, noted
  not defected).
- **Rule (locked)**: extend the frozen override table with
  ("спор", "спор"). General 306-surface audit stays out of
  scope.
- **Bar**: unit pin extended; live — «что такое спор?» carries
  `bestTopic=спор`; zero new failures unit/fast/core.

---

# Dictionary batch-5 — landed (2026-10-05)

- **What** (pre-registered + one amendment): `definitionCorpus`
  148→160, 12 topics with operator-approved verbatim
  predicates (решение, привычка, приказ, граница, просьба,
  давление, действие, разрешение, цель, спор,
  вседозволенность, демократия). Lexicon: 4 SQL provenance
  inserts (8 lemmas pre-existed — an early grep with a wrong
  pattern briefly duplicated them; caught and removed before
  landing, forms verified identical); export regen
  (quality.json only); 5 Eng-concrete hand-appends with
  senior-gloss dedupe (habituation/directive/plea/doing/
  popular rule); PGF recompiled (binary identical, manifest
  updated); Agda untouched.
- **Triage**: 7 topics verbatim; 5 coherent overlays
  (давление renders the physics sense — genuine ambiguity,
  honest hypothesis-marked, noted not defected). Real defect
  found and fixed: спор→спора (same class as вина; frozen
  override extended, live spot green). Deferred: легитимность,
  выгода.
- **Infra notes**: post-restart re-verification from scratch;
  cold-start timeouts sized at 300s (page cache).
- **Verification**: lib clean, export --check green, unit 1687,
  fast 1830, core 1201 green.

---

# Dictionary expansion batch-6 (tail) — pre-registration (2026-10-05)

- **Trigger**: tail audit (same method): 160 keys vs cluster
  noun lemmas; 42 missing, mostly off-cluster concretes and
  generics. 12 taken: легитимность, выгода (batch-5
  deferrals), цена, гарантия, обязательство, контроль, норма,
  правильность, предательство, гордость, сила, путь (borderline:
  polysemous road/way — operator may veto for проверка).
  Excluded by rule: metaphorical one-offs, off-cluster
  concretes (птица, машина, вода, золото…), generics
  (дело, люди, начало, конец…), non-topics (есть, ничто…).
- **Scope compliance**: freedom-cluster/adjacent only
  (ADR-0054 §2.7 freeze respected).
- **Rule (locked)**: same pipeline — `definitionCorpus`
  160→172, 2 predicates (prop/rel + EN) operator-approved
  verbatim; SQL inserts only for lemmas missing from
  seed_ru_curated (обязательство, гордость — paradigms from
  funmap cross-check); export regen + --check; Eng hand-appends
  with senior-gloss dedupe; PGF recompile; Agda re-record ONLY
  if spec/*.agda moves; no weights, no code, no thresholds.
- **Known headwind**: overlay may outrank corpus predicates —
  triaged per precedent; verbatim bar where corpus wins.
- **Bar**: lib clean; unit/fast green; live — «что такое X?»
  verbatim-or-coherent-overlay for all 12 with honest
  bestTopic (collision-class triaged on sight); zero new
  failures unit/fast/core.
- **Out of scope**: remaining tail (next batch or never —
  value per topic falls); overlay precedence design; weights.

---

# Dictionary batch-6 (tail) — landed (2026-10-05)

- **What** (pre-registered above): `definitionCorpus` 160→172,
  12 topics with operator-approved verbatim predicates
  (легитимность, выгода, цена, гарантия, обязательство,
  контроль, норма, правильность, предательство, гордость,
  сила, путь). Lexicon: only 2 SQL inserts needed
  (обязательство, гордость — paradigms from funmap); export
  regen (quality.json only); 8 Eng-concrete hand-appends with
  senior-gloss dedupe (benefit/valuation/guarantee/checking/
  precept/rightness/betrayal/might); PGF recompiled (binary
  identical, manifest updated); Agda untouched.
- **Triage**: 4 topics verbatim; 8 coherent overlays
  (контроль carries mixed-language "plans" inside the overlay
  text — curated-overlay quality note, not this batch;
  давление renders the physics sense — genuine ambiguity,
  honest hypothesis-marked). bestTopic honest everywhere
  (обязательство empty via pre-existing deontic stopword —
  response correct through the intent path; recorded, not
  defected). No collision-class defect in this batch.
- **Verification**: lib clean, export --check green, unit 1687,
  fast 1830, core 1201 green.

---

# «понятно» atom-path — pre-registration (2026-10-05)

- **Mechanism (proven by audit)**: «понятно» has no
  что/как/почему/? marker → zero structural atoms; the
  `atomFocus` comes from a lexical-cluster match carrying the
  raw token. So «понятно» reaches `bestTopic` through TWO
  links: `ipfFocusEntity` (length ≥ 3 passes candidacy) and
  `atomFocus` (no candidacy check at all). The reverted
  stopwords attempt cut only the first — vacuous by
  construction. Any complete fix must cut both.
- **Rule (locked), two parts**:
  - (1) «понятно» rejoins `logicalFocusStopwords`
    (entity link; same site as the trio).
  - (2) New total pure `focusCandidateOrEmpty`
    (`Proposition/Focus.hs`, tested) applied to `atomFocus`
    in the Effects `focus`/`bestTopic` computation ONLY
    (`conceptToCheck` untouched — the constitutional check
    keeps working on raw atoms). Legitimate atom focuses
    (content nouns passing candidacy) flow unchanged; only
    the contentless class filters to "".
- **Anomaly interaction (from the addendum, still binding)**:
  fresh «понятно» still refuses (best="" uncovered);
  post-content «понятно» continues the carried topic.
- **Bar**: unit pins — stopwords rejection + empty entity
  (re-landed) + `focusCandidateOrEmpty` (понятно→"",
  свобода→свобода, ""→""); live — fresh refuses with
  `bestTopic=""`, post-content continues свобода,
  trio + controls + crisis + speculative unchanged;
  zero new failures in unit/fast/core.
- **Out of scope**: global 306-surface audit; `conceptToCheck`
  filtering; paradigms data.

---

# «понятно» atom-path — landed (2026-10-05)

- **Rule** (pre-registered above, both links cut): «понятно»
  rejoins `logicalFocusStopwords` (entity link) + new total
  `focusCandidateOrEmpty` (`Proposition/Focus.hs`) applied to
  `atomFocus` in the Effects focus computation only
  (`conceptToCheck` untouched — constitutional check keeps raw
  atoms). Re-exported through `Proposition` for pins/tests.
- **Probe**: fresh «понятно» refuses with `bestTopic=""`;
  post-content «понятно» continues свобода (anchor hold
  naming the carried topic — honest continuity). Trio,
  greeting, contact, definitional controls unchanged; crisis
  (resources intact) and speculative probe coherent.
- **Verification**: unit 1687, fast 1830, core 1201 green.
  New pins: stopwords/entity/atom-link coverage for понятно +
  `focusCandidateOrEmpty` passthrough/empty cases.
  The fallback-topic program is now complete: no path —
  frame, focus-entity, atoms — invents topic nouns.

---

# Intent-topic carry override — pre-registration (2026-10-05)

- **Defect (proven live, harvest live-0273)**: «что такое
  обязательство?» (after давление) renders the right
  predicate but carries `bestTopic=давление`. Focus links are
  all empty (обязательство is a deontic stopword) so the chain
  falls to `ssLastTopic`. Carry is correct for acknowledgements
  but wrong on explicit topic-setting questions — follow-up
  threading then continues the wrong topic.
- **Audit**: `SemanticIntent` (Intent/Classifier) is NOT
  available in Prepare/Effects (only the geometric classifier
  is); ResponsePlan classifies later. M6.1 forbids
  post-hoc `tiBestTopic` overrides downstream — the fix belongs
  in Effects, which has `input` + `ssMorphology` but needs
  `Intent.Features` threaded in (new dependency; same pure
  function + same inputs as the later call → identical
  verdicts, pinned by equality).
- **Rule (locked)**: classify intent in Prepare; override ONLY
  the pure-carry case (nom/entity/atom links all empty) AND
  normalized intent topic covered non-fallback AND intent ∈
  {Define, Distinguish} (the only acts normalizeIntentTopics
  touches — F2 doctrine). Contact/challenge/generative and all
  resolved focuses byte-identical.
- **Bar**: unit pins — Define intent extraction, carry
  preserved for non-Define acts and for resolved focuses,
  Prepare/ResponsePlan verdict equality; live —
  обязательство-definitional carries обязательство,
  понятно/ага/ну continuity unchanged, fresh empties
  unchanged, controls + crisis + speculative unchanged;
  zero new failures in unit/fast/core.
- **Out of scope**: M6.1 violation (no downstream override);
  deontic-stopword removal; paradigms data.

---

# Intent-topic carry override — landed (2026-10-05)

- **Rule** (pre-registered above): `semanticIntentForRender`
  moved verbatim to `Intent.Classifier` (Route/Render
  re-exports it — zero import churn for tests); new total
  `resolveCarryTopic` overrides ONLY the pure-carry case
  with an explicit covered Define/Distinguish topic;
  Effects computes the same call as render stage (same
  function, same inputs — verdict equality by construction).
  `conceptToCheck` untouched.
- **Probe**: обязательство after давление carries
  обязательство; ну/ага/понятно continuity, fresh empties,
  greeting/contact/definitional controls, crisis (resources)
  and speculative probe all unchanged.
- **Verification**: unit 1693, fast 1830, core 1201 green.
  New pins: `carryOverrideTests` (6 assertions).

---

# 306-audit: душ/метод/логик nominative overrides — pre-registration (2026-10-06)

- **Audit (read-only)**: 306 surfaces flip under a global
  nominative-preference; only 7 can actually become topics
  (corpus/cluster intersection); of those, спор is fixed and
  вод/машин/техник are never bare topics (oblique-only
  forms). Three genuine defects remain, all proven live:
  «душ»→душа (worst: renders SOUL content for a SHOWER
  question), «метод»→метода (trace-level; content correct
  via intent path), «логик»→логика (same class, probe
  post-fix).
- **Rule (locked)**: extend the frozen override table with
  ("душ","душ"), ("метод","метод"), ("логик","логик").
  Post-fix «душ» becomes uncovered-honest (hold/abstain,
  no soul content). Global flip stays out of scope.
- **Bar**: unit pins extended (3 pairs + душа/логика/метода
  controls); live — душ/метод/логик carry their own topics,
  душа/логика controls unchanged, crisis control;
  zero new failures in unit/fast/core.

---

# 306-audit overrides (душ/метод/логик) — landed (2026-10-06)

- **Rule** (pre-registered above): frozen table extended with
  three pairs. Audit result: 306 surfaces flip globally, but
  only 7 can become topics; спор fixed earlier, вод/машин/
  техник never bare topics. This landing closes the
  topic-relevant set (вина/спор/душ/метод/логик).
- **Triage**: душ content stays душа-compositional (governed
  neighbor composition over shared atoms, hypothesis-marked —
  designed uncovered behavior, not a misresolution); метод
  content was already correct via intent path; логик renders
  логика overlay with honest bestTopic. Fixed layer is
  bestTopic/threading only, as barred.
- **Verification**: unit 1693, fast 1830, core 1201 green.
  New pins: 3 override pairs + душа control.

---

# Curated-quality surgery — pre-registration (2026-10-07)

- **Audit (read-only)**: 83 RU-topic rows in
  `curated_predicates.jsonl` carry mixed-language fragments
  (EN/PT/PL/IT/CN/JP shards, latin-in-cyrillic typos). Legit
  technical tokens (USB/HTML/Wi-Fi/LIFO/XX века/a + bi/2πr)
  explicitly excluded. EN-topic bulk out of scope (separate
  corpus, separate landing).
- **Rule (locked), two tiers**:
  - Mechanical (~70 rows): unambiguous typo/fragment
    completion (mobilizes→мобилизует, plans→планов,
    artefacts→артефакты, tenniS→теннис, 负ativных→
    негативных, 共→общим, 自然→естественные, etc.).
    Scripted edits, diff-reviewed; no row deleted, no topic
    renamed (except row 57's `_loc` slot leak, fixed to the
    plain topic).
  - Flagged (~10 rows): ambiguous reconstructions
    (утыkanie, marathon, producción, gases, утыkanie…),
    decided per-item by the operator before landing.
- **Pins/bar**: exact-match pins on the live-observed row
  (контроль/plans→планов) + a sample of repaired rows;
  `loadCuratedPredicates` still parses all rows (strict
  decoder — any botched edit fails loudly); CuratedPredicates
  suite green (topic presence/predicate counts untouched);
  live spot — «что такое контроль?» renders планов;
  zero new failures in unit/fast/core.
- **Out of scope**: EN-topic bulk; 1009 duplicate topics
  (last-wins silent loss — recorded as separate data issue);
  overlay precedence; weights.

---

# Stage-1 Batch A: verdict taxonomy + fuel signal — pre-registration (2026-10-07)

- **Defect (verified in code)**: `Verdict.NotEntailed` is
  payload-free (`IREval.hs`); `forwardChain` does not report
  fuel exhaustion; and `Verdict` is constructed nowhere except
  one JSON round-trip pin — runners return `Bool`, so the
  taxonomy is decorative.
- **Rule (locked)**:
  - `Verdict` gains `Refuted [ProofStep]` and
    `NotEntailed SearchBoundary` with
    `SearchBoundary = OpenWorldMissingFacts | FuelExhausted
    FuelReport | UnsupportedPredicate` (all with ToJSON/
    FromJSON; old traces contain no verdicts, so no migration).
    `AmbiguousInterpretation` explicitly DEFERRED (needs
    interpretation-alternative plumbing — Batch D/E).
  - New `forwardChainFuel` returns the fuel outcome
    (fixpoint vs exhausted + fuel used); `forwardChain` stays
    as a compatible wrapper (zero churn for existing callers).
  - New pure `entailmentVerdict :: Int -> [StrictRule] ->
    [Proposition] -> Proposition -> Verdict` in IREval:
    entailed → `Entails`; negation entailed → `Refuted`;
    fuel exhausted → `NotEntailed (FuelExhausted _)`; query
    predicates outside the rules+facts inventory →
    `NotEntailed UnsupportedPredicate`; else `NotEntailed
    OpenWorldMissingFacts`.
  - `IREval.Batch` gains verdict runners; `ExitTrace` gains
    nullable `etVerdict` (schema v2 note in the landed entry;
    old fields kept). Defeasible maps to
    `Entails []`/`DefeatedBy`; conflicts to `Conflict`.
    Emitter re-run shows verdicts per task.
- **Bar**: unit pins — refuted vs open-world vs fuel-exhausted
  vs unsupported (4+ cases), JSON round-trips, fuel-signal
  unit (fixpoint vs exhausted), emitter aggregates unchanged
  (17/17, 12/12, 6/6, 6/6, 40/40) + verdicts present on all
  strict traces; zero new failures in unit/fast/core.
  Slow NOT warranted (shadow-only, no runtime readers).
- **Out of scope**: `AmbiguousInterpretation`; render rules
  (Batch B); composition (Batch C); runtime wiring (non-goal).

---

# Stage-1 Batch A: verdict taxonomy — landed (2026-10-07)

- **What** (pre-registered above): `Verdict` gains `Refuted`
  and `NotEntailed SearchBoundary` (OpenWorld/FuelExhausted/
  Unsupported; Ambiguous deferred); `forwardChainFuel` with
  dry-round exhaustion signal (`forwardChain` wraps it,
  zero churn); pure `entailmentVerdict` (entails → negation →
  unsupported → fuel → open-world); Batch verdict runners +
  `etVerdict` on traces (schema v2; defeasible →
  Entails[]/DefeatedBy, conflicts → Conflict, duels/
  presuppositions → null by design).
- **Measured**: aggregates unchanged (17/17, 12/12, 6/6, 6/6,
  40/40); verdicts present on all strict/single/conflict-
  found traces. No Refuted/Fuel/Unsupported in exit data
  (authored tasks don't cover those paths) — covered by
  synthetic pins instead.
- **Corrections en route**: (1) fuel pin used in-order rules
  that `foldl'` chains within one round — reversed order
  genuinely starves (documents a fuel-semantics footgun for
  rule authors); (2) missing paren (parse error, caught by
  build); (3) anti-rot pin allowlist needed runtime/Type-C/
  HDMI/2πr additions after it caught 3 legitimate terms.
- **Verification**: unit 1695, fast 1831, core 1201 green.
- **Also landed here**: curated-quality surgery (72 fixes +
  2 deletions + 1 gloss-guided repair, pre-registered above;
  exact-match pin on контроль + whole-file anti-rot pin).

---

# Stage-1 Batch B: status doctrine + leak ban — pre-registration (2026-10-07)

- **Audit (read-only)**: claim modes exist
  (Known/Interpretive/Hypothetical/Question/Unknown);
  Hypothesize renders "Гипотеза"-headed, GenerateThesis
  "Тезис"-headed with hypothetical mode + hypothesis suffix;
  abstain fallbacks exist (NoTopic/NotCovered/NoPredicate/
  ConflictingEvidence/QualityRejected + empty-claims hold).
  Commitments derive from user frames, stances from
  challenges — system hypotheses have no intake path into
  either store. The leak surface is render marking +
  future cutover, not storage.
- **Rule (locked)**:
  - New `EvalStatus = StatusGrounded | StatusRefuted |
    StatusHypothesis | StatusAbstain` (shadow, IREval) +
    total `statusOfVerdict` (Entails→Grounded,
    Refuted→Refuted, everything else→Abstain: defeated,
    conflicted, open, starved and unsupported queries
    never assert).
  - Pure render contract `renderStatusSurface`
    (RU, no callers): per-status templates; Abstain reuses
    the established honest-abstain phrasing, Hypothesis
    requires explicit marking + no fact-recording claim.
  - Leak-ban pin (anti-rot on current behavior):
    Hypothesize/GenerateThesis plans render with Гипотеза
    marking (headline or suffix); GenerateThesis never
    renders bare-categorical.
  - Doctrine text (this report + code comments):
    abstain-vs-hypothesize rules mirroring the fallback
    reasons; hypothesis never enters strict proof, never
    recorded as fact, never upgraded at render,
    disputable/replaceable.
- **Bar**: unit pins — status mapping (7+ cases), all four
  render templates, marking invariant on built plans;
  JSON round-trips; zero new failures in unit/fast/core.
  Slow NOT warranted (shadow-only).
- **Out of scope**: runtime render changes (surfaces
  unchanged); trace schema (status derives from verdict);
  AmbiguousInterpretation; cutover (later decision).

---

# Stage-1 Batch B: status doctrine + leak ban — landed (2026-10-07)

- **What** (pre-registered above): `EvalStatus`
  (Grounded/Refuted/Hypothesis/Abstain) + total
  `statusOfVerdict` (only `Entails` asserts) + pure
  `renderStatusSurface` (RU, no callers by law) in IREval;
  `claimModeFor` exported for pins; leak-ban data pin
  (hypothetical goals never produce Known claims).
  Audit finding recorded: Hypothesize renders Гипотеза-headed,
  GenerateThesis Тезис-headed with hypothetical mode +
  suffix; commitments derive from user frames and stances
  from challenges — no storage intake for system
  hypotheses. Suffix marking is Route-level (live-probed,
  future cutover enforces).
- **Verification**: unit 1697, fast 1831, core 1201 green.
  New pins: status mapping (7), render templates (4),
  claim-mode totality. Infra: post-restart re-verification
  from scratch.

---

# Stage-1 Batch C: typed composition — pre-registration (2026-10-07)

- **Gap (audited)**: shadow Stage-1 has NO composition —
  rules are flat, scenarios use file rules only. (Runtime
  `composeFromActivation` exists but is out of scope —
  different layer, untouched.) Primitives/senses/rules do not
  combine into novel derivations.
- **Rule (locked)**: new shadow module `QxFx0.Semantic.IRCompose`
  (no pipeline callers). Composition compiles DOWN to strict
  rules so Batch A verdicts apply unchanged:
  - `CompositionDef`: id, base rule refs, added premises/
    conclusions, BLOCKED conclusions (not-entails list),
    role bindings.
  - `expandComposition`: inherits base conclusions, adds new
    ones, NEVER emits blocked ones (blocking enforced at
    expansion, not by post-filter).
  - Role compatibility (bound roles consistent across base
    + additions), scope preservation (quantifier/modal
    wrappers carried intact), conflict propagation (base
    conflict with additions surfaces via `detectConflict`
    on the expansion, not silently).
  - Domain composites as DATA (new `compositions.jsonl`,
    additive); operators in CODE. Batch C ships generic
    operators + synthetic test composites only; ownership
    domain data waits for Batch E.
- **Bar**: unit pins — TemporaryTransfer-shaped example
  (entails holder + obligation, NOT-entails ownership),
  inheritance, blocking (blocked conclusion absent even when
  base would derive it), role-mismatch rejection, scope
  preservation, conflict propagation; JSON round-trips;
  exit aggregates unchanged (no exit-data changes);
  zero new failures in unit/fast/core. Slow NOT warranted
  (shadow-only).
- **Out of scope**: runtime composition; ownership domain
  data (Batch E); learning (separate ADR); cutover.

---

# Stage-1 Batch C: typed composition — landed (2026-10-07)

- **What** (pre-registered above): new shadow module
  `QxFx0.Semantic.IRCompose` (operators in code) +
  `compositions.jsonl` file support in Batch (domain data
  mechanism, 2 abstract machinery rows) + pins. Composition
  compiles down to strict rules; Batch A verdicts apply.
- **Corrections en route**: (1) the withheld-ownership pin
  exposed that blocked conclusions leave the theory's
  vocabulary — `UnsupportedPredicate`, not open-world
  (pinned both precisely: withheld→Unsupported, third-party
  in-vocabulary→OpenWorld; blocked is absence, never
  refutation); (2) fuel pin used in-order rules that `foldl'`
  chains in one round — reversed order genuinely starves
  (same footgun as Batch A, now pinned twice).
- **Measured**: exit aggregates unchanged (17/17, 12/12, 6/6,
  6/6, 40/40 — no exit-data changes).
- **Verification**: unit 1703, fast 1831, core 1201 green.

---

# Stage-1 Batch D: generic state-transition engine — pre-registration (2026-10-07)

- **Gap**: shadow Stage-1 evaluates timeless rule bases; no
  notion of state, change, persistence, or derivation
  lineage. Batch C composes rules; nothing applies events
  over time.
- **Rule (locked)**: new shadow module
  `QxFx0.Semantic.IRState` (no pipeline callers).
  Event-sourced design (state = fold over events, so
  correction = replace event + refold — no incremental TMS):
  - `FluentState`: time-indexed fluent sets (`AtTime`-tagged
    propositions; times are opaque ordered labels).
  - `EventSpec`: id, preconditions (checked against
    pre-state, `Left` on violation), withdraws, asserts,
    time advance.
  - Frame axiom: fluents persist across events unless
    withdrawn or contradicted (structural negation).
  - Lineage: every derived fluent carries its support
    (event id + kind: asserted/persisted/derived) —
    the Explain substrate (Batch A proofs + this lineage =
    full dependency objects).
  - `reviseHistory`: replace one event, refold; dependent
    fluents recomputed, independent ones byte-identical
    (pinned).
  - Domain contracts as DATA wait for Batch E; Batch D pins
    use abstract fluents/events (holds/owes style).
- **Bar**: unit pins — apply/withdraw/persist/contradict,
  precondition violation, lineage query (why does F hold at
  t2), revision by replacement (dependents change,
  independents identical), time advance; JSON round-trips;
  exit aggregates unchanged; zero new failures in
  unit/fast/core. Slow NOT warranted (shadow-only).
- **Out of scope**: ownership domain (Batch E); learning;
  runtime wiring; cutover.

---

# Stage-1 Batch D: state-transition engine — landed (2026-10-07)

- **What** (pre-registered above): new shadow module
  `QxFx0.Semantic.IRState` — event-sourced histories
  (fold over events; correction = replace + refold),
  frame axiom with structural-contradiction revision,
  per-fluent support lineage (Explain substrate alongside
  Batch A proofs), time advance, JSON instances.
- **Corrections en route**: `Map TimeStep` JSON keys needed
  `ToJSONKey`/`FromJSONKey` newtype-deriving (caught by
  build). Domain data stays out (Batch E).
- **Verification**: unit 1709, fast 1831, core 1201 green.

---

# Stage-1 Batch E: ownership microworld — pre-registration (2026-10-07)

- **Gap**: Batch D engine has no domain; Batch C has no
  domain composites. Nothing applies known concepts in novel
  combinations end to end.
- **Rule (locked)**:
  - Data: `data/semantic_ir/ownership.jsonl` — contract
    library, 7 event templates (give/lend/return/take/show/
    steal/return-right) + ownership-exclusivity strict rule,
    all s-exprs, no times (scenario-bound in tests).
  - Code: file row type + pure converters in IRState
    (`toEventSpec`, `toOwnershipRule`); verdicts via Batch A,
    expansion via Batch C where composites apply, lineage
    via Batch D — the batches compose, nothing reimplemented.
  - Held-out tests (combinations NOT in the data file):
    give-vs-lend (Own moves vs persists+obligation),
    lend-vs-show (exclusive hold+obligation vs shared hold,
    none), take-vs-steal (wrongness fluent present/absent),
    return-object-vs-return-right, double-lend,
    return-without-lend (precondition rejection),
    lend-corrected-to-give revision demo (Own flips,
    obligation withdrawn, independents identical).
  - The user demo path verbatim: Lend → owner query →
    correction to Give → recompute (pinned step by step).
- **Bar**: unit pins — file decodes (7+1 rows), all held-out
  contrasts, demo path, exclusivity Refuted (not merely
  open); exit aggregates unchanged; zero new failures in
  unit/fast/core. Slow NOT warranted (shadow-only).
- **Out of scope**: learning (separate ADR); runtime wiring;
  cutover (next decision); new primitives.

---

# Stage-1 Batch E: ownership microworld — landed (2026-10-07)

- **What** (pre-registered above): `data/semantic_ir/
  ownership.jsonl` (7 event templates + borrower-not-owner
  strict rule) + file converters in IRState + held-out tests.
  Batches compose: verdicts (A), statuses (B), expansion (C),
  engine+lineage (D) — nothing reimplemented.
- **Design correction en route**: bare templates cannot bind
  fresh participants — instantiation takes an explicit
  environment (utterance-named bindings); silent existential
  introduction stays a data error. Precondition matching uses
  variable binding (same discipline as rule premises), which
  the pre-reg's "checked" always meant.
- **Measured**: the user demo path verbatim (Lend → owner
  query Refuted with proof → correct to Give → Own(B),
  obligation withdrawn, t0 identical); all minimal
  contrasts green (give/lend, lend/show, take/steal,
  return-object/return-right, double-lend rejects,
  lend-return-lend works).
- **Verification**: unit 1716, fast 1831, core 1201 green.

---

# Stage-1 trace review for gated cutover (2026-10-07)

- **Mechanical leg (measured today, emitter)**: strict 17/17
  (≥0.80 ✓ with margin), defeasible 12/12 (≥0.60 ✓),
  conflicts 6/6 exact ✓, presuppositions 6/6 exact ✓,
  scenarios 40/40 ✓. Zero false-authority by construction
  (stage1-shadow provenance on every trace; hypothesis
  marking + leak ban landed in Batch B).
- **Batches since the last review**: A (verdicts), B
  (statuses), C (composition), D (state engine), E
  (microworld) — all shadow-only, all green.
- **Human leg**: OPEN. Requires B2-style blind pairs on
  novel out-of-corpus freedom-cluster examples,
  operator-rated (coherent majority, zero false-authority,
  honest abstain allowed). Packet preparation is next;
  rating needs the operator.
- **Cutover decision**: NOT YET. Mechanical passes; human
  leg pending; cutover ADR writable only after both
  (ADR-0054 §2.5). No runtime wiring meanwhile (non-goal).

---

# Human leg (Stage-1 exit): packet rated, operator-confirmed (2026-10-07)

- **Packet**: `data/semantic_ir/human_leg_packet.jsonl`,
  20 novel out-of-corpus items (strict chains, refuted ×2,
  open-world, fuel-starved, unsupported ×3, defeasible
  fire/blocked, duel tie, conflict, presuppositions,
  composition ±, state query ±, revision, statuses ×2).
- **Machine verdicts** (temporary runner, deleted after use):
  01 Entails, 02 Unsupported, 03 Refuted, 04 Refuted []
  (given-negation, empty proof — honest), 05 Unsupported,
  06 OpenWorld, 07 FuelExhausted, 08 Unsupported, 09 fires,
  10 blocked, 11 tie-kept, 12 conflict found, 13 held+missing,
  14 Entails, 15 Unsupported (withheld leaves vocabulary),
  16 Entails [], 17 OpenWorld, 18 Entails [] post-revision,
  19 Grounded, 20 Abstain.
- **Operator verdict**: CONFIRMED (coherent 20/20, zero
  false-authority, no abstain cases needed — packet inputs
  all well-formed, recorded as coverage note).
- **Cutover decision**: mechanical PASS + human CONFIRMED.
  Cutover ADR is now writable (bounded domain, shadow-first
  comparison, explicit abstain doctrine). No runtime wiring
  in this landing.

---

# Cutover Stage 1: shadow-compare wiring — pre-registration (2026-10-07, ADR-0055)

- **Scope (locked)**: compute-only wiring, zero surface
  change. New pure module `QxFx0.Semantic.Ownership.Detect`
  (micro-grammar: 7 events over explicit mentions; pronouns
  and bare roles close the gate). New sub-record
  `trcOwnershipCompare :: Maybe OwnershipCompareTrace`
  (gate verdict + reason, detected events, verdicts, lineage
  refs; backward-compat Nothing; sub-record discipline).
  Computation in Finalize (ss+ti available); surfaces,
  plans, commitments, stances untouched.
- **Entity rule**: mentions resolve via morphology
  nominative; unresolvable → gate closed (abstain, logged).
  No guessing, no defaults.
- **Bar**: unit pins — all 7 detectors fire/decline,
  pronoun/bare-role closure, entity resolution,
  compare-record JSON round-trip; live — fixed gate battery
  (Batch E demo + all contrasts + 3 corrections +
  5 out-of-domain controls): gate fires exactly where
  specified, abstains elsewhere; IDENTICAL 15-turn battery
  re-run pre/post wiring diffed byte-identical surfaces
  (any delta triaged before landing); zero new failures in
  unit/fast/core; slow per discipline (live surfaces
  touched, even read-only — the binary changes).
- **Out of scope**: gated surfaces (Stage 2); runtime reads
  of verdicts (trace only); definitional path (untouched);
  cutover exit decision (after review).

---

# Cutover Stage 1 scope amendment (2026-10-07, before wiring)

- **Finding**: multi-turn histories (return, corrections,
  revision) need a session-scoped fluent journal — new
  persisted `SystemState` field with JSON + migration.
  That is state surgery, not compute-only wiring.
- **Split (locked)**: Stage 1a (this landing) = single-turn
  event application + verdicts (give/lend/take/show/steal
  with presupposed seed) + gate battery of single turns +
  out-of-domain controls. Stage 1b (separate pre-reg) =
  session journal + multi-turn (return/correction/revision)
  + the Batch E demo path live.
- **Bar unchanged otherwise** (pre-reg above), battery
  adjusted: 5 seedable events + 5 controls (no multi-turn
  claims in 1a).

---

# Cutover Stage 1a: shadow-compare wiring — landed (2026-10-08)

- **What** (pre-registered + one amendment): pure detectors
  (`Ownership.Detect`, 7 events, exactly-one-match +
  pronoun + parties discipline, canonical-order roles
  documented); `ssOwnershipLibrary` loaded at bootstrap
  (empty on failure; persisted backward-compat);
  `buildOwnershipCompare` in Prepare (trace-only;
  per-event party mapping take/steal swap; presupposed
  seed; borrower-rule verdict; lineage refs) carried
  `PrepareStatic` → `TurnInput` → `trcOwnershipCompare`
  sub-record (M6.1 respected).
- **Corrections en route**: (1) single-turn scope only —
  multi-turn needs the session journal (Stage 1b);
  (2) bootstrap path resolution (CWD-first, not bare
  `getDataFileName`); (3) seed role shapes must mirror
  library roles (arity mismatch found by live probe);
  (4) REAL regression caught by fast/core: derived-ToJSON
  wrote `foId` while manual FromJSON read `id` — session
  restore broke (14 fast errors + 6 core failures);
  manual ToJSON with file-schema keys + round-trip pin.
- **Measured**: gate battery 10/10 (5 fires with correct
  verdicts incl. live Refuted on lend, 5 abstains);
  10-turn surfaces byte-identical pre/post wiring.
- **Verification**: unit 1725, fast 1831, core 1201 green.

---

# Cutover Stage 1b: session journal + multi-turn — pre-registration (2026-10-07, ADR-0055)

- **Gap (audited)**: Stage 1a is single-turn; return,
  corrections and revision need cross-turn fluent memory.
- **Rule (locked)**:
  - Text journal (no structure persistence):
    `ssOwnershipJournal :: [OwnershipJournalEntry]`
    (event id + agent/recipient/object mentions + turn
    label), persisted backward-compat, empty default.
    Per-turn refold rebuilds EventSpecs from the library
    (deterministic given same morphology) — no EventSpec
    /Proposition persistence anywhere.
  - Prepare: journal non-empty → pre-state = refolded
    journal fluents (instead of presupposed seed); fired
    event appended; correction (below) replaces last entry.
    TurnInput carries the next journal (M6.1: computed once
    in Prepare); Finalize stores it. Surfaces, plans,
    commitments, stances untouched (still shadow-compare).
  - Correction detector (boring, pinned): contrast marker
    (" а ", "на самом деле", "точнее", leading "нет, ")
    + exactly one old-verb stem before / new-verb stem
    after the marker; else decline (gate closed, logged).
    Applies to the LAST journal entry only (documented).
  - Trace: `OwnershipCompareTrace` gains nullable
    `octHistoryDepth :: Maybe Int` + `octCorrected ::
    Maybe Bool` (sub-record discipline; old readers ignore).
- **Bar**: unit pins — journal refold identity, return and
  correction flows, correction-decline shapes, empty-journal
  fallback to presupposed seed, JSON round-trip of entries;
  live multi-turn battery (lend→return, lend→correction,
  lend→unrelated, empty-start controls): threading +
  verdicts correct, surfaces byte-identical pre/post;
  zero new failures in unit/fast/core; slow per discipline.
- **Out of scope**: gated surfaces (Stage 2); pronoun
  resolution in journal (explicit mentions only, unchanged);
  case-based roles (documented limitation stands); learning.

---

# Cutover Stage 1b amendment (2026-10-08, before landing)

- **Live finding 1**: return binds ?a wrong. The template's
  ?a is the prior-state holder (second mention), like
  take/steal — not the agent. Swap list extended to
  take/steal/return (prior-state-holder class).
- **Live finding 2**: fresh return (empty journal) computed
  then failed. Correct behavior is gate decline: return and
  return-right presuppose a prior event, and inventing
  history is worse than presupposing ownership. History-
  dependent events require a non-empty journal.

---

# Cutover Stage 1b amendment: proper-name paradigms (2026-10-08)

- **Live finding**: cross-turn coreference breaks on
  inflected proper names ("Боре" vs "Боря", "Аня" vs
  "Ане"): no paradigm entries exist, so `toNominative`
  passes surfaces through and structural identity fails.
  Same-turn turns work (consistent surfaces); multi-turn
  needs real lemmas.
- **Rule (locked)**: 6 frozen proper-name paradigms
  (Аня, Боря, Вера, Коля, Маша, Петя) via the lexicon
  pipeline (SQL seed + export + witness iff Agda moves).
  Uncovered names → compute-failed records (honest,
  logged); full proper-name coverage stays lexicon-loop
  work, out of scope.

---

# Cutover Stage 1b: session journal + multi-turn — landed (2026-10-08)

- **What** (pre-registered + two amendments): text journal
  (`ssOwnershipJournal`, persisted backward-compat);
  per-turn refold in Prepare (TurnInput carries next
  journal, Finalize stores; M6.1 respected); correction
  detector (explicit/implicit contrast, last-entry only);
  history-dependent decline (return/return-right need a
  journal); trace depth/corrected fields.
- **Amendment 2 (lexicon)**: cross-turn coreference needs
  real name lemmas — 6 frozen proper-name paradigms via
  surgical `paradigms.json` inserts + 3 analyzed collisions
  into `KNOWN_FBS_COLLISIONS` (вина precedent). Two data
  fixes en route: instrumental Борей (not Бореем),
  lowercase form convention (parity ratchet caught both).
  Agda re-verified on changed files, witness re-recorded,
  PGF recompiled (binary identical).
- **Measured**: lend→return (depth 2, OpenWorld — no
  exclusivity axiom, honest), lend→correction→give
  (Entails, depth 1), lend→unrelated (no record),
  fresh return declines. Surfaces: no render code touched
  (structural); pre-wiring baseline file lost to a server
  restart, substituted by the matrix's exact-surface pins
  (all green) + 10-turn gate battery shapes unchanged.
- **Known limitation (follow-up)**: the journal never
  expires — a much-later ownership turn inherits ancient
  history. Scoping/expiry is Stage 2 or later work.
- **Verification**: unit 1729, fast 1831, core 1201 green.

---

# Shadow-compare review for Stage 2 (ADR-0055, 2026-10-08)

- **Battery**: 10-turn gate battery + 2 multi-turn sessions
  (lend→return, lend→correction), re-run live on HEAD.
- **Attribution**: legacy surfaces on gated inputs are
  mirror holds asserting NOTHING about ownership relations;
  IR verdicts (Entails on give, Refuted on lend, OpenWorld
  post-return, Entails post-correction) answer questions
  legacy never asks. ZERO contradictions found.
- **One expositional divergence (out of gate)**: душ renders
  душа-compositional content (hypothesis-marked, governed
  neighbor composition — designed uncovered behavior).
  No ownership verb fires there; Stage 2 would not engage;
  recorded, not blocking.
- **Review verdict**: zero unattributed divergence. Stage 2
  (gated surfaces) may proceed to pre-registration.

---

# Cutover Stage 2: gated surfaces — pre-registration (2026-10-08, ADR-0055)

- **Scope (locked)**: on gated turns with successful IR
  computation, the base content surface renders from derived
  fluents through operator-approved RU templates (below);
  crisis/anomaly/recovery surfaces keep precedence; all
  tails/suffixes preserved. Compute-failed or unfired gate
  → legacy surface (abstain-first). EN inputs never fire
  (detectors are RU) → legacy by construction.
- **Rule**: new pure `renderOwnershipSurface` (Route/Render,
  status via Batch B mapping over the trace verdict tag):
  fluent verbalization with morphology case forms
  (genitive/dative/accusative from paradigms); no new claims
  beyond derived fluents (leak ban); operator wordings
  verbatim (approved next).
- **Bar**: unit pins — verbalizer per event (7) + status
  routing + fallback preservation; live — fixed 10-turn
  battery renders the approved surfaces verbatim, correction
  and multi-turn included, controls/crisis/spec unchanged;
  trace carries status; zero new failures in unit/fast/core;
  slow (surfaces change by design).
- **Out of scope**: EN templates; journal expiry; case-based
  roles; learning; domain widening (follow-up ADR).

---

# Cutover Stage 2: gated surfaces — landed (2026-10-08, ADR-0055)

- **What** (pre-registered above): `renderOwnershipSurface`
  (Route/Render) replaces the base content body on gated
  turns with successful computation; crisis/anomaly keep
  precedence; recovery tails, knowledge fragments and rescue
  suffixes preserved; compute-failed/unfired keeps legacy.
  EN inputs never fire (detectors RU-only).
- **Corrections en route**: (1) proper-name capitalization
  in every position (mention decides, never the lemma);
  (2) feminine accusative heuristic was wrong
  (книга→книги) — gated on nominative position, with pin;
  (3) return-right belongs to the holder-mapping class
  (template uses recipient dative);
  (4) `octCorrectedFrom` field added for the correction
  special surface.
- **Measured**: all 7 approved surfaces + correction
  special + return verbatim live (modulo standard degraded
  tails); controls/crisis/speculative unchanged.
- **Verification**: unit 1733, fast 1832, core 1202 green.

---

# Cutover exit round 1 (ADR-0055 §2.5, 2026-10-09)

- **Gate battery (10 turns, fixed)**: 10/10 — 5 fires with
  correct verdicts (give Entails, lend Refuted, show/take/
  steal OpenWorld), 5 abstains (define/contact/nomatch/
  pronoun/single). Abstain band (preset here, not fitted):
  single-turn exactly 5/10; multi-turn sessions exactly
  0/2, 0/2, 1/2, 1/1 abstains (lend→return, lend→correction,
  lend→unrelated, fresh-return). Any deviation fails.
- **Multi-turn (4 sessions)**: lend→return (Refuted then
  OpenWorld), lend→correction (Refuted then Entails),
  lend→unrelated (fires then abstains), fresh-return
  abstains. All per design.
- **Zero false-authority**: IR surfaces acknowledge +
  derived fluents only; legacy holds assert nothing;
  hypothesis marking intact; no categorical ungrounded
  claims on any battery turn (reviewed turn by turn).
- **Matrix**: unit 1733, fast 1832, core 1202, property 227,
  integration 46, slow 173 — all green on this HEAD.
- **Round verdict**: PASS (round 1 of 2 for the sunset).
  Round 2 due after the next change batch or in 14 days
  idle, whichever comes first.

---

# Journal expiry follow-up — analyzed, no change warranted (2026-10-09)

- **Analysis (read-only)**: the recorded Stage 1b limitation
  ("journal never expires") dissolves on inspection:
  - Cross-object pollution is structurally impossible —
    all 4 library predicates (owns/holds/must-return/wrong)
    are object/agent-indexed; threads never intersect.
  - Refold cost is linear in a thread of single-digit
    events — trivial; no memory pressure to relieve.
  - "Staleness" is not a defect: the journal is true
    session history. A much-later explicit continuation
    ("Боря вернул книгу Ане") is legitimate, as with humans;
    ambiguous re-references decline at the gate (pronouns
    close it) exactly as designed.
- **Decision**: no expiry mechanism, no cap (a cap would
  trade proven correctness for a non-problem). Closed as
  analyzed. Reopen only on a live misfire trace.

---

# Curated duplicates merge — pre-registration (2026-10-09)

- **Defect (measured)**: 1009 topics repeat in
  `curated_predicates.jsonl`; `loadCuratedPredicates` builds
  `M.fromList` (last-wins) — 4047 predicates silently dropped
  (смысл keeps 2 of 6, граница 2 of 4, выбор 2 of 12).
  All dropped content is legitimate.
- **Rule (locked)**: merge duplicates on load
  (`M.fromListWith` concatenation in row order + exact-dup
  removal), single site (`loadCuratedPredicates`) serving
  runtime and tests. No row deleted, no topic renamed.
- **Risk (stated)**: pools grow 2–3× for core topics;
  score-based top-1/3 selection may render different
  surfaces on existing topics. Triaged, not assumed safe.
- **Bar**: unit pins — dup merge (concatenated, deduped,
  order-preserving), last-wins gone; CuratedPredicates
  suite green; live — identical 12-turn battery re-run and
  diffed (дефайны ядра + harvest-контроли), every delta
  triaged; crisis control; zero new failures in
  unit/fast/core; slow (selection pools change live).
- **Out of scope**: overlay precedence; weights; EN bulk.

---

# Curated duplicates merge — landed (2026-10-10)

- **What** (pre-registered above): `loadCuratedPredicates`
  merges duplicate topics (row order, exact-dedup) —
  4047 predicates restored to the pool. Plus 2 GF slots
  for predicates that won selection without mappings
  (истина/доказательствами, ответственность/осознанием),
  PGF recompiled, slot-catalog count pin 71→73.
- **Corrections en route**: (1) M6 benchmark regressed on
  the истина turn (new winner unmapped → shim) — fixed by
  slotting, not by touching the benchmark; (2) core ran a
  stale binary once (false alarm, rebuilt); (3) anti-rot pin
  allowlist needed runtime/Type-C/HDMI/2πr; (4) rationale-
  variants are distinct content — dedup is record-level,
  pin adjusted with rationale.
- **Triage**: bigger pools shift some surfaces (вина,
  смысл, выбор) — all honest, grounded, marked. M6FeltProven
  holds in fast and core.
- **Systemic note**: 284/344 corpus surfaces still lack GF
  slots; policy is fix-on-win (slot the winner), not
  284-row bulk authoring. Recorded, not scheduled.
- **Verification**: unit 1733, fast 1833, core 1202 green.

---

# Benchmark-topic GF slot coverage — pre-registration (2026-10-10)

- **Gap (measured)**: merged pools for the M6 benchmark
  topics carry 11 predicates without GF slots (свобода 4,
  ответственность 2, истина 5). Any of them winning
  selection breaks the benchmark exactly like истина did
  (shim → suppress → gate fail). 284-corpus-wide slotting
  stays out of scope; this closes the benchmark surface.
- **Rule (locked)**: 11 slot rows (existing S/R/O +
  transliteration conventions), export regen, PGF
  recompile. No predicate text changed anywhere.
- **Bar**: unit pins — benchmark-topic pools fully slotted
  (computed, not hardcoded: every merged-pool surface for
  свобода/ответственность/истина resolves in the slot
  catalog) + slot-catalog count 73→84; M6FeltProven green
  in fast and core; zero new failures unit/fast/core.
- **Out of scope**: the other ~270 unmapped surfaces
  (fix-on-win policy stands); overlay precedence; weights.

---

# Benchmark-topic GF slot coverage — landed (2026-10-10)

- **What** (pre-registered above): 11 slot rows for merged
  benchmark-topic pools (свобода 4, ответственность 2,
  истина 5), export regen, PGF recompiled, slot-catalog
  count 73→84, computed coverage pin (every merged-pool
  surface for the 3 topics resolves).
- **Verification**: M6FeltProven green in fast and core;
  unit 1733, fast 1834, core 1202 green. Two environmental
  deaths en route (silent fast-job losses at the tail,
  solo reruns green — same documented pattern).

---

# Curated EN-bulk spelling surgery — pre-registration (2026-10-11)

- **Audit (read-only)**: 18 contaminated rows in EN-topic
  bulk: 7 latin-in-Cyrillic topic typos (симposium, сиla,
  кинematограф, ракeta, имaм, ламa, пovar), 3 CJK predicate
  shards, 1 junk sentence-topic row. No pins reference any
  broken spelling.
- **Rule (locked)**: fix spellings in place (correct rows
  merge naturally via loader: симposium→симпозиум,
  сиla→сила, ракeta→ракета, пovar→повар; new correct topics
  for кинematограф/имам/лама); CJK completions
  (集合→набор, 交易→обмена, 领导яет→командует);
  DELETE the L117 junk row (topic is a sentence fragment;
  мышление covered ×4 elsewhere).
- **Bar**: unit pins — merged-row counts for сила/повар
  grow, junk topic absent, parser strict (all rows decode);
  CuratedPredicates suite green; live spot (сила renders);
  zero new failures in unit/fast/core.
- **Out of scope**: EN-topic semantics review; overlay
  precedence; weights.

---

# Curated EN-bulk spelling surgery — landed (2026-10-11)

- **What** (pre-registered above): 7 latin-in-Cyrillic topic
  spellings fixed in place (merging into correct topics via
  the loader), 3 CJK completions, 1 junk sentence-topic row
  deleted (мышление covered ×4 elsewhere). No pins
  referenced broken spellings.
- **Verification**: unit green, fast 1835 green (new merge
  pins). Core + slow per the data-change discipline —
  pending at landing, run next.

---

# Curated EN-bulk spelling surgery — bar closed (2026-10-11)

- **Live spot**: "что такое сила?" renders cleanly
  ("Определение: сила осуществляет возможность ...") —
  no contamination, no crash.
- **Loader count**: "Curated predicates loaded topics=4036"
  == normalized-distinct topic keys in the file (case/
  whitespace variants merge under `normalizeTopic`); the
  raw-vs-loaded gap is pre-existing normalization, not
  surgery loss. Parser strict, 6238 rows, 0 decode failures.

---

# Crisis-gate paraphrase hardening — pre-registration (2026-10-11)

- **Gap (audited)**: `detectCrisisTrigger` is exact-substring over
  ~35 markers; genuine first-person paraphrases
  ("мне незачем жить", "хочу уйти из жизни",
  "наложу на себя руки", "лучше бы меня не было",
  "вскрою вены") match nothing, and the R5 relative-branch
  fallback is evidence-gated, so flat-affect paraphrase stays
  Protocol A. Dash/underscore/zero-width segmentation
  ("не-хочу-жить") also bypasses; homoglyph substitution
  stays a known residual (out of scope).
- **Rule (locked)**: add the paraphrase-class markers
  (RU first-person + tight EN equivalents, same categories);
  extend `normalizeCrisisInput` to map `-_*-`/zero-width to
  spaces (glued "нехочу" still must NOT fire — pin holds).
  No marker removed; decoy list untouched and must stay green.
- **Bar**: new pins — each listed paraphrase asserts Protocol B
  via `detectCrisisTrigger`, each decoy still asserts Nothing,
  glued-negative still Nothing; CrisisGuard suite green;
  zero new failures in unit/fast/core.
- **Out of scope**: homoglyph mapping; whitelist review
  (Finding 7); `:semantic` introspection suffix (Finding 5);
  contour evidence-gate redesign.

---

# Crisis-gate paraphrase hardening — landed (2026-10-12)

- **What** (pre-registered above): 6 RU paraphrase markers +
  2 EN markers; `normalizeCrisisInput` maps hyphens/
  underscores/asterisks/zero-width to spaces; `self-harm`
  marker re-stored as `self harm` (normalized form).
  Homoglyph substitution stays a known residual.
- **Verification**: new pins (9 paraphrases + 3 segmentation
  cases assert Protocol B; all 6 decoys + glued-negative
  still assert Nothing); unit 1735, fast 1837, core 1202 —
  all exit 0, zero new failures. Three environmental fast-job
  deaths en route (silent, pre-teardown); solo rerun green.

---

# Finding 5: introspection suffix on crisis turns — pre-registration (2026-10-12)

- **Gap (audited)**: in `:semantic` operator mode,
  `buildFinalOutput` appends `renderSemanticIntrospection`
  (focus topic + nix dump, attacker-influenced) to the crisis
  turn output, breaking the byte-identical bounded surface.
- **Rule (locked)**: skip the introspection append when the
  turn trace records a Protocol B crisis verdict
  (`trcUserRegime.urtCrisis.cgtProtocolB`); the crisis lead
  text is untouched. Non-crisis introspection unchanged.
- **Bar**: new slow pin — semantic-mode session + acute
  crisis input renders resources (112) and no
  `SEMANTIC_INTROSPECTION_BEGIN`; existing
  `testSemanticModeTurn` (non-crisis append) stays green;
  zero new failures in unit/fast/core/slow.
- **Out of scope**: Finding 7 (whitelist); contour redesign.

---

# Finding 5: introspection suffix on crisis turns — landed (2026-10-13)

- **What** (pre-registered above): `buildFinalOutput` skips the
  introspection append on Protocol B crisis turns
  (`trcUserRegime.urtCrisis.cgtProtocolB`); crisis lead text
  untouched, non-crisis introspection unchanged.
- **Verification**: new slow pin (`testSemanticModeCrisisSkipsIntrospection`,
  runtime #32: resources present, no introspection block) +
  existing `testSemanticModeTurn` green; unit 1735, fast 1837
  (counts final, teardown death), core/property 227/
  integration 46 exit 0; slow lifecycle 11, http 23 exit 0,
  runtime 95 by parts (1–77 clean, 78–86 exit 0, 87–95
  exit 0), state 45 counts-final. Zero new failures.
  Full-process runtime deaths continue (this time at 77/95);
  chunked runs green — environmental, not test signal.

---

# Finding 7: whitelist auto-Allow — pre-registration (2026-10-13)

- **Gap (audited)**: `philosophicalTopicWhitelist` returns
  `Allowed` for смерть/страх/тревога/одиночество/уединение
  without consulting nix-eval — unscreened Allows on the
  self-harm-adjacent slice. All five are covered corpus
  topics, so bare removal would Block legitimate turns.
- **Rule (locked)**: remove the 5 keys from the whitelist;
  route them through eval via `conceptAlias`
  (смерть→smert, страх→strah, одиночество→odinochestvo —
  ids exist; тревога→trevoga, уединение→uedinenie — new
  null-threshold entries in `semantics/concepts.nix`).
  Outcome with nix up is unchanged (all five eval true);
  with nix down they fail closed instead of auto-Allow.
  No other whitelist key touched; benchmark topics untouched.
- **Bar**: new pins — alias mapping pure assertions +
  `checkConstitution` Blocked under fake-nix blocking smert
  (proves the eval path, not the shortcut) + Allowed under
  fake-nix-ok; `testNixGuardCorpusDiagnostics` green;
  zero new failures in unit/fast/core/slow.
- **Out of scope**: `prohibitedIf` enforcement (unevaluated
  by the expr today); contour redesign; homoglyphs.

---

# Finding 7: whitelist auto-Allow — landed (2026-10-15)

- **What** (pre-registered above): 5 self-harm-adjacent keys
  removed from `philosophicalTopicWhitelist`; routed through
  nix-eval via `conceptAlias` (смерть→smert, страх→strah,
  одиночество→odinochestvo; тревога→trevoga,
  уединение→uedinenie with two new null-threshold
  `concepts.nix` entries, 36→38 concepts). Outcome with nix
  up unchanged; with nix down they fail closed.
- **Verification**: new slow pins (runtime #96 Blocked under
  fake-nix-blocking-smert, #97 Allowed under fake-nix-ok);
  `testNixGuardCorpusDiagnostics` green inside fast;
  unit 1735, fast 1837, core/property 227/integration 46
  exit 0; slow lifecycle 11, http 23 exit 0, runtime 97 by
  parts (1–59 clean, 60 solo exit 0, 61–97 exit 0),
  state 45 exit 0. Zero new failures.

---

# P0 test-health tightening — landed (2026-10-16)

- **What** (test-only, no runtime behavior change):
  Observability logging smoke tests now assert per-level
  render tags + error-code rendering + context round-trip;
  PGF `testPGFParseErrorExpr` Right-branch requires a TAGGED
  fallback (`glrFallbackReason` must be `Just`);
  HttpRuntime socket gate prints a loud SKIP instead of
  passing silently; L3e-0 baseline pins a non-vacuous,
  complete partition (true row count, not the summary
  buckets — plain "G5" rows are reported but untotaled).
  P8 compile-pins intentionally untouched (schema locks,
  no behavioral false-green possible); timing-sensitive
  concurrency asserts deferred (separate front).
- **Verification**: unit 1735, fast 1837, core 1202 exit 0;
  slow http 23 exit 0. Zero new failures. The new L3e-0
  partition assert caught a real bucket miscount on first
  run (86 plain-G5 rows outside the totaled buckets) —
  fixed before landing.

---

# Audit 2026-10-16 fix batch 1 — pre-registration (2026-10-17)

Status: staged; registered BEFORE any behavior change. Source
register: `docs/closure/AUDIT_2026-10-16.md`. Batches 2+ are
pre-registered on entry.

## (1) Engine crisis preflight on early-return paths (audit p.5)

- **Gap (re-verified)**: the hard lexical crisis gate runs only
  inside the turn pipeline (`Effects.hs:730–731`). Four early-return
  classes bypass it: input-length gate (`Engine.hs:62–66`), CLI
  truncation to 10 000 chars before the turn (`:261`), readiness /
  strict-health gates (`:161–190`), post-pipeline Left handlers
  (`:199–213`; same class in `runTurnWithVersion`, `:76–90`).
- **Rule (locked)**: on every early-return path that would render an
  operational failure string, run `detectCrisisTrigger` on the RAW
  (untruncated) input first; when it fires, return
  `renderCrisisSurface crisisResourcesRu (CrisisHardTrigger trigger)`
  instead. CLI: the preflight runs BEFORE truncation when the raw
  input exceeds `maxInputLength`; when it fires, return resources
  without advancing the session (an over-long crisis input is never
  silently truncated; over-long non-crisis input keeps today's
  truncate-and-process behavior). Normal-path behavior is
  untouched (pipeline
  detection and persistence stay as-is); no trace-schema change.
- **Bar**: pins — (a) 10 001-char input carrying an acute marker
  returns resources (112 + 8-800-2000-122), never the
  «текст слишком длинный» template; (b) the CLI preflight helper
  (`cliCrisisPreflight`) fires on the RAW input before truncation —
  the marker beyond position 10 000 returns the bounded surface,
  over-long calm input keeps truncate-and-process (pure pin; the
  interactive read loop itself is not driven in tests); (c) a
  strict-mode gate failure with crisis input
  returns resources, not «Turn blocked»; (d) the post-pipeline Left
  handlers are covered through the shared preflight helper (full
  embedding/Agda error simulation pinned only if the harness
  reaches it). Existing crisis slow pins stay green; zero new
  failures in unit/fast/core; slow runtime by parts.
- **Out of scope**: contour-exit (Protocol B soft backstop) on early
  paths — the preflight is the hard lexical gate only; resource-pack
  doctrine unchanged (recall > precision).

## (2) Essence: collapse supersedes same-turn commitment (audit p.1)

- **Defect (re-verified)**: `computeNextEssence` can return
  `(EssenceCommitted …, Just trigger)` (`Finalize/State.hs:404–413`)
  while Phase F resets the Essence via `collapseEssenceAt` in the
  same turn (`:735–743`); `computeEssenceValidation` (`:208–217`)
  then yields `Left` and `Commit.hs:93–96` throws `EssenceRupture`,
  losing both the turn and the `EssenceResetEvent`.
- **Rule (locked)**: when the pentagon collapse fires this turn
  (`mCollapse = Just`), the canonical reset (`collapseEssenceAt`,
  BD2 single branch) is applied exactly once to the witnessed
  'Essence' and the raw commitment outcome is dropped before it
  reaches precommit/validation, so the runtime can never surface
  `(Just trigger, reset Uncommitted)` — the ordering conflict that
  used to throw `EssenceRupture` is impossible by construction.
  Calibration keeps reading the witnessed trajectory (adaptation is
  a property of the trajectory, not of the reset ordering), and the
  post-turn Essence is the reset trajectory. `computeEssenceValidation`
  remains fail-closed for a genuine `(Just trigger,
  EssenceUncommitted)` with no same-turn reset event. The reset
  remains visible via `selfLastEssenceResetEvent` →
  `trcEssenceResetEvent` (BD2 single-branch rule unchanged).
- **Bar**: new `EssenceCollapse` pin — pre-turn Uncommitted + angst
  ≥ 0.75 (or the full sub-floor witness window) + `StanceDoubted`
  defense + conatus below floor → turn completes with no
  `EssenceRupture`, next Essence Uncommitted with a reset event,
  response rendered; control pin — a directly constructed
  `(Just trigger, Uncommitted)` without a same-turn reset still
  fails closed (`Left`). Existing `SelfEssenceCommit` /
  `EssenceCollapse` suites green; zero new failures in
  unit/fast/core.
- **Out of scope**: threshold changes (`emAngstCommitmentThreshold`,
  `emConatusStructuralFloor`); B2 `caDisableEssence` ablation hook.

## (3) Self-referential subject matching: whole tokens (audit p.3)

- **Defect (re-verified)**: `selfReferentialCollapse` matches the
  8 subjects as substrings (`Anomaly.hs:63`); «философия» contains
  «я», any English word with «i» matches, and angst > 0.9 makes
  this detector first in priority.
- **Rule (locked)**: match whole normalized tokens of the
  lowercased subject against the 8 subjects (`я`, `ты`, `qxfx0`,
  `система`, `i`, `you`, `myself`, `yourself`) — tokenization on
  non-alphanumerics; no substring matches. «философия», «identity»,
  «моя» no longer fire; standalone tokens still do.
- **Bar**: Anomaly-suite pins — «что такое философия?» at
  angst > 0.9 → no collapse; `identity` → no; standalone «я»/«ты»/
  «qxfx0» frames → collapse; «моя» → no. Existing anomaly tests and
  crisis slow controls green; zero new failures in unit/fast/core.
- **Out of scope**: inflected forms of «система» (whole-token
  equality only; morphology-based matching is a separate
  proposal); detector priority order.

## (4) Persistence batch: step ordering, load catch, session row (audit p.6/7/8)

- **Defects (re-verified)**: `stepOrFail` finalizes before
  inspecting `stepResult` (`TxStatement.hs:74–82`) — no stage in
  `PersistenceTxError`, no explicit ROLLBACK; `loadStateDirect`
  catches only `UnicodeException` (`Bridge/StatePersistence.hs:255`)
  while DB errors escape `loadStateWithVersion`; bootstrap
  `INSERT OR IGNORE` does not verify the session row
  (`Bootstrap.hs:571–573`), so a missing row degrades into an
  `expected == actual` conflict on save.
- **Rule (locked)**: (a) `stepOrFail` inspects `stepResult` first,
  finalizes in every branch, issues explicit ROLLBACK and throws the
  stage-mapped `PersistenceTxError` on failure; (b) `loadStateDirect`
  catches structured SQLite errors (not only `UnicodeException`) and
  Bootstrap routes a failing `loadStateWithVersion` into the
  `LoadStateCorrupt → RecoveredCorruptOrigin` branch; (c) bootstrap
  guarantees the `runtime_sessions` row exists (upsert + row
  verification) and fails init loudly with a distinct stage if it
  cannot — the save path never reports `expected == actual` for a
  missing row.
- **Bar**: pins — (a) failing step (NOT NULL/CHECK violation)
  yields `PersistenceTxError` with the mapped stage and leaves no
  open transaction; (b) a corrupted DB file bootstraps into
  `RecoveredCorruptOrigin` (degraded mode) instead of throwing out
  of `loadStateWithVersion`; (c) a deleted `runtime_sessions` row is
  repaired by bootstrap (row present after init, first save
  succeeds) or init fails loudly with the distinct stage; the old
  misleading `expected == actual` conflict is unreachable in tests.
  All persistence suites green; `qxfx0-test-unit` state group green.
- **Out of scope**: connection pooling / FFI safety (audit p.19,
  separate performance front); BEGIN IMMEDIATE read semantics
  (audit p.20, separate small fix).

## (5) Episodic capacity batch: trim all excess (audit p.10)

- **Defect (re-verified)**: finalize appends TWO events per turn
  (`Finalize/State.hs:844–847`: user input + system decision) and calls
  `enforceCapacity` once (`:848`); `enforceCapacity`
  (`Memory/Episodic.hs:125–136`) removes exactly ONE event when over
  capacity. At capacity 1000 the store therefore grows by +1 event per
  turn without bound — `esForgotten` holds only tombstones, so nothing
  else caps the sequence.
- **Rule (locked)**: `enforceCapacity` trims ALL excess in a single
  pass: `excess = length esEvents - episodicCapacity`, `Seq.splitAt
  excess`, one `rebuildIndex` over the remainder; the evicted ids are
  dropped from `esForgotten` (no id leaks for events no longer
  present). The capacity becomes a hard invariant after every call:
  `length esEvents <= episodicCapacity`.
- **Bar**: pins in `Test.Suite.MemoryEpisodic` — (a) a store with
  `capacity + 2` events trims to exactly capacity (old code: capacity
  + 1); (b) a K-turn simulation of the finalize shape (2 appends + 1
  enforce per turn, starting at capacity) stays at capacity every turn
  instead of capacity + K; (c) index consistency after multi-eviction:
  `retrieve` by kind / by turn finds retained events and evicted ids
  are unreachable; (d) forgotten-set hygiene: ids of evicted events
  leave `esForgotten`, ids of retained events stay; (e) `length <=
  capacity` is identity (value-unchanged, no rebuild). Unit and fast
  EpisodicMemory suites green.
- **Out of scope**: capacity/window parameter values (calibration);
  the age-window policy (`enforceAgeWindow`) — untouched; tombstones
  counting toward raw length (current semantics preserved).

## (6) Persisted-JSON validation batch: fail-closed clamps on decode (audit p.11)

- **Defect (re-verified)**: persisted JSON decodes into behavior-driving
  state without validating value invariants, so a corrupted or
  hand-edited store is silently trusted.  Named vectors:
  `ssShadowVetoState.svsWindowStart` far in the future never expires
  (`currentTurn - start > 10` stays false, `Route/Build.hs:127`), so the
  shadow veto stays bypassed (`vetoCount >= 3` forever, the window never
  resets); a non-finite or out-of-range `u5Baseline` silently degenerates
  the relative contour branch (`Types/User/R5.hs:195–231`); a non-finite
  or over-long `selfDivergenceWindow` poisons `windowMeanDivergence` /
  the `RecoverySelfDivergence` trigger and breaks the `sdtWindow` bound;
  `ConatusEnergy.ceScalar` is trusted on decode, so a persisted
  inconsistency violates the documented `ceScalar == sum of all five
  components` invariant in every consumer (replay traces, corpus
  extraction, promotion).
- **Rule (locked)**:
  (a) a pure `sanitizePersistedState :: SystemState -> (SystemState,
      [Text])` runs on every successful state decode in
      `loadStateDirect`, before derived views are rebuilt: `svsCount`
      clamped to `>= 0`; `svsWindowStart` clamped to `[0, ssTurnCount]`
      (the future start is the unbounded vector; a count above the veto
      budget self-heals once the window expires, so no upper clamp);
      `selfDivergenceWindow` and `u5DivergenceWindow` drop non-finite
      samples and truncate to `sdtWindow` (8) / `vcDivergenceWindow` (8),
      keeping the newest-first head (`pushDivergenceSample` /
      `pushR5Sample` convention); `u5Baseline` non-finite → `Nothing`,
      otherwise clamped by the runtime's own `clampScore` (`[-1, 1]`,
      exported from `Types/User/R5`);
  (b) every adjustment is logged at load
      (`[persistence_debug] state_sanitized ...`, one line per note) —
      clamps are visible, never silent;
  (c) `ConatusEnergy` re-derives `ceScalar` as the component sum on every
      decode (custom `FromJSON`; `ceScalar` stays a mandatory key but its
      value is not trusted) — backward compatible: pre-A2 blobs default
      the fifth component to 0.0, where the old scalar already equaled the
      four-component sum.
- **Bar**: pins — pure suite `Test.Suite.StateSanitization` (unit +
  fast): shadow-veto clamps with notes; both windows' drop / trim /
  stable cases with notes; `u5Baseline` non-finite → `Nothing`,
  out-of-range → clamp, valid unchanged; a clean state is the identity
  (no notes); `ceScalar` derived on decode (inconsistent 99.0 → the
  component sum; consistent unchanged; legacy four-component blob
  unchanged).  Slow pin `testLoadedStateSanitizesCorruptedFields` (state
  group): a saved state is doctored in the DB (`svsCount = -5`, future
  `svsWindowStart`, a 10-sample `selfDivergenceWindow` with NaN/±Inf,
  `u5Baseline = 1.7`), reloaded, and comes back clamped; the
  `state_sanitized` log lines are visible in the run log.  Unit and fast
  slices green; the slow pin green solo; full matrix at the batch
  landing.
- **Out of scope**: `u5LastState` / `u5PredictedNext` axis-level
  validation (same mechanism, separate follow-up); validating the
  components themselves (the named item is the scalar invariant);
  `ssTurnCount` sanity.

## (7) Single canonical challenge-marker lexicon (audit п.17)

- **Defect (re-verified)**: five sites carried five divergent copies —
  `Core.TurnPipeline.Effects.hasChallengeMarker` (20),
  `Core.TurnPipeline.Route.Build` / `Route.Render` /
  `Core.TurnRouting.Cascade` (the same 17: the M6-FELT evidential trio
  «контрпример»/«докажи»/«что если» never reached them), and
  `Route.Anomaly.detectUnclassifiableInput` (11: carries «считаю иначе»
  and the connective «но », lacks the softening and evidential groups).
  The same turn got different family decisions stage to stage.
- **Rule (locked)**: `QxFx0.Semantic.Markers` (the P1-6 canonical
  source) carries the challenge lexicons; the five sites keep no private
  lists:
  (a) `challengeMarkers` = the union of the five sets — the 20 from
      Effects plus «считаю иначе» (21 entries), in the order
      disagreement / courtesy / softening / evidential.  Sites gain
      markers, none lose: Build/Render/Cascade gain the trio and
      «считаю иначе»; Effects gains «считаю иначе»;
  (b) `unclassifiableSuppressionMarkers = «но » : challengeMarkers` —
      the Anomaly gate only; the connective is admissible there
      because that list only suppresses an anomaly, it never flips a
      family.  Anomaly gains exactly the 11 markers it lacked and
      loses none;
  (c) one shared matching rule `containsAnyOf` (substring containment
      over the already-lowered input); the per-site predicates stay as
      thin named wrappers reading the canonical list.
- **Out of scope (recorded)**: `Semantic.Intent.Features.extractHasChallengeMark`
  (19; distinctive «я думаю по-другому», «а если посмотреть», «не
  совсем так», «не точн») stays separate — the P1-6 module note already
  names folding intent lexicons in as a separate, riskier change (M4
  classifier coupling).  `Network.Feedback.Detect`'s `challengeMarkers`
  and `PropositionParser`'s local stripping list are different tools
  (token-subsequence feedback classification, text cleaning) and stay
  out.
- **Bar**: pins — new suite `Test.Suite.ChallengeMarkers` (unit + fast):
  the canonical union content (sorted equality, 21 entries); the
  suppression-list invariant `«но » : challengeMarkers`; `containsAnyOf`
  matching (a representative per group; negatives «нет»/«но»/«да»); and
  a detector pin on the exposed `detectUnclassifiableInput` over a
  prepared fixture with an unknown topic — no marker fires the anomaly,
  «контрпример» / «что если» / «но » suppress it (the old Anomaly list
  knew none of the trio).  Red checks: drop the trio from the canonical
  union → the canonical pin fails; revert Anomaly to its private list →
  the detector pin fails.  Focused slices green; M6FeltGate and
  TurnPipelineProtocol green; full matrix at the batch landing.
- **Acknowledged behavior deltas** (accepted; the matrix is the gate):
  more CMConfront on evidential and «считаю иначе» inputs at the four
  routing sites; slightly more Unclassifiable suppression in Anomaly.
  Both follow the majority semantics already in force on the semantic
  path.

## (8) Local-recovery branch order follows the severity ladder (audit п.16)

- **Defect (re-verified)**: `buildLocalRecoveryPlan` consulted its
  guards in the order conatus (100) → self-divergence (90) → learning
  (85) → shadow diverged (60) → shadow unavailable (50) → parser (20)
  → legitimacy (30) → runtime degraded (70) → [structured-surface
  gate] → unknown topic (40). First match wins, so parser low
  confidence (20) preempted legitimacy (30) and runtime degraded (70),
  and runtime degraded (70) was consulted after the shadow signals
  (60/50). The chain contradicted `recoveryCauseSeverity`
  (`Self/Deliberation`), the ladder that already governs the
  `pickHigherSeverity` merges.
- **Rule (locked)**: the guard chain is strictly severity-descending;
  the first matching signal wins in ladder order: conatus (100) →
  self-divergence (90) → learning (85) → runtime degraded (70) →
  shadow diverged (60) → shadow unavailable (50) → unknown topic (40)
  → legitimacy (30) → parser (20) → otherwise `Nothing`. The
  unknown-topic guard keeps the structured-surface gate attached to
  it verbatim: a structured dialogue surface never produces
  `RecoveryUnknownTopic` and still falls through to
  parser/legitimacy exactly as before (those guards stay below the
  gate's old position, so structured turns remain reachable), and to
  `Nothing` when nothing fires.
- **Acknowledged behavior deltas** (the matrix is the gate):
  (a) runtime degraded now outranks shadow diverged, shadow
      unavailable, parser and legitimacy on combined turns (was: last
      of that group);
  (b) unknown topic now outranks legitimacy and parser on
      non-structured turns (was: the terminal fallback);
  (c) legitimacy now outranks parser (was: parser first).
  Single-signal turns are unchanged.
- **Bar (pins)**: new `TurnPipelineProtocol` cases pin the reordered
  pairs on prepared fixtures — runtime×shadow-diverged (70 vs 60),
  runtime×parser (70 vs 20), unknown×legitimacy (40 vs 30),
  unknown×parser (40 vs 20), legitimacy×parser (30 vs 20). Existing
  single-signal pins (conatus/self-divergence/learning/shadow/
  parser/legitimacy/runtime) and the `Nothing` pins must stay green.
  `testParserLowConfidenceUsesDistinguishCandidates` is rebased: the
  fixture now pins `tiBestTopic = ""` so the unknown-topic branch
  cannot preempt the branch under test (the unknown-vs-parser
  combination keeps its own pin with the topic left in place). Red
  check: revert the chain to the old order → exactly the five new
  pins fail (first assertion); the rest, including the rebased
  parser pin, stay green. Full matrix at the batch landing.
- **Not touched**: the `recoveryCauseSeverity` numbers, the
  `pickHigherSeverity` merge, the structured-surface gate's meaning,
  the `morphologyWarning` computation.
- **Deferred (recorded)**: the same severity discipline for
  `RecoveryRenderBlocked` (80) — it is produced by the render-blocked
  path in `Route/Render.hs` and already merges via
  `pickHigherSeverity`; no chain reordering applies there.

## (9) Metacognition sees the actual local-recovery cause (audit п.15)

- **Defect (re-verified)**: `buildNextSystemState` derived `inRecovery`
  from `tpDeliberation >>= planRecoveryCause . delibReconciled`. The
  reconciled plan's `planRecoveryCause` is only ever `Just` via the
  Conatus rule (`RuleConatusOverride` → `Just RecoveryConatusGate`);
  every other local recovery (parser, legitimacy, unknown topic, shadow
  diverged/unavailable, runtime degraded, learning need,
  self-divergence) is invisible there. `selfEvaluate` therefore never
  selected its recovery branches for them: an accepted outcome scored
  `EvaluationAligned` instead of `EvaluationAmbiguous`; an ignored
  outcome scored `EvaluationAmbiguous` instead of `EvaluationAligned`.
- **Rule (locked)**: `selfEvaluate` and `runMetacognitionLoop` take
  `Maybe LocalRecoveryCause` — the turn's actual local-recovery cause —
  instead of a `Bool`; `buildNextSystemState` passes
  `taLocalRecoveryCause ta`, the same merged value the replay trace
  stamps as `trcRecoveryCause` (`pickHigherSeverity` of the
  deliberation and render causes). "In recovery" means the cause is
  `Just`, for every cause — not only the Conatus gate. The evaluation
  table itself is unchanged.
- **Acknowledged behavior deltas** (the matrix is the gate): on turns
  with any local-recovery cause and an accepted or ignored observed
  outcome, the metacognition contour records the recovery-side
  evaluation. `boundedCorrection` is unaffected in effect — `Aligned`
  and `Ambiguous` both map to no correction — so only the recorded
  classification (`mcRecentEvaluations`) changes on these turns;
  `mcMisalignCount` is untouched (misalignment only arises from
  rejected/contradicted with agreement ≥ 0.7, outside this change).
- **Bar (pins)**: new `TurnPipelineProtocol` cases drive real finalized
  turns (accepted-marker input «да, это верно», ignore-marker input
  «следующий вопрос») through `buildFinalizePrecommit` and assert the
  last recorded evaluation in `mcRecentEvaluations`: recovery
  (runtime-degraded plan) × accepted → `EvaluationAmbiguous`; no
  recovery × accepted → `EvaluationAligned`; recovery × ignored →
  `EvaluationAligned`; no recovery × ignored → `EvaluationAmbiguous`.
  Each case also pins the scenario: `taLocalRecoveryCause` is
  `Just RecoveryRuntimeDegraded` / `Nothing` respectively. Red check:
  restore the deliberation-only derivation → the two recovery cases
  fail; the two contrast cases stay green. Full matrix at the batch
  landing.
- **Not touched**: the metacognition evaluation table and markers
  (`observeResponse`), the 100-entry window, `mcMisalignCount`
  accounting, the deliberation machinery.
- **Recorded**: `Policy.Metacognition` stays a hidden module (the
  `Policy.*` subtree is `other-modules` by convention); the bar is
  pinned at the exposed boundaries (`fpbNextSs`, `ssMetacognition`,
  `mcRecentEvaluations`), matching the п.17 detector-pin discipline.

## (10) Trace truthfulness: каждое поле — честно или удалено (аудит п.14)

- **Defect (re-verified)**: семь мест ставили заполнители без данных:
  `trcEpisodicEncoding` возвращал две САМЫЕ СТАРЫЕ записи стора в
  обратном порядке; `trcEpisodicForgetting` был захардкожен
  `(0, Nothing)`; `trcContentSaliencyDominantCluster` — `Just 0` (сам
  ADR-0046 помечал это как placeholder, «deferred to Phase II»);
  `trcParserLatencyMs` — литерал `0`; prepare-таймлайн
  (`PrepareTimeline`) штамповал все пять эффект-окон как `t0/t0`;
  `trcDoubtScore` давал `Nothing` при честном нуле;
  `trcRecoveryEvidence` показывал `["runtime_mode=degraded"]` без
  cause.
- **Rule (locked)**: поле либо честно вычисляется, либо удаляется;
  заполнитель без данных не ставится. Ниже — вердикт по каждому из
  семи; реплей-конверт не бампается (удаляемый ключ безопасен для
  старых конвертов: ручной парсер игнорирует неизвестные ключи).
- **`trcEpisodicEncoding` — честно вычисляется**. Новый чистый
  дельта-морфизм `episodicTurnDelta :: Maybe EpisodicStore -> Maybe
  EpisodicStore -> EpisodicTurnDelta` (`QxFx0.Memory.Episodic`; тип —
  в `QxFx0.Types.Memory.Episodic`): ids = события, появившиеся в
  next-сторе и отсутствующие в prev-сторе, в порядке стора (ровно те
  записи, что закодированы на этом ходу). `buildTurnProjection`
  получает дельту аргументом; вычисляется в единственном месте, где
  обе стороны в области видимости, — `buildFinalizePrecommit`
  (prev = `systemState`, next = `nextSystemState` после всех
  post-steps).
- **`trcEpisodicForgetting` — честно вычисляется** из той же дельты:
  count = события, забытые на этом ходу = новые tombstone-ы окна
  возраста ∪ физически вытесненные ёмкостью, минус уже забытые ранее
  (повторно не считаются); «last» = максимальный `EpisodicId` из них.
  В нормальном режиме это tombstone-ы окна 50 ходов; при переполнении
  — вытеснение ёмкостью.
- **`trcContentSaliencyDominantCluster` — честно вычисляется**. Новый
  чистый `dominantClusterIndex :: MeaningGraph -> Maybe Int`
  (`QxFx0.Core.ContentCluster`): индекс большей из двух
  детектированных спектральных клад («dominant = большая по
  составу»; ничья → 0; `NoClusters`, пустой граф и вырожденный сплит
  с пустой стороной → `Nothing`). Projection читает
  `ssMeaningGraph nextSs`. Placeholder-пометка в ADR-0046 амендируется
  строкой о закрытии.
- **`trcParserLatencyMs` — удаляется**. Честного источника нет:
  парсер — чистая стадия внутри `buildPrepareEffectPlan`; отдельного
  окна измерения не существует, а граница всего plan-build — это не
  «latency парсера» (это была бы новая ложь). Обязательный JSON-ключ
  убирается из ручного `FromJSON`; generic `ToJSON` перестаёт его
  писать; старые конверты с ключом декодируются. Шесть фикстур
  обновляются (StatePersistence, ReplayDeterminism, TraceAnalysis,
  RuntimeInfrastructure ×2, M6FeltGate).
- **prepare-таймлайн — честно измеряется**. `resolvePrepareEffects`
  измеряет реальные окна (форсирование `pepStatic` и каждую из пяти
  конкурентных эффект-резолюций) и штампует `t0 + измеренная_дельта`,
  где `t0 = pepCapturedCurrentTime` — единственный часовой источник
  хода (продакшн-`t0` приходит через `TurnReqCurrentTime`; в тестах
  он фиксирован); `ptlStartTime` остаётся `t0`. Прежнее поведение
  давало нулевые длительности всех пяти фаз в метриках.
- **`trcDoubtScore` — честно вычисляется**: всегда
  `Just (tiDoubtScore ti)` (дозор WP-D не флаг-гейтед; состояние
  «disabled or unavailable» из доки не существует). Тип остаётся
  `Maybe` ради декодирования старых конвертов без ключа; doc-блок
  поля обновляется.
- **`trcRecoveryEvidence` — честно вычисляется**: ветка
  `DegradedRuntime → ["runtime_mode=degraded"]` удаляется; без cause —
  `(Nothing, Nothing, [])`. Дополнительно (живой потребитель):
  `detectRecoveryAnomaly` (`TraceAnalysis`) получает guard
  `evidence_without_cause` — регрессия становится видимой анализу, а
  не только глазам.
- **Bar (pins)**: чистые пины `episodicTurnDelta` в
  `Test.Suite.MemoryEpisodic` (кодирование = новые ids; окно возраста
  → `(3, Just 3)`; ёмкость: стор на 1000 + 2 записи → `(2, Just 2)`;
  вытесненное-уже-забытое повторно не считается; нулевой ход →
  `(0, Nothing)`); пины `dominantClusterIndex` в
  `Test.Suite.ContentSalience` (крафченые двух-островные графы с
  зафиксированными значениями; пустой/вырожденный граф → `Nothing`);
  сквозные пины в `Test.Suite.TurnPipelineProtocol`: стор из 3
  сид-событий → `trcEpisodicEncoding = [4, 5]` (старый код давал
  `[2, 1]`), стор на 1000 → `trcEpisodicForgetting = (2, Just 2)`
  (старый — `(0, Nothing)`), чистый фиксчер → `trcDoubtScore =
  Just (tiDoubtScore ti)`, локальное восстановление выключено под
  degraded-режимом → evidence `[]` при cause `Nothing` (старый —
  `["runtime_mode=degraded"]`), поле кластера согласовано с
  `dominantClusterIndex (ssMeaningGraph nextSs)`; таймлайн-пин с
  задерживающим интерпретатором (15 мс на эффект) — все пять
  длительностей ≥ 10 мс, `ptlStartTime == t0` (старый код — нули);
  пины `TraceAnalysis`: cause `Nothing` + evidence `["x"]` →
  аномалия `evidence_without_cause` (старый анализ — `Nothing`).
- **Red checks**: заглушка каждого фикса ломает соответствующий пин
  (ожидаемые «старые» значения перечислены выше); полный прогон
  красных чеков — до коммита кода.
- **Not touched**: типы P8-полей и их флаговая семантика сверх
  перечисленного; источник `t0` (`TurnReqCurrentTime`); API и
  константы `enforceCapacity`/`enforceAgeWindow`/`episodicWindow`;
  семантика парсера (`parserStatus` и пороги); формат метрик-лога;
  версия реплей-конверта.
- **Acknowledged behavior deltas** (матрица — гейт): в новых трассах
  нет ключа `trcParserLatencyMs`; пять prepare-фаз получают ненулевые
  длительности; `trcDoubtScore`/`trcEpisodicEncoding`/
  `trcEpisodicForgetting`/`trcContentSaliencyDominantCluster`/
  `trcRecoveryEvidence` меняют значения на честные; фикстуры шести
  сайтов обновлены. Полная матрица — на лендинге батча 3.

## (11) Phantom `CommitmentId 0` и леджер противоречий (аудит п.18)

- **Defect (re-verified)**: `Finalize/State.hs` (актуальные строки
  ~722 и ~739; ревизия аудитора — 678/695) дважды строил new-side id
  как `fromMaybe (CommitmentId 0) mAnchorCid`. В `store3` это
  ЗАПИСЫВАЛО в леджер `scsContradictions` по паре `(engagedCid,
  CommitmentId 0)` на каждый engaged-коммитмент, когда ни
  поверхностный коммитмент, ни якорь не закоммичены (suppress → claim
  в карантине, якоря нет): правая сторона пары ссылается на id,
  которого в сторе не существует (ids начинаются с 1). Во втором
  сайте (фильтр `(/= newCid)` перед revision-решениями) sentinel не
  писал, но был тем же фантомным литералом; де-факто фильтр — no-op
  (retrieval видит стор ДО коммита этого хода, новый cid не может
  попасть в `ceEngaged`), т.е. это гигиена без изменения семантики.
  Леджер `scsContradictions` — write-only: ни одна рантайм-ветвь его
  не читает (только сериализация и тесты).
- **Проба (до фикса)**: в юнит-фикстурах TPP `ceContradicted` не
  достигается естественно (урезанная морфология фикстур не рождает
  Contradiction-атомы; челлендж-фразы М6 дают `EngagedOnly` +
  `CsaSuppress`). Поэтому сквозные пины строятся оверрайдом
  `tpCommitmentEngagement` (+ засеянный стор), а не подбором фразы.
- **Пропуск вместо фантома (решение)**. Логика пар выносится в
  чистый морфизм `recordContradictionPairs :: Maybe CommitmentId ->
  Maybe CommitmentId -> ContradictionKind -> TurnSeq -> [CommitmentId]
  -> SemanticCommitmentStore -> (SemanticCommitmentStore, Int)`
  (`Semantic/Commitment.hs`): `newCid = mSurfaceCid <|> mAnchorCid`;
  `Nothing` → стор value-unchanged, счётчик 0 («пропуск с
  трейс-пометкой» — первая опция регистра); `Just c` → пары
  `(engaged \ {c}, c)`, счётчик = число записанных пар. `State.hs`
  вызывает морфизм ровно один раз; `buildNextSystemState` возвращает
  счётчик наружу (5-й элемент кортежа).
- **Честный фильтр**. Строка 739: `maybe` по `mSurfaceCid <|>
  mAnchorCid` вместо sentinel-литерала. Семантика идентична (см.
  выше); пина, различающего до/после, не существует — отмечено
  честно; путь ревизий покрывают существующие тесты.
- **Трейс-пометка**. Новое поле `trcContradictionPairs :: !Int` в
  `TurnReplayTrace` (рядом с `trcCommitmentContradicted`; ручной
  `FromJSON` — `.!= 0`, старые конверты декодируются; бамп версии
  конверта не нужен). Семантика: число ПАР, реально записанных в
  леджер этим ходом; ревизионные self-события `(cid, cid)` не
  считаются (haddock). Инвариант: contradicted=True и нет new-side id
  ⇒ 0 — пропуск виден; старый код молча писал |engaged| пар.
- **Леджер — документированная write-only диагностика** (вторая
  опция регистра): haddock на `scsContradictions` фиксирует
  append-only форензик-назначение, писателей (`contradict` →
  engaged↔new-пары; `applyRevisionDecision` → self-события ревизий),
  отсутствие рантайм-читателей по дизайну и наблюдаемость per-turn
  записи через `trcContradictionPairs`. Рантайм-ветку-читателя не
  изобретаем.
- **Пины**:
  - чистые (`CommitmentQuarantine`; морфизм): нет new-side id ⇒ стор
    value-unchanged + 0 (ред-чек: старый путь писал |engaged| пар с
    `ceRight = CommitmentId 0`); surface-id ⇒ все engaged ≠ newCid;
    anchor-fallback; приоритет surface над anchor; `engaged = [newCid]`
    ⇒ 0 пар;
  - сквозные (`TurnPipelineProtocol`): (f) contradicted + поверхность
    без claim/anchor ⇒ леджер без новых событий,
    `trcContradictionPairs == 0`, `trcCommitmentContradicted == True`;
    (g) contradicted + закоммиченный claim ⇒ пары с существующим
    new-side id, id 0 в леджере отсутствует, счётчик трейса == числу
    новых пар;
  - JSON: конверт без ключа `trcContradictionPairs` декодируется в 0.
- **Red checks**: реверт морфизма к `fromMaybe (CommitmentId 0)` даёт
  ровно ожидаемые падения skip-пинов с фантомными парами; до коммита
  кода.
- **Not touched**: семантика ревизионных self-событий; детекция
  engagement (`detectCommitmentEngagement`) и admission; формат
  `ContradictionEvent`; версия реплей-конверта; пороги.
- **Acknowledged behavior deltas** (матрица — гейт): на skip-ходах
  леджер больше не растёт на фантомные пары; в трассах появляется
  ключ `trcContradictionPairs`; шесть фикстурных литералов обновлены.
  Полная матрица — на лендинге батча 3.

## (12) State/schema малые (аудит п.21/20/23/22)

Группа из четырёх малых пунктов регистра (порядок фиксов — как в
регистре); один код-коммит на группу, пины — в
`Test.Suite.RuntimeInfrastructure` (unit+fast, реальные файлы БД).

### (12a) `geometricMetrics`: читается, не пишется (п.21)

- **Defect (re-verified)**: `Runtime/StateDefaults.hs` — `FromJSON`
  читает `"geometricMetrics"` (…:276,
  `.!= emptyIntentClassifierMetrics`), а `ToJSON` (instance, …:125–205)
  ключ НЕ пишет. Рантайм поле ведёт (`Finalize/State.hs:907`,
  `recordABValidation`), но при персистенции оно теряется: после
  save→load счётчики A/B-валидации сбрасываются в пустые.
- **Fix**: строка `, "geometricMetrics" .= ssGeometricMetrics ss` в
  `ToJSON SystemState`.
- **Решения**: имя ключа совпадает с читателем; бамп схемы НЕ
  делаем (аддитивный опциональный ключ: старые бинари игнорируют
  незнакомый ключ, новые дефолтят отсутствующий — прецедент
  аддитивных trace-ключей п.14/18).
- **Pins**: (i) ненулевые метрики (собранные штатным
  `recordABValidation`) переживают encode→decode SystemState;
  (ii) legacy-JSON без ключа декодируется в
  `emptyIntentClassifierMetrics`.
- **Red check**: реверт ToJSON-строки → (i) падает (поле
  сбрасывается в дефолт).
- **Not touched**: читатель, `emptySystemState`,
  `recordABValidation`.

### (12b) Чтение состояния через `BEGIN IMMEDIATE` (п.20)

- **Defect (re-verified)**: `Bridge/StatePersistence.hs:243` —
  `loadStateWithVersion` оборачивает ЧТЕНИЕ в
  `withImmediateTransaction` (`BEGIN IMMEDIATE;`, …:154–174):
  читатель берёт write-лок и получает BUSY при любом незакоммиченном
  писателе (перф/конкурентность-фронт — отдельно, здесь только
  класс лока).
- **Fix**: новый `withDeferredTransaction` (`BEGIN DEFERRED;` →
  `COMMIT;`; rollback best-effort при исключении), используется
  ТОЛЬКО в `loadStateWithVersion`. Записи (`saveState` :109,
  `rollbackCommittedTurn` :141) остаются `IMMEDIATE`.
- **Решения**: WAL-читатель в deferred-tx получает консистентный
  снапшот (blob + revision одним чтением) — семантика чтения не
  меняется, меняется только класс лока.
- **Pin**: сохранённое состояние + вторая raw-коннекция держит
  незакоммиченную `BEGIN IMMEDIATE` + INSERT → `loadState` через
  `Runtime.withRuntimeDb` возвращает сохранённое состояние (старый
  код: BUSY-диагностика `tx_begin_failed`).
- **Red check**: реверт на IMMEDIATE → пин падает `tx_begin_failed`.
- **Not touched**: CAS/revision-бампер, save/rollback-пути.

### (12c) Схемные пробы сваливают ошибки в «объект отсутствует» (п.23)

- **Defect (re-verified)**: `Bridge/SQLite/SchemaContract.hs` —
  `tableExists`/`columnMissing`/`indexExists`/`triggerExists`/
  `ftsTableExists` при prepare-failure печатают в stderr и
  возвращают «нет» (`tableExists` :264 → `False`; `columnMissing`
  :276 → `True`); `readSchemaVersionRow` (:229) при prepare-failure →
  `Nothing` → «версия пуста». Следствие: битый файл БД
  классифицируется как `SchemaContractFreshBootstrapable`,
  `readSchemaVersion` врёт `SchemaVersionMissingTable`, и
  bootstrap-решения строятся на ложном факте.
- **Fix**: трёхзначный `ProbeOutcome = ProbeFound | ProbeNotFound |
  ProbeFailed Text` во всех пробах; `readSchemaVersion` получает
  конструктор `SchemaVersionProbeError Text`; `isV1Shape`/`isV2Shape`
  прокидывают ошибку (`Either Text Bool`) вместо `False`;
  `ensureSchemaMigrations` при ошибке пробы падает структурной
  ошибкой `schema_probe_failed` ДО любых штамповок/миграций/сидинга;
  `runMigrationStep` при ошибке пробы не выполняет `ALTER`;
  `checkSchemaContract` мапит ошибку в существующий
  `SchemaContractQueryFailed` (Health уже трактует non-Ok как
  нездоровый).
- **Pins**: (i) мусорный файл БД («not a database») →
  `tableExists` = `ProbeFailed`, `columnMissing` = `ProbeFailed`,
  `readSchemaVersion` = `SchemaVersionProbeError` (старое:
  `False`/`True`/`MissingTable` — ложные факты); (ii)
  `checkSchemaContract` на мусорном файле = `SchemaContractQueryFailed`
  (старое: `FreshBootstrapable` — «повреждение = свежая БД»);
  (iii) bootstrap на БД с несовместимой таблицей `schema_version`
  (нет колонки `version`) → `schema_probe_failed`, до штампа/сидинга
  (старое: падение позже с `schema_version_insert`); в обеих версиях
  проверяется, что строка версии не появилась и сид-таблицы пусты.
- **Red check**: реверт проб → (i)/(ii) падают ложными фактами.
- **Not touched**: списки таблиц/колонок/индексов контракта; текст
  `renderSchemaContractResult` для старых конструкторов.

### (12d) `insertSchemaVersion` глотает ошибки; rollback после commit (п.22)

- **Defect (re-verified)**: `Bootstrap.hs:192–202` — результаты
  `bindInt`/`bindText`/`step` отбрасываются (`_ <-`), `finalize` под
  `tryQxFx0`: INSERT может не состояться, функция «успешна».
  `runPendingMigrations` (:221) держит `finally (rollbackOnException
  db)` — ROLLBACK выполняется и после успешного COMMIT.
- **Fix**: проверка bind/step; при любой ошибке —
  `schema_version_insert` с деталью; finalize best-effort ровно один
  раз; rollback — только при незакоммиченной транзакции (флаг
  `committedRef`).
- **Pins**: (i) прямая: таблица `schema_version` с неудовлетворимой
  NOT NULL-колонкой → `insertSchemaVersion` бросает
  `schema_version_insert` (старое: молчаливый «успех», строки нет);
  (ii) миграционная атомарность: v1-БД + та же ловушка →
  `ensureSchemaMigrations` падает И ALTER'ы откатаны
  (`turn_quality.warranted_mode` отсутствует) — старое: COMMIT
  сохранял ALTER'ы.
- **Red check**: реверт — (i) не бросает, (ii) колонка остаётся.
- **Not touched**: `resolveMigrationSteps`, sequence-пути
  `ensureSchemaMigrations`, конструкторы `SchemaContractResult`.

---

## (13) Boot-загрузчики: границы catch-типов и async-отмена (аудит п.12/26)

Вход батча 4. Бар зарегистрирован ДО изменения поведения (2026-10-20).
Группа объединяет п.12 (catch-типы против throw-типов в boot-загрузчиках)
и п.26 (Async-отмена глотается): общий дефект — граница загрузки
ресурсов не различает ожидаемые классы ошибок и отмену.

### Defect (re-verified по коду HEAD `19650dc`)

- **п.26**: `Runtime/Session/Bootstrap.hs` `initializeAutonomousStorage`
  (`try` над schema-init, `Left (err :: SomeException)` → `NSQL.close` +
  `Left Text`). `ThreadKilled`/`UserInterrupt` во время bootstrap
  превращается в «storage initialization failed; worker disabled»
  (`spawnAutonomousLearningHandles`), отмена не доходит. Прецедент
  правильного поведения — `Engine.hs:236` (`try` + rethrow
  `AsyncException`), уже вынесен в `ExceptionPolicy.tryAsync`.
- **п.12 (catch-тип против throw-типа)**:
  - `Semantic/Ontology.hs` `loadOntology` на битой строке бросает
    `RuntimeInitError` (QxFx0Exception); bootstrap-сайт
    (`Bootstrap.hs:685`) ловит только `IOException`
    (`try @IOException`) → документированный fallback «classifier
    falls back to lexical markers» для parse-ошибки недостижим:
    bootstrap падает.
  - `loadCuratedPredicates` — то же: parse-ошибка = `RuntimeInitError`,
    сайт (`Bootstrap.hs:478`) ловит `IOException` → fallback «seed
    corpus only» недостижим.
  - self-play (`Bootstrap.hs:516–520` → `Ingest.mergeSelfPlayRelations`
    → `loadRelations`): сайт не защищён вовсе; битый JSONL/чтение —
    bootstrap падает. (`ingestExternalKnowledge` свой загрузчик уже
    защищает `tryIO`+`tryQxFx0`; self-play — нет.)
  - `Semantic/Network/Substrate.hs` `loadBrainKB`: `doesFileExist` →
    `BS.readFile` без защиты; read-ошибка (EACCES и т.п.) вылетает из
    bootstrap (задумано: «empty substrate is non-fatal»).
  - `Semantic/Lexicon/RuntimeParadigms.hs`
    `loadDefaultRuntimeParadigms`: `doesFileExist` → `BS.readFile` без
    защиты; комментарий в `Bootstrap.hs` обещает «load failure is
    non-fatal: empty set degrades to JSON», обещание покрывает parse,
    но не чтение.
  - `Runtime/Session/SelfConfig.hs`: `decodeOrFallback` /
    `loadTunedOrDefaultIO` читают `BS.readFile` без защиты;
    `resolveSelfConfigPath` вызывает `getDataFileName` без защиты →
    read-ошибка конфига вылетает вместо builtin-fallback.
  - `Bridge/NativeSQLite.hs` `columnText` декодирует строго
    (`decodeUtf8`) и бросает `UnicodeException` — не
    `QxFx0Exception`; Engine turn-boundary (`Engine.hs:81`) ловит
    только `QxFx0Exception` → невалидный UTF-8 в текстовой колонке БД
    вылетает из governed-пути (state-blob уже читается через
    `columnTextLenient`).

### Policy (locked)

- **Граница boot-ресурсов — ожидаемые классы, не catch-all**: новый
  канонический helper `ExceptionPolicy.tryBootResource` ловит ровно
  `QxFx0Exception` (структурная ошибка загрузчика) и `IOException`
  (чтение), `AsyncException` **перебрасывает**, всё остальное
  (программная ошибка) **перебрасывает**. Catch-all не используется:
  неожиданный класс должен оставаться громким.
- **п.26 — отдельно catch-all-minus-async**: `initializeAutonomousStorage`
  сохраняет прежнюю контейнмент-семантику (`Left Text` для любой
  синхронной ошибки schema-init), но `AsyncException` перебрасывает —
  `tryAsync`. Соединение закрывается и при async-отмене (иначе утечка).
- **Fallback-значения не меняются**; каждый fallback логируется WARN с
  путём/причиной (существующие сообщения сохраняются). Новых
  trace-полей нет.
- **DB-граница — lenient**: `columnText` = `decodeUtf8With
  lenientDecode` (U+FFFD); `columnTextLenient` сохраняется как
  compat-имя с той же семантикой. Строгий декод из границы убирается;
  Engine catch-тип не меняется (дефект исчезает у источника).
- **Разделение «ресурс vs данные»**: битый UTF-8 в checked-in
  ресурсе остаётся громким (строгий декод внутри `loadOntology` не
  трогаем — это ошибка репозитория/сборки), невалидный UTF-8 в БД
  деградирует lenient (данные может испортить внешний писатель).

### Sites / fix

1. `initializeAutonomousStorage` → `tryAsync`; тестовый шов
   `initializeAutonomousStorageWith :: (QxFx0DB -> IO ()) -> FilePath
   -> IO (Either Text QxFx0DB)` (production-путь = прежний
   schema-init), экспорт из `QxFx0.Runtime.Session.Bootstrap` для
   детерминированного async-пина.
2. `tryBootResource` в `ExceptionPolicy` (+ экспорт).
3. Ontology-сайт → новый `loadOntologyForBootstrap` на
   `tryBootResource` (fallback `emptyOntology`, WARN сохранён).
4. Curated-сайт → `tryBootResource` + новый
   `loadBootstrapDefinitionCorpusFrom :: FilePath -> IO (Map Text
   DefinitionContent)`; старый no-arg wrapper резолвит путь и зовёт
   его.
5. Self-play-сайт → новый `mergeSelfPlayRelationsForBootstrap ::
   FilePath -> SemanticNetwork -> IO SemanticNetwork` на
   `tryBootResource` (fallback = базовый network, WARN).
6. `loadBrainKB`: чтение под `tryIO`; Left → `[]` (missing-file
   поведение то же); WARN «0 entries» уже на сайте.
7. `loadDefaultRuntimeParadigms`: новый `loadRuntimeParadigmsFrom ::
   FilePath -> FilePath -> IO RuntimeParadigms`; чтение под `tryIO`,
   Left → WARN + `mempty` по файлу; дефолтный путь зовёт его.
8. `SelfConfig`: чтение под `tryIO` (`decodeOrFallback`,
   `loadTunedOrDefaultIO`), `getDataFileName` под `tryIO`; Left →
   stderr-WARN + builtin/base-fallback (сообщения о parse сохранены).
9. `columnText` → lenient; `columnTextLenient` — alias той же
   семантики.

### Pins (bar)

Новый `Test.Suite.BootBoundary` (unit+fast+main; детерминированные
temp-файлы, без session-bootstrap) — 9 кейсов, плюс 1 кейс в
`Test.Suite.NativeSQLiteNulls` (fast):

1. **async (п.26)**: `initializeAutonomousStorageWith (\_ -> throwIO
   ThreadKilled) tmpDb` под `try @AsyncException` → `Left ThreadKilled`
   (старое: `Right (Left ...)` — отмена съедена).
2. **sync containment**: тот же шов с `userError "boom"` →
   `Right (Left text)` (содержит «boom») — прежняя семантика цела.
3. **классы `tryBootResource`**: `userError "io"` → `Left`;
   `ErrorCall "bug"` → пробрасывается (программная ошибка громкая);
   `ThreadKilled` → пробрасывается.
4. **ontology parse**: temp-файл «not json» →
   `loadOntologyForBootstrap` = `emptyOntology`, без исключения
   (старое: QxFx0Exception вылетал из `try @IOException`).
5. **curated parse**: temp-файл с битой строкой →
   `loadBootstrapDefinitionCorpusFrom` = `definitionCorpus` (seed),
   без исключения (старое: вылетал).
6. **self-play parse**: temp-файл «not json» →
   `mergeSelfPlayRelationsForBootstrap` = базовый network, без
   исключения (старое: вылетал).
7. **brain_kb read**: файл mode 000 → `loadBrainKB` = `[]`, без
   исключения (старое: IOException). *Root-skip*: под euid 0 тест не
   выполняется (root игнорирует mode bits) — фиксируется в лендинге.
8. **paradigms read/parse**: mode 000 + отдельно битый JSON →
   `loadRuntimeParadigmsFrom` = `emptyRuntimeParadigms`, без исключения
   (старое: read-ошибка вылетала; parse уже деградировал).
9. **SelfConfig read**: mode 000 → `loadConfigOrBuiltinIO` = builtin,
   без исключения; `loadTunedOrDefaultIO` с нечитаемым tuned →
   base/builtin (старое: IOException).
10. **columnText lenient** (`Test.Suite.NativeSQLiteNulls`, fast):
    `INSERT ... CAST(X'80' AS TEXT)` → `columnText` возвращает текст с
    U+FFFD, без `UnicodeException` (старое: бросал);
    `columnTextLenient` — тот же результат.

### Red check

По одному реверту на класс: (i) `tryAsync`→`try` в шве → пин 1
падает; (ii) `tryBootResource`→`try @IOException` на ontology-сайте →
пин 4 падает (исключение); тот же реверт на curated/self-play → пины
5/6; (iii) снятие `tryIO` в `loadBrainKB`/paradigms/SelfConfig → пины
7/8/9; (iv) `columnText`→строгий декод → пин 10. Пин 3 падает, если
`tryBootResource` станет catch-all (ErrorCall не пробрасывается).

### Not touched

- Fallback-значения и существующие WARN-тексты; `loadBrainKB`
  parse-skip; `ingestExternalKnowledge` (уже защищён);
  `loadBootstrapSqlSet` (различает свои два класса); Engine
  catch-тип; строгий декод checked-in ресурсов.

---

## (14) Feedback mirror: самовосстановление и атомарная перезапись (аудит п.9)

Вход второго пункта батча 4. Бар зарегистрирован ДО изменения
поведения (2026-10-21).

### Defect (re-verified по коду HEAD `9354adc`)

`Semantic/Network/Feedback/Persist.hs` — зеркало обратной связи
(`resources/config/tuned_relation_weights.jsonl`):

- **Чтение бросает на битой строке**: `loadExisting` зовёт
  `loadRelations` (`Semantic/Network/Ingest.hs`), который на любой
  невалидной JSONL-строке бросает `RuntimeInitError`
  (`RELATION_PARSE_ERROR`). Вызов идёт из
  `runBestEffortPostCommit "feedback_mirror"` (`Finalize/Commit.hs`),
  поэтому ход не падает, но перезапись отменяется — и битая строка
  остаётся навсегда: каждая следующая обратная связь снова упирается
  в неё. Зеркало заклинивает до ручной правки.
- **Запись неатомарна**: `BL.writeFile path` усекает целевой файл до
  записи; падение/убийство процесса посреди записи оставляет
  частичный JSONL — который тот же бросающий ридер затем считает
  фатальным (замыкание цикла «обрезали → заклинило»).
- **Ошибка чтения неотличима от отсутствия файла**: read-ошибка
  (EACCES и т.п.) вылетает наружу (best-effort её глотает), при этом
  файл не перезаписывается — но и диагностики, кроме общего WARN
  post-commit, нет.

### Policy (locked)

- **Ридер зеркала — устойчивый** (практика `loadBrainKB`/П4.3):
  строки декодируются по одной (`eitherDecodeStrict ::
  Either String LoadedRelation`), битые пропускаются с одним WARN
  (путь + число пропущенных). Отсутствующий файл = пустая база.
- **Read-ошибка (кроме отсутствия) — запрет перезаписи**: функция
  возвращается, не трогая файл (WARN); история не затирается из-за
  транзиентного сбоя. Исключение наружу не бросается.
- **Запись атомарна**: уникальный temp-файл в той же директории
  (`openTempFile`) → полная запись → `hClose` → `renameFile` поверх
  цели; при любой ошибке temp закрывается и удаляется
  (best-effort), цель остаётся прежней целой. Это же убирает
  «частичный JSONL после kill».
- **Best-effort-вызов не меняется**: `runBestEffortPostCommit`
  остаётся; write-ошибка по-прежнему может бросить и логируется
  вызывающим. Формат JSONL и семантика merge (заменить изменённые
  рёбра, сохранить остальные) не меняются.
- **Новых trace-полей нет**; наблюдаемость — WARN в stderr.

### Pins (bar)

Новый `Test.Suite.FeedbackMirror` (unit+fast+main, temp-файлы,
5 кейсов):

1. **Битая строка не клинит зеркало**: файл = валидное ребро +
   `not json` + второе валидное ребро; `persistFeedbackNetwork` с
   одним изменённым ребром → без исключения; итоговый файл целиком
   парсится, оба валидных ребра сохранены, изменённое добавлено,
   битой строки нет (старое: `RELATION_PARSE_ERROR`).
2. **Read-ошибка не затирает**: файл mode 000 (root-skip) →
   функция возвращается без исключения, байты файла не изменились
   (старое: IOException).
3. **Отсутствующий файл создаётся**: пути нет → файл создан, каждая
   строка парсится, содержит изменённое ребро (пин первого пути
   записи).
4. **Атомарная замена (структурный пин)**: inode цели до и после
   успешной перезаписи различается (`getFileStatus`/`fileID`), т.е.
   файл заменён через rename, а не переписан на месте; temp-файлов в
   директории не осталось (старое: inode тот же — `BL.writeFile`).
5. **Сбой записи убирает temp**: цель — директория (rename/write
   невозможны) → исключение наружу (best-effort-контракт), temp не
   остался, цель-директория цела.

### Red check

- реверт ридера на `loadRelations` → пин 1 падает
  `RELATION_PARSE_ERROR`;
- реверт обработки read-ошибки на «бросить» → пин 2 падает
  IOException;
- реверт записи на `BL.writeFile` → пин 4 падает (inode не
  изменился);
- снятие очистки temp → пин 5 падает (temp остался).

### Not touched

- `loadRelations`/ingest (бросающий контракт остаётся для курируемых
  корпусов; зеркало — runtime-данные);
- путь зеркала и handler (`Runtime/Wiring/Handlers.hs`);
- `runBestEffortPostCommit`; формат JSONL; merge-семантика.

### Honest limits

- Настоящую crash-атомарность (kill -9 посреди записи) нельзя
  проверить in-process без инъекции сбоев; пин 4 проверяет
  структурно (inode меняется = rename-механика), пин 5 — очистку
  temp на пути ошибки.
- `openTempFile` создаёт temp с mode 0600, тогда как `BL.writeFile`
  давал 0644; зеркало — локальные runtime-данные, потребителей с
  другим uid нет (отмечается как осознанное изменение режима).

---

## (15) Кризисный лексикон: первое лицо для EN и объект для «хочу покончить» (аудит п.25)

Вход третьего пункта батча 4. **Safety-бар**: зарегистрирован ДО
изменения лексикона (2026-10-21). Действует операторское правило
«кризисная лексика — только в сторону полноты»: ни одна острая
формулировка не теряет срабатывание; сужение голых infix-паттернов
допускается только с компенсацией и расширенной батареей.

### Defect (re-verified по коду HEAD `4103d04`)

- EN: `suicide` и `suicidal` — голые infix-маркеры
  (`Safety/CrisisGuard.hs`), поэтому топикальная/мета-фраза
  включает Protocol B: «suicide is a philosophical problem»,
  «the novel discusses suicide». EN-декоя-теста нет.
- RU: `хочу покончить` без объекта — «хочу покончить с работой»
  включает Protocol B.
- RU-стем «самоубий» исключён сознательно (Camus-ловушка) —
  не трогаем.
- Положительное EN-покрытие тонкое: при сужении без компенсации
  потерялись бы «thinking about suicide» и первые лица.

### Policy (locked, recall-first)

1. **Острая покрываемость только растёт.** Текущая положительная
   батарея (`Test.Suite.CrisisGuard`) остаётся зелёной; новые
   маркеры добавляются вместе с сужением, а не после.
2. **EN — первое лицо и акт**: из infix-списка убираются голые
   `suicide` и `suicidal`. Добавляются: `i am suicidal`,
   `i'm suicidal`, `im suicidal`, `i feel suicidal`,
   `feeling suicidal`, `i have suicidal thoughts`,
   `i'm having suicidal thoughts`, `im having suicidal thoughts`,
   `thinking about suicide`, `thinking of suicide`,
   `want to commit suicide`, `wants to commit suicide`,
   `going to commit suicide`, `plans to commit suicide`,
   `take my own life`, `ending my life`, `do not want to live`,
   `is suicidal`, `are suicidal`, `committed suicide`,
   `suicide attempt`, `suicide note`.
3. **Терсный ввод не теряется**: новый список
   `acuteCrisisExactMarkers` (`suicide`, `suicidal`) проверяется
   первым по нормализованному вводу, очищенному от окружающей
   пунктуации и пробелов; `Suicide!` и `suicidal.` срабатывают,
   топикальная фраза — нет.
4. **RU — объект**: `хочу покончить` убирается из infix; острые
   завершения покрываются `покончить с собой` (уже есть) и новыми
   `покончить с жизнью`, `покончить жизнь самоубийством`.
   Добавляются: `покончу с собой`, `покончил с собой`,
   `лишить себя жизни`, `расстаться с жизнью`,
   `совершить самоубийство`, `совершу самоубийство`,
   `планирую самоубийство`.
5. **Ресурсы не меняются**: `crisisResourcesRu`, `crVersion`,
   `renderCrisisSurface`, `decideProtocol`, Engine-префлайт и
   R5-контур не трогаются; меняется только лексикон и детектор.
6. Детерминизм: точные маркеры (в порядке списка) → infix-маркеры
   (в порядке списка); первый матч выигрывает. `acuteCrisisMarkers`
   остаётся экспортированным; новый `acuteCrisisExactMarkers`
   экспортируется рядом.

### Pins (bar)

Расширение `Test.Suite.CrisisGuard` (новые кейсы; регистрация не
меняется — suite уже в unit+fast+main):

- EN-позитивы: все первые лица/акты из п.2, включая
  `thinking about suicide` (существующий позитив),
  `my friend committed suicide`, `she survived a suicide attempt`,
  `he left a suicide note`;
- терсный ввод: `suicide`, `suicidal`, `Suicide!`, `suicidal.`;
- RU-позитивы: острые завершения и формы из п.4, включая
  `он покончил с собой`;
- EN-декои: `suicide is a philosophical problem`,
  `the novel discusses suicide`,
  `suicidal thoughts are a theme in the book`,
  `camus wrote about suicide as a philosophical question`,
  `suicide rates have declined`;
- RU-декои: `хочу покончить с этой работой`,
  `хочу покончить с проектом`;
- существующие позитивы/декои/нормализация/обфускация — без
  изменений и зелёные;
- `every marker non-empty` расширяется на точный список.

### Red check

- вернуть `suicide`/`suicidal` в infix → EN-декои падают;
- вернуть `хочу покончить` → RU-декои падают;
- отключить точное сравнение → терсные `suicide`/`Suicide!` падают;
- убрать новые RU/EN-маркеры → соответствующие позитивы падают.

### Not touched

- `crisisResourcesRu`, `crVersion`, `renderCrisisSurface`,
  `decideProtocol`, Engine-префлайт, R5-контур;
- RU-стем «самоубий» (остаётся исключённым);
- `normalizeCrisisInput` (хелпер очистки пунктуации для точных
  маркеров живёт рядом с детектором; нормализация ввода не
  меняется);
- `Semantic.Markers` (не кризисный лексикон).

### Honest limits

- Точное сравнение покрывает только терсные EN-формы
  `suicide`/`suicidal`; терсное RU `самоубийство` остаётся
  не-маркером (сознательное решение из-за Camus-ловушки).
- Топикальные EN-фразы без первого лица/акта больше не запирают
  Protocol B — это цель сужения; положительная батарея
  компенсирует острую покрываемость.
- Третьеличные отчёты покрываются акт-фразами
  (`committed suicide`, `suicide attempt`, `suicide note`,
  `is/are suicidal`), а не любым упоминанием слова; описание
  вымышленного персонажа («the protagonist is suicidal») может
  сработать — сознательный recall-first компромисс.

---

## (16) SessionLock: эвикция не должна расщеплять сессию (аудит п.27)

Вход четвёртого пункта батча 4. Бар «воспроизведение сначала»:
сценарий-тест регистрируется ДО фикса (2026-10-21).

### Defect (re-verified по коду HEAD `6d50cbf`)

`Core/SessionLock.hs`: `getOrCreateLock` возвращает `MVar` записи, а
`withSessionLock` берёт его отдельным шагом (`withMVar`). Между
этими шагами запись уже в `Map` и её `MVar` свободен, поэтому
конкурентный `evictFreeTrackedLock` может её вытеснить: `tryReadMVar`
видит свободу, LRU-CAS удаляет запись. Второй вызов той же сессии
не находит её в `Map`, создаёт **новый** `MVar`, и две критические
секции одной сессии идут параллельно. Инвариант «одна сессия — одна
критическая секция» нарушается под давлением cap.

Существующий overflow-путь (общий шард) сам по себе безопасен;
дефект — только в эвикции отслеживаемой записи.

### Reproduction (bar, до фикса)

Тестовые швы (поведение production не меняют):

- `newSessionLockManagerWithCap :: Int -> IO SessionLockManager` —
  конструктор с явным cap (без глобального env);
- `withSessionLockPaused mgr sid hook action` — хук после
  регистрации/пина и до захвата `MVar`; production
  `withSessionLock` = тот же путь с `pure ()`.

Сценарий (cap 1, детерминированный, только MVars):

1. поток A: `withSessionLockPaused "a" hookA`; `hookA` сигналит и
   ждёт; A ещё не взял `MVar`;
2. main: `withSessionLock "b" (pure ())` — под cap 1 эвикция
   вытесняет запись «a» (она свободна) и ставит «b»;
3. main: отпускает A; A входит в критическую секцию и висит на
   `aRelease`;
4. поток C: `withSessionLock "a"` — на HEAD «a» уже не в `Map`,
   создаётся новый `MVar`, C входит **параллельно** A;
5. бар: C не должен войти, пока A внутри (проверка «C не вошёл за
   500 мс»), и должен войти после `aRelease`.

На HEAD шаг 5 падает (C входит), после фикса — зелёный.

### Policy (locked)

- **Пин при выдаче**: `acquireSessionLock` атомарно (STM) либо
  находит запись и увеличивает `slePins`, либо вставляет новую с
  `slePins = 1`; `withSessionLockPaused` снимает пин в `finally`.
  Эвикция выбирает только записи с `slePins == 0` и свободным
  `MVar`; CAS перепроверяет пин, метку и cap.
- **Ретрай**: если CAS эвикции не удался, но место появилось
  (другой эвиктор уже удалил запись), вставка повторяется один раз;
  иначе — overflow-шард (без пина).
- **Один пин на выдачу**, включая путь существующей записи; release
  идемпотентен и no-op для шарда/недостижимого fallback.
- **Наблюдаемость**: `SessionLockStats` получает `slsPinnedLocks`
  (сумма пинов) и `slsEvictions` (успешные LRU-эвикции);
  `slsTrackedLocks`/`slsOverflowActive` не меняются.
- Overflow-шарды, LRU-метки, cap и env-контракт
  (`QXFX0_MAX_SESSION_LOCKS`) не меняются.

### Pins (bar)

Новый `Test.Suite.SessionLockOverflow` (unit+fast+main):

1. **детерминированный сценарий**: C не входит, пока A внутри; C
   входит после release; `slsPinnedLocks == 0` в конце;
2. **стресс-инвариант**: 4 потока × 200 итераций на двух сессиях
   при cap 1 — максимум одновременных входов на сессию = 1;
3. **release при исключении**: действие бросает — исключение
   выходит, `slsPinnedLocks == 0`, сессия снова доступна;
4. **эвикция по-прежнему работает**: cap 1, две сессии
   последовательно — `slsTrackedLocks` = 1, `slsOverflowActive`,
   `slsPinnedLocks == 0` после каждой, `slsEvictions` растёт на
   каждой вставке сверх cap; третья сессия завершается
   (overflow-шард);
5. **счётчик пинов виден**: во время удержания критической секции
   из другого потока `slsPinnedLocks >= 1`.

### Red check

- заменить пин на 0 (эвикция снова видит свободную запись) → пин 1
  падает;
- убрать release в `finally` → пин 3 падает (`slsPinnedLocks` не
  возвращается к 0);
- разрешить эвикцию записи с `slePins > 0` → пин 1 падает.

### Not touched

- overflow-шарды (`pickOverflowShard`, 64 шарда), LRU-семантика,
  `QXFX0_MAX_SESSION_LOCKS`, `resolveMaxTrackedLocks`;
- `Runtime/Wiring/Context.hs` (вызов `withSessionLock` не меняется);
- формат статистики: только новое поле.

### Honest limits

- Проверка «C не вошёл за 500 мс» — расписательная: на
  перегруженной машине она может дать ложный зелёный на HEAD
  (red-чек снят на простаивающей машине); для фиксированного кода
  направление безопасное (медленная машина не создаёт ложного
  падения).
- Стресс-пин вероятностный (сеть против регрессий, не
  доказательство); детерминированный сценарий — основной бар.
- Швы `newSessionLockManagerWithCap`/`withSessionLockPaused`
  экспортируются для тестов; production-путь — `newSessionLockManager`/
  `withSessionLock`.

---

## (17) SQLite: threaded RTS, safe FFI и acquire без гонки timeout/takeMVar (аудит п.19)

Вход пятого пункта батча 4 — отдельный перф/конкурентность-фронт.
Бар зарегистрирован ДО изменения поведения (2026-10-21). Timing-
тесты по решению 2026-10-16 не пишутся как latency-бар; единственный
timing-sensitive пин проверяет не скорость, а прогресс Haskell во
время блокирующего FFI (функциональный инвариант).

### Defect (re-verified по коду HEAD `4fcf839`)

- `Bridge/NativeSQLite.hs`: все 18 `foreign import ccall unsafe`,
  включая блокирующие `sqlite3_open/close/prepare_v2/step/exec`.
  При `busy_timeout=5000` блокирующий step держит capability до 5 с.
- Runtime собран **без** `-threaded`: `+RTS --info` даёт `rts_v`
  (vanilla) у `qxfx0-main` и всех тестовых бинарников. Поэтому
  `safe` FFI сам по себе ничего не даст: без threaded RTS нет
  второго OS-потока, которому можно отдать capability. Фронт
  обязан включать `-threaded` (без фиксации `-N`: default 1
  capability; safe-вызов освобождает её на время блокировки).
- `Bridge/SQLite/Pool.hs:withPooledDB`: `timeout 5s (takeMVar
  poolMVar)` — асинхронное исключение `timeout` может прийти
  после успешного `takeMVar`, но до возврата `Just`: соединение
  вынуто и потеряно (не возвращено в пул и не закрыто). Гонка
  timeout/takeMVar, отмеченная аудитом. Сейчас она прикрыта
  процесс-глобальным `withDatabaseActionLock` (контеншена пула
  внутри процесса нет), но остаётся дефектом защитного пути.

### Policy (locked)

1. **Threaded RTS**: `-threaded` добавляется executables и
   `test-common` (link-time); `-N` не фиксируется. Library не
   меняется.
2. **safe FFI только для блокирующих**: `sqlite3_open`,
   `sqlite3_close`, `sqlite3_prepare_v2`, `sqlite3_step`,
   `sqlite3_exec` → `safe`. Биндинги, колонки, `errmsg`,
   `finalize` и wrapper `bind_text_transient` остаются `unsafe`
   (не блокируют; `safe` дал бы только overhead).
3. **Acquire без async-исключения**: вместо `timeout` вокруг
   `takeMVar` — polling `tryTakeMVar` с дедлайном
   (`GHC.Clock.getMonotonicTimeNSec`) и `threadDelay 1000`; по
   дедлайну — тот же `SQLiteErrorStructured "pool_acquire"
   "TIMEOUT"`. `tryTakeMVar` не может «вынуть и потерять»:
   значение либо возвращено, либо осталось в MVar.
4. **Швы**: `withPooledDBTimeout :: Int -> WorkerDBPool -> ...`
   (микросекунды; production `withPooledDB = withPooledDBTimeout
   5000000`), `acquireConnectionsWithTimeout :: MVar [Database] ->
   Int -> IO [Database]` (unit-тест таймаута на пустом MVar) и
   `poolAvailableConnections :: WorkerDBPool -> IO Int`
   (наблюдаемость размера пула). Все три — аддитивные,
   документированы как тестовые.
5. Поведение действия, транзакции, busy_timeout, WAL,
   `withDatabaseActionLock` и формат ошибок не меняются.

### Pins (bar)

Новый `Test.Suite.SQLiteRuntime` (unit+fast+main):

1. **blocking FFI не морозит Haskell**: соединение A держит
   `BEGIN EXCLUSIVE`, соединение B делает INSERT с
   `busy_timeout=1000` (блокируется ~1 с); тикер (10 мс)
   увеличивает счётчик. Дельта за время блокирующего вызова
   ≥ 20 — Haskell-поток прогрессировал. На vanilla RTS или при
   `unsafe` step дельта = 0 (red). Это функциональный инвариант,
   не latency-бар.
2. **acquire-таймаут структурный и без потерь**: на пустом
   `MVar` `acquireConnectionsWithTimeout` с 50 мс возвращает
   `SQLiteErrorStructured` с кодом `TIMEOUT`; после `putMVar`
   тот же вызов возвращает ровно положенное значение (пул не
   потерян).
3. **размер пула стабилен**: `newDBPool` на 2 соединения,
   10 последовательных `withPooledDB`, затем
   `poolAvailableConnections` = 2.
4. существующие SQLite/пул-тесты зелёные (регрессия).

### Red check

- вернуть `unsafe` для `sqlite3_step`/`sqlite3_exec` (при
  `-threaded`) → пин 1 падает (дельта 0);
- убрать `-threaded` из `test-common` → пин 1 падает;
- вернуть `timeout` вокруг `takeMVar` → пин 2 остаётся зелёным на
  пустом MVar (гонка вероятностная), поэтому структурный реверт
  фиксируется ревью и пин 1/3 не затрагивает; honest limit ниже.

### Not touched

- SQLite schema, транзакции, WAL, busy_timeout, `withDB`,
  `withDatabaseActionLock`, `sanitizeForPool`;
- `-N`/capabilities (default 1), никаких новых фоновых потоков;
- формат ошибок: тот же `SQLiteErrorStructured`.

### Honest limits

- Пин 1 timing-sensitive: на сильно загруженной машине возможен
  ложный зелёный (тикер успел до вызова), поэтому порог ≥ 20 при
  блокировке ~1 с и сброс счётчика непосредственно перед вызовом;
  главный контроль — структурный (`safe` + `-threaded`).
- Гонка timeout/takeMVar на HEAD вероятностная и прикрыта
  action-lock; пин 2 проверяет наблюдаемое поведение таймаута, а
  не гонку. После фикса гонка структурно невозможна
  (`tryTakeMVar`).
- `-threaded` меняет RTS целиком: полная матрица обязательна;
  поведенческие тесты рантайма — основной контроль.

---

## (18) SessionLock: overflow-шард не должен расщеплять сессию (фикс к п.27, найден п.19)

Вход — по красной матрице п.19 (2026-10-22): `-threaded` изменил
планировку, и стресс-пин п.27 упал:
`max concurrent entries per session must be 1, got: fromList [("a",2),("b",2)]`.

### Defect (re-verified по коду HEAD `915c736`)

`acquireSessionLock` при переполнении cap и неудачной эвикции
выдаёт overflow-шард, **не регистрируя сессию в `slmLocks`**.
Конкурентный acquire той же сессии может в этот момент вставить
tracked-запись (если место освободилось) и получить независимый
`MVar`: две критические секции одной сессии идут параллельно —
tracked и шардовая. Пин п.27 закрывал окно «выдача → захват» для
tracked-записей, но не для overflow-пути; под vanilla RTS гонка
была редкой, под `-threaded` — частая (бар поймал её в fast-прогоне).

### Policy (locked)

- Overflow-путь становится записью в том же реестре:
  `SessionLockEntry` получает `sleOverflow :: Bool`; при
  невозможности вставить tracked-запись сессия атомарно
  вставляется в `slmLocks` с `sleLock = шард`, `slePins = 1`,
  `sleOverflow = True` (размер карты может превысить cap на число
  активных overflow-сессий; они транзиентны).
- `releaseSessionLock` при `slePins == 1` и `sleOverflow` удаляет
  запись; иначе уменьшает пин.
- Все пути входа (lookup, insert, eviction CAS, retry, overflow)
  проверяют сессию в одной STM-транзакции с мутацией — тотальный
  порядок на `slmLocks` закрывает окно.
- Эвикция по-прежнему выбирает только `slePins == 0` и свободный
  `MVar`; overflow-записи с пином 0 эвикцируемы. Cap, 64 шарда,
  `SessionLockStats` и env-контракт не меняются;
  `slsTrackedLocks` теперь включает активные overflow-записи
  (документировано).
- `pickOverflowShard`/`sessionLockOverflowShardIndex` не меняются.

### Pins (bar)

`Test.Suite.SessionLockOverflow` получает 6-й детерминированный
кейс «overflow-запись сериализуется с последующим tracked-входом»:

1. cap 1; C держит tracked-запись «c» через
   `withSessionLockPaused` (пин, до захвата `MVar`);
2. B входит в «a»: insert/evict/retry невозможны → overflow;
3. C отпускают; A входит в «a»: на HEAD A эвиктит C и вставляет
   tracked «a» → A и B одновременно; после фикса A пинит
   overflow-запись и ждёт шард;
4. бар: A не входит за 500 мс, пока B внутри; после release B —
   входит.

Существующие 5 кейсов остаются зелёными; стресс-пин гоняется
под `-threaded`.

### Red check

- Отключить overflow-вставку (вернуть выдачу шарда без записи в
  реестр) → новый кейс 6 падает: A входит, пока B внутри.
  Стресс-пин остаётся вероятностным нетом; его красное состояние
  уже наблюдалось в fast-прогоне п.19 (2/2).

### Not touched

- Cap/эвикция/LRU/шарды/статы/env; поведение overflow-сессий во
  времени (они по-прежнему делят шард).

---

## (19) п.13. Внешние guardrails: честные имена и доки (enforcement не возвращается)

Вход — решение 2026-10-17 по п.13 (`AUDIT_2026-10-16.md`): честное
переименование и документирование, как у п.4; принуждение не
возвращается. Объём фиксируется здесь, на входе в батч 4.

### Findings (re-verified на HEAD `c5ede8d`)

- `legacyExternalLearningEnabled = False` (`Learning/Loop.hs:134–135`);
  `applyExternalLearning` и `runLearningStep` в production инертны
  (`disabled_by_policy`, состояние не меняется).
- Заголовок `Learning/Guardrails.hs` обещает enforcement
  («Prevents runaway learning loops by enforcing…»), которого нет:
  единственные вызовы `record*` — в недостижимом теле
  `applyExternalLearning` и в тестах; счётчики `GuardrailState` не
  обновляются ни на одном живом пути.
- `canIssueExternalAction gs _kind turn` игнорирует вид действия, но
  имя и сигнатура обещают kind-зависимый гейт.
- `canSubmitProposal` не имеет production-вызовов (только
  `Guardrails`/`TurnPipelineProtocol` тесты), но имя обещает
  разрешение.
- `Autonomous` не консультируется с `GuardrailState`; это отдельный
  env-gated контур (`QXFX0_AUTONOMOUS_LEARNING`), его безопасность —
  собственные ворота, не эти счётчики.
- Живой трейс при выключенном флаге уже честен:
  `mExternalActionDecisionTrace` = `DeniedNoActionSelected` в ветке
  `otherwise`; `scheduleTurnEffects` не планирует
  `TurnReqExternalQuery`.

### Policy (locked)

- Переименования:
  - `canIssueExternalAction` → `externalActionGuardrailDecision`;
    параметр `ExternalActionKind` удаляется: решение kind-agnostic по
    построению (rate limit/circuit breaker общие для всех внешних
    действий), вид остаётся в трейсе.
  - `canSubmitProposal` → `proposalSubmissionGuardrailDecision`:
    предикат — диагностическая проекция, не разрешение.
- Документация:
  - заголовок `Learning/Guardrails.hs` переписывается: контур
    superseded Phase 8/9, enforcement не является runtime-свойством;
  - пороги, `emptyGuardrailState`, `record*` и `quarantine*`
    помечаются как persisted diagnostic state, обновляемый только
    выключенным путём и тестами; счётчики **не удаляются и не
    оживают**;
  - заголовок `Learning/Loop.hs`: `runLearningStep` и
    `applyExternalLearning` инертны в production при флаге False;
    enabled-тело сохранено для истории/тестов;
  - заголовок `Learning/Autonomous.hs`: worker не консультируется с
    `GuardrailState`; это отдельный контур, а не забытый вызов.
- Без изменений: `legacyExternalLearningEnabled` остаётся False;
  никаких новых проверок в `Autonomous`/`Precommit`; JSON-схема
  `GuardrailState` и replay-трейс не меняются; `TurnReqExternalQuery`
  не планируется.

### Pins (bar)

- Существующие `LearningLoop` пины остаются:
  `testLegacyLearningStepDisabled` (флаг + `disabled_by_policy`) и
  `testLegacyExternalLearningApplyDisabled` (точное состояние).
- Новый `LearningLoop` кейс: непустой `GuardrailState` в состоянии,
  `applyExternalLearning` с валидным ответом → `ssGuardrailState`
  байт-в-байт прежний (счётчики не двигаются) и состояние целиком
  прежнее.
- Новый `Guardrails` кейс: `externalActionGuardrailDecision` —
  пустое состояние → `ExternalActionAllowed`; rate limit →
  `DeniedGuardrailRateLimit`; открытый circuit breaker →
  `DeniedGuardrailCircuitBreaker`.
- Обновить имена в `Guardrails` и `TurnPipelineProtocol` тестах; без
  изменения семантики.
- Счётчики: +2 unit/fast/main (Guardrails 1, LearningLoop 1);
  ожидаемо unit 1813, fast 1911, main 1334 (core 1214); slow 190.

### Red check

- Убрать guard `| not legacyExternalLearningEnabled = ss` в
  `applyExternalLearning` (флаг остаётся False) → новый
  guardrail-inert пин падает (состояние/счётчики меняются); restore.
- `git grep canIssueExternalAction` и `git grep canSubmitProposal`
  → 0 вхождений после переименования (компилятор + grep).

### Not touched

- Пороги, JSON-схема, replay-поля, `Autonomous` admission,
  `Precommit` (по-прежнему вызывает `applyExternalLearning`, который
  инертен), семантика `TurnPipelineProtocol`.

---

## (20) P3-техдолг: четыре низкорисковых пункта + верификация WIP-порогов

Вход — явное «да» пользователя 2026-10-23 на P3-батч; объём: четыре
низкорисковых пункта (`Autonomous` env-клампы, лог `wal_checkpoint`,
`bindText` orFail в query-путях, `lastCharOf`) плюс WIP-порогов.
tmp-fsync и `Prepare/Resolve` fallback в этот батч не входят.

### Findings (re-verified на HEAD `243fc0b`)

- `readAutonomousWorkerConfig` читает девять лимитов через
  `readIntWithDefault` без клампа: `"-3"` доходит до бюджета как -3.
  Парсер `readIntWithDefault` сам по себе обязан сохранять негативы —
  это пин `testReadIntWithDefault` и вызов в `Runtime/Session/Bootstrap`
  с собственным `max 0`.
- `maybeCheckpoint` (`Bridge/SQLite/Queries.hs:102–106`) отбрасывает
  `Either` от `execSql`: `Left` исчезает молча.
- Три `_ <- NSQL.bindText` в `Queries.hs` (queryExactTrigger, queryFTS5,
  queryTopicFallback) игнорируют `Left`. `insertSchemaVersion` в
  `Bootstrap` уже проверяет bind/step (п.22), `TxStatement` имеет
  `bindTextOrFail` только для `TxStmt`.
- `lastCharOf` (`Lexicon/Inflection.hs:33–34`) — `T.index` на
  `length - 1`; пустая строка падает. Единственный вызов —
  `isConsonantEndingInf`; публичные пути (`dativeForm ""`) сегодня до
  него не доходят, поэтому это защитная тотализация, а не живой баг.
- WIP-порогов: `compositionShareFloor` и `analogyFallbackFloor` уже
  извлечены в `Types/Thresholds/Selection.hs` коммитом `e2ecd0d`;
  `compositionShareThreshold`/`analogyDepth` не встречаются ни в
  `src/`, ни в `test/`, ни в доках (кроме строки аудита). Строка P3
  устарела: действие — верифицировать и закрыть, новых констант не
  выдумывать.

### Policy (locked)

- (a) `Autonomous`: добавить `readLimit m d = max 0 (readIntWithDefault
  m d)`, экспортировать, применить к девяти лимитам
  (requests/tokens ×3, reserved tokens, edges, queue cap) и к
  provider timeout внутри существующего `max 1000 (min 300000 …)`.
  `readIntWithDefault` не меняется.
- (b) `maybeCheckpoint`: `case execSql … of Left err -> hPutStrLn stderr
  ("[sqlite] wal_checkpoint failed: " <> T.unpack err); Right () ->
  pure ()`. Не бросать: обслуживание остаётся best-effort, период
  (каждые 100 ходов) не меняется.
- (c) `Queries.hs`: `bindTextOrFail :: Text -> NSQL.Statement -> Int ->
  Text -> IO ()`, экспортировать для пина; `Left` → `throwQxFx0
  (mkSQLiteError operation err Map.empty)`. Заменить три непроверенных
  bind. `Bootstrap` не трогать (уже проверяет).
- (d) `Inflection.hs`: `lastCharOf :: Text -> Maybe Char`
  (`Nothing` для пустой), экспортировать ради прямого пина;
  `isConsonantEndingInf` — `Nothing → False`. Для непустых слов
  поведение не меняется.
- (e) WIP-порогов: только запись в регистр/лендинг о верификации
  `e2ecd0d`; кода нет.

Не трогаем: значения порогов, схему БД, replay-поля, admission
autonomous-очереди, семантику `readIntWithDefault`, tmp-fsync,
`Prepare/Resolve`.

### Pins (bar)

- `Autonomous` (+2, fast-only): `readLimit` — негатив → 0, валидное
  значение, default, мусор; config-пин с env
  `QXFX0_LEARNING_QUEUE_CAP=-5` → `awcQueueCap == 0` (переменная
  восстанавливается).
- `SQLiteRuntime` (+3, main/unit/fast): bind success (`SELECT ?` →
  значение), bind failure (`SELECT 1` + индекс 1 → `SQLiteErrorStructured`
  с `sedOperation = "bindTextOrFail-pin"`), `maybeCheckpoint` 99 —
  no-op, 100 — успешный проход на реальной БД.
- `Lexicon` (+1, main/unit/fast): `lastCharOf "" == Nothing`,
  `lastCharOf "стол" == Just 'т'`, `dativeForm emptyMorphologyData "" ==
  ""`, `dativeForm … "стол" == "столу"` (регресс непустого пути).
- Ожидаемые счётчики: main 1338 (core 1218), unit 1817, fast 1917;
  property 244, integration 47, slow 190 не меняются.

### Red check

- `readLimit` без `max 0` → оба Autonomous-пина падают (негатив
  остаётся отрицательным).
- Вернуть `_ <- NSQL.bindText` → bind-failure пин падает (исключения
  нет, параметр не привязан).
- Вернуть `T.index` в `lastCharOf` → totality-пин падает с
  исключением на пустой строке.
- Для `maybeCheckpoint` инъекция `Left` через публичный DB API
  хрупка (нужны read-only-права); честно фиксируем: гейт-пин
  доказывает проход ветки на 100-м ходу, а `Left`-ветка — типизированный
  one-liner без инъекционного пина.

### Not touched / honest limits

- `maybeCheckpoint` по-прежнему не бросает: лог — наблюдаемость, не
  политика отказа.
- `lastCharOf` экспортируется только ради пина; это внутренний
  тотальный хелпер.

---

# Audit 2026-10-16 fix batch 1 — landing (2026-10-17)

Status: landed; the pre-registered bars above were registered BEFORE
any behavior change and held. Commits: thresholds `e2ecd0d`, p.5
`af05785`, p.1 `911151c`, p.3 `035127b`. Register statuses:
`docs/closure/AUDIT_2026-10-16.md`.

## Threshold registry (decision (3), landed `e2ecd0d`)

Values verbatim; no behavior change. Single address for tuning —
any change here is calibration-grade (pre-register rule + bar; a
math-version bump when an equation moves).

- `QxFx0.Types.Thresholds.Anomaly` (v3.0 detector gates):
  `anomalySelfRefAngst` 0.9, `anomalyCollapseConfidence` 0.95,
  `anomalyAntiConatusConfidence` 0.7, `anomalyAntiConatusAngst` 0.8,
  `anomalyAntiConatusEnergy` 5.0,
  `anomalyAntiConatusConfidenceOut` 0.85,
  `anomalyTemporalConfidence` 0.85, `anomalyUnclassifiableRatio` 0.2.
- `QxFx0.Types.Thresholds.Conatus`: `conatusWeightMorphology` 1.0,
  `conatusWeightIdentity` 0.5, `conatusWeightTurns` 0.25,
  `conatusWeightViolation` 10.0, `conatusLowEnergy` 3.0 (ADR-0045).
- `QxFx0.Types.Thresholds.Selection`: `selectorAffinityFloor` 0.1,
  `selectorBaseMultiplier` 1.0, `selectorBonusRate` 0.3,
  `compositionActivationFloor` 0.05, `compositionShareFloor` 0.3,
  `compositionFallbackBaseScore` 0.3, `analogyFallbackFloor` 0.3,
  `externalToolReliabilityFloor` 0.3, `learningNeedEscalationLevel`
  0.6, `adaptiveSignalEpsilon` 0.15, `activationReportFloor` 0.05,
  `routeHintMargin` 0.05.
- `Types.Thresholds.Constants` re-exports the three modules. Adoption
  hunks inside `Finalize/State.hs` and `Route/Anomaly.hs` landed with
  p.1 / p.3 (noted in those commit messages).

## (1) p.5 crisis preflight — landed (`af05785`)

Bars held as pre-registered; new pins:
`testOverlongCrisisInputStillGetsResources`,
`testStrictGateFailureKeepsCrisisResources`,
`testCliCrisisPreflightChecksRawInputBeforeTruncation` (slow
runtime) and the `Test.Suite.CrisisGuard` preflight case. CLI
semantics confirmed: an over-long crisis input returns the bounded
surface and the session does not advance; over-long calm input keeps
truncate-and-process. In-pipeline detection/persistence untouched;
no trace-schema change.

## (2) p.1 collapse supersession — landed (`911151c`)

Bars held; pins: `testCollapseSupersedesCommitment` (pure,
`Test.Suite.EssenceCollapse`) and
`testFinalizeCollapseSupersedesCommitment` (pipeline,
`Test.Suite.Anomaly`, incl. the fail-closed control on the raw pair).

**Incident — `<<loop>>` caught by the regression matrix.** After the
first implementation, `qxfx0-test-fast` case #1065 (M6FeltBenchmark)
died with `<<loop>>`: the new `mCollapse`-driven store path closed a
strict-field cycle

    mCollapse -> store1/store2 -> store0 -> nextWithLog
      -> (strict ssSelfState) -> nextEssence -> supersede -> mCollapse
      (black hole)

`store0` had read `ssSemanticCommitments nextWithLog`. Root fix:
`store0 = ssSemanticCommitments ss` (pre-turn state) — value-identical,
since neither `baseNext` nor `appendAdaptiveMutationRecords` touches
`ssSemanticCommitments`; the read is the same store without closing
the cycle. The deterministic catch (M6FeltBenchmark) stays as the
pin. No math-version bump: control-flow / reset ordering only, no
equation moved.

## (3) p.3 whole-token self-ref — landed (`035127b`)

Bars held; pin `testSelfReferentialCollapseWholeTokens`
(`Test.Suite.Anomaly`): «философия», «что такое философия?»,
«identity», «моя», «системный», «sistema», «thyself» do not fire;
«я», «ты», «qxfx0», «система», «i», «you», «myself», «yourself»
and case-folded / punctuation-adjacent standalone tokens do; low
angst does not. Detector priority and morphology matching stay as
pre-registered out of scope.

## Verification matrix (landing tree)

unit 1739/1739, fast 1841/1841, property 227/227, integration 47/47
— exit 0. Slow per-group with recorded exit codes: runtime 100/100
exit 0 (whole group in a SINGLE process — first time; the
2026-10-15 "by parts" wart did not reproduce), state 45/45 exit 0,
http 23/23 exit 0, lifecycle 11/11 exit 0 (`CHAIN-DONE`). Full
`qxfx0-test` and the core slice were not re-run in this landing.

## Ops notes (run discipline)

- Three first fast attempts (58m53s / 59m36s / 60m56s) were killed
  EXTERNALLY at wall-clock ~59–61 min — not test failures and not
  OOM: the third reached 1840/1841 with 0 errors/failures before the
  kill. Lesson: suites that can exceed ~30 min run detached (setsid
  or a systemd user unit) with the verdict read from the log, never
  from a foreground session.
- The slow chain ran as one systemd unit, groups sequentially
  (state needs `-M10G`; `-M8G` heap-exhausts and `-M12G` invites the
  OOM killer); heavy suites are not run in parallel (box memory).

---

# Audit 2026-10-16 fix batch 2 — landing (2026-10-18)

Status: landed; the pre-registered bars (4) above were registered
BEFORE any behavior change and held. Commits: p.6 `5007bee`, p.7
`1fbc0de`, p.8 `c49a491`. Register statuses:
`docs/closure/AUDIT_2026-10-16.md`. Commits were staged: each one was
built and its own pins ran green before the next was committed.

## (4a) p.6 stepOrFail stage mapping — landed (`5007bee`)

Bars held. `stepOrFail` inspects `stepResult` first and finalizes in
every branch; the failure branch finalizes tolerantly — the captured
step error is the diagnosis worth keeping, and a strict `finalize`
would mask the branch with the rc of the failed step — then issues
the explicit ROLLBACK and throws the stage-mapped
`PersistenceTxError`. Pin
`testStepOrFailKeepsStageMappedErrorAndRollsBack`: a NOT NULL
violation under `BEGIN IMMEDIATE` yields
`PersistenceTxError StageStateBlobUpsert` (not a masking generic
`SQLiteError` from `finalize`) and leaves no transaction open — a
second `BEGIN IMMEDIATE` on the same connection succeeds.

## (4b) p.7 corrupt-load routing — landed (`1fbc0de`)

Bars held. `loadStateDirect` guards the read with `tryQxFx0` (the old
`UnicodeException` catch could never fire — the read goes through
`columnTextLenient`) and reports `LoadStateCorrupt [PdCorruptDecode,
PdSchemaMissingFields ["load_state_failed:" <> rendered]]`; Bootstrap
wraps `loadStateWithVersion` and routes a throw into the same contour
with `StateVersion 0 0`. The `LoadStateCorrupt → RecoveredCorruptOrigin`
branch is reachable. Pin
`testCorruptDbFileBootstrapsIntoDegradedRecovery`: the pages dbstat
reports for `dialogue_state` and both its indexes are rewritten with
0xFF (schema catalog and `runtime_sessions` intact) → degraded
bootstrap comes up `RecoveredCorruptOrigin` with
`GrfRecoveredCorruptBootstrap` rendering `load_state_failed`.

## (4c) p.8 session-row verification — landed (`c49a491`)

Bars held. Bootstrap verifies the `runtime_sessions` row right after
the `INSERT OR IGNORE` upsert (`runtimeSessionRowPresent`); a missing
row fails init loudly with the distinct stage (`mkRuntimeInitError
"Bootstrap" "session_row" "SESSION_ROW_MISSING"`), outside the
schema-init wrapper, so the diagnosis is not masked as
`SCHEMA_INIT_EXCEPTION`; a failing verification query maps to
`SESSION_ROW_QUERY_FAILED`. Pins:
`testBootstrapRepairsDeletedSessionRow` (row deleted → the next
bootstrap re-establishes it → the first save succeeds) and
`testBootstrapRefusesSilentlyMissingSessionRow` (`BEFORE INSERT …
RAISE(IGNORE)` → structured init failure, stage `session_row`, code
`SESSION_ROW_MISSING`). The old misleading `expected == actual`
conflict is unreachable in tests.

## Verification matrix (landing tree)

Detached chain, 2026-10-18, verdicts read from logs, all exit 0:
slow state 49/49 (45 batch-1 cases + the 4 new pins), slow lifecycle
11/11, integration 47/47, property 227/227, unit 1739/1739, fast
1841/1841, slow runtime 100/100 (single process), slow http 23/23 —
`CHAIN-DONE`. Full `qxfx0-test` and the core slice were not re-run in
this landing.

Red-sensitivity of the pins is analytical, not revert-cycled: the old
code gives a masking `SQLiteError` on the p.6 path, an exception out
of the loader on the p.7 fixture (the old catch admits no throw on
this path) and a silently missing session row for p.8.

## Ops notes (batch 2)

- **Runtime stall, self-recovered.** The runtime group stalled on
  test #57 `testPersistedReplayTraceDeterministicWithFixedTimeProperty`
  from ~00:43 to 10:24 UTC (~9 h 41 min of log silence) and then
  resumed by itself; all 100 cases passed, exit 0. This is the known
  isolation-wart class ("hangs after N others, passes solo"; cf.
  `testComputeReadinessModeReady` #60) — pre-existing and
  environment-shaped: the batch-2 changes live in cold
  persistence-error branches and add no waits. A stall watchdog (kill
  after 30 min of log silence) is now standard for these chains; it
  did not need to fire.
- **Fixture lesson.** The p.7 fixture must rewrite pages with strict
  `BS.readFile`/`BS.writeFile`: a lazy `BL.readFile` keeps the read
  handle open, and writing the same path from the same process fails
  with `resource busy (file is locked)`.
- State group runs as one process at `-M10G`; staged commits were each
  built and pin-run before committing (p.6 1/1, p.7 2/2, p.8 4/4
  green).

---

# Audit 2026-10-16 fix batch 3 — landing (2026-10-20)

Status: landed; the pre-registered bars (5)–(12) above were registered
BEFORE any behavior change and held. Commits: p.10 `4935f8b`, p.11
`b11b1e6`, p.17 `6a4b9a4`, p.16/15 `7f6becd`, p.14 `7166457`, p.18
`7f8d62f`, p.21/20/23/22 `606dca0`; the matching pre-registrations are
`ae0f813`, `95a22f0`, `57a0b13`, `f3cd43f`, `7204382`, `2d5b5b8`,
`63aa454`. Register statuses: `docs/closure/AUDIT_2026-10-16.md`.
Each group was built and its own pins ran green before the next was
committed.

## (5) Episodic capacity — landed (`4935f8b`)

Bars held. `enforceCapacity` trims all excess in one pass (single
`Seq.splitAt` + one `rebuildIndex`), evicted ids leave `esForgotten`,
and `length esEvents <= episodicCapacity` is a hard invariant after
every call. Pins in `Test.Suite.MemoryEpisodic`: capacity+2 → exactly
capacity; a 5-turn finalize-shape simulation holds capacity every turn
(old code: 1000→1005); the rebuilt index cannot reach evicted events;
forgotten-set hygiene; identity within capacity. Red check on the
reverted fix produced exactly the four expected failures with the
identity pin green.

## (6) Persisted-JSON clamps — landed (`b11b1e6`)

Bars held. `sanitizePersistedState` runs on every successful state
decode in `loadStateDirect`: `svsCount >= 0`, `svsWindowStart ∈
[0, ssTurnCount]`, both divergence windows drop non-finite samples and
trim to their documented bounds (newest-first), `u5Baseline` non-finite
→ `Nothing` / finite → `clampScore`. Every adjustment is logged
(`[persistence_debug] state_sanitized ...`) — visible, never silent;
clean state is the identity. `ConatusEnergy.FromJSON` re-derives
`ceScalar` as the component sum on every decode (key stays mandatory,
value not trusted; legacy four-component blobs unchanged). Pins:
`Test.Suite.StateSanitization` (8 cases, unit+fast) plus the slow-state
pin `testLoadedStateSanitizesCorruptedFields` (doctor a saved blob →
clamped state + log lines). Red checks: wiring off → slow pin red;
derivation off → unit pin red.

## (7) Canonical challenge lexicon — landed (`6a4b9a4`)

Bars held. `QxFx0.Semantic.Markers.challengeMarkers` is the union of
the five former copies (21 entries; every site gained markers, none
lost any); `unclassifiableSuppressionMarkers` («но » : challenge) is
Anomaly-only; `containsAnyOf` is the shared matching rule. No private
copies remain. Pre-registered deltas (more CMConfront on evidential and
«считаю иначе» inputs; slightly more Unclassifiable suppression) are
the majority semantics already in force on the semantic path. Pins:
`Test.Suite.ChallengeMarkers` (4 cases, unit+fast) incl. a detector pin
on `detectUnclassifiableInput` (pre-unification Anomaly copy knew none
of «контрпример»/«что если»/«но »). Red checks: shrink the union to 17
→ 3 pins red; revert Anomaly to its private list → detector pin red.

## (8)/(9) Recovery severity order + honest metacognition cause — landed (`7f6becd`)

Bars held. `buildLocalRecoveryPlan` is ordered strictly by
`recoveryCauseSeverity` (runtime 70 > shadow signals 60/50 > unknown
topic 40 > legitimacy 30 > parser 20); the unknown-topic guard keeps its
structured-surface gate. Pre-registered deltas: combined turns select
the higher-severity cause; single-signal turns unchanged.
`selfEvaluate` / `runMetacognitionLoop` take the turn's actual
`Maybe LocalRecoveryCause` (the same merged value the trace stamps as
`trcRecoveryCause`) instead of the deliberation-only
`planRecoveryCause`. Pins: TurnPipelineProtocol +5 order pins and +4
metacognition pins (accepted/ignored × recovery/clean, through
`buildFinalizePrecommit`); the parser fixture is rebased with
`tiBestTopic = ""`. Red checks: old chain order → exactly the five
order pins red; old `inRecovery` derivation → exactly the two recovery
pins red.

## (10) Trace truthfulness — landed (`7166457`)

Bars held. Seven fields are now honest or removed:
`trcEpisodicEncoding` = ids appended this turn in store order
(`episodicTurnDelta`); `trcEpisodicForgetting` = newly tombstoned +
capacity-dropped, no re-count; `trcContentSaliencyDominantCluster` =
derived from the post-turn meaning graph (`dominantClusterOf .
detectClusters`) — honest `Nothing` today because the spectral splitter
is degenerate on every graph (documented on the pin; index selection is
pinned synthetically until the numerics produce real splits);
`trcParserLatencyMs` removed (was a literal 0; old envelopes decode);
the five prepare-timeline windows are measured and anchored at the
turn's captured `t0` (no more t0/t0); `trcDoubtScore` always carries an
honest `0.0`; the degraded-runtime `trcRecoveryEvidence` placeholder
branch is gone and `TraceAnalysis` gains `evidence_without_cause`.
Pins: MemoryEpisodic 5 pure, ContentSalience 3, TurnPipelineProtocol 6
end-to-end, TraceAnalysis 1. Red check: combined revert → exactly 12
failures, all new pins, no pre-existing test moved.

## (11) Commitment ledger — landed (`7f8d62f`)

Bars held. `recordContradictionPairs` (`Semantic/Commitment.hs`) is the
single pure morphism: `newCid = surface <|> anchor`; `Nothing` → the
store is value-unchanged with counter 0 (the pre-registered “skip with
a trace mark” option); `Just c` → pairs `(engaged \ {c}, c)` and the
counter is the number of recorded pairs. The revision filter uses the
same `maybe` over the real id (sentinel removed; semantics identical —
no discriminating pin exists, noted honestly). `trcContradictionPairs`
is the per-turn trace mark (`FromJSON` defaults to 0, envelope version
not bumped); the ledger haddock documents the append-only write-only
forensic role and its per-turn observability through that field. Pins:
CommitmentQuarantine pure cases (skip / surface / anchor / priority /
`engaged = [newCid]`) and TurnPipelineProtocol (f)/(g) end-to-end
(contradicted + no new-side id ⇒ no ledger growth, `pairs == 0`,
`contradicted == True`; committed claim ⇒ real-id pairs, no id 0,
counter == new pairs). Red check on the phantom morphism: exactly the
skip pins fell with `(engaged, CommitmentId 0)` pairs.

Matrix catch (fixed at this landing): the pre-existing
`CommitmentAwareRouting` integration pin still asserted a non-empty
ledger for the skip fixture — the very case the pre-registered bar
declares empty. It now asserts `trcContradictionPairs == 0` and that no
ledger event references `CommitmentId 0`. The unit suite is re-run at
this landing, so the check is green here.

## (12) State/schema smalls — landed (`606dca0`)

Bars held. п.21: `ToJSON SystemState` writes `geometricMetrics`
(additive optional key, no schema bump). п.20: `loadStateWithVersion`
reads through `BEGIN DEFERRED`; writes stay `BEGIN IMMEDIATE`; a reader
no longer takes the write lock. п.23: probes are three-valued
(`ProbeOutcome = ProbeFound | ProbeNotFound | ProbeFailed Text`);
`readSchemaVersion` gains `SchemaVersionProbeError`;
`isV1Shape`/`isV2Shape` return `Either`; `checkSchemaContract` maps a
failure to `SchemaContractQueryFailed`; `ensureSchemaMigrations` fails
with `schema_probe_failed` before any stamp, migration or seed;
`columnMissing` → `columnExists`; `NSQL.stepHasRow` is the non-throwing
row probe. п.22: `insertSchemaVersion` checks bind/step/finalize and
throws `schema_version_insert`; `runPendingMigrations` rolls back only
while the transaction is still open (`txClosedRef`), never after COMMIT.

Deviations from the pre-registration, recorded honestly:

- (12d)(i) direct `insertSchemaVersion` pin was dropped: the function is
  not exported. The bar is covered by (ii) — the migration trap yields
  the same `schema_version_insert` operation identity plus the rollback
  assertions (no ALTER persists, no version row remains).
- The pre-registration said the pins live in “unit+fast”. They live in
  `Test.Suite.RuntimeInfrastructure`, which unit/fast only compile; the
  suite runs in the slow runtime group (and the full `TestMain`). Actual
  indices in `runtimeInfrastructureTests` (106 entries) are 10–15, run
  at `-M12G`.

Pins: metrics round-trip (`recordABValidation` values survive
encode→decode) + legacy JSON default; deferred read while a raw
connection holds an uncommitted `BEGIN IMMEDIATE` writer; corrupt-file
probes (`ProbeFailed`, `SchemaVersionProbeError`,
`SchemaContractQueryFailed`); fail-fast bootstrap on an incompatible
`schema_version` table (`schema_probe_failed`, no stamp, no seed);
migration insert trap (`schema_version_insert`, ALTERs rolled back, no
version row). Red check reverted all four behaviors at once — exactly
five intended pins failed (round-trip, deferred read with
`tx_begin_failed`, corrupt probes, fail-fast probe identity, insert
trap) and the legacy-default pin stayed green. Green after restore:
pins 6/6, slow lifecycle 11/11, fast slice
`CorpusTuning,BootstrapRecovery` 17/17.

## Verification matrix (landing tree)

Detached chain, 2026-10-20, verdicts read from logs, all exit 0:
slow runtime 106/106 (100 batch-2 cases + 6 state/schema pins), slow
state 50/50 (49 + the п.11 sanitization pin), slow http 23/23, slow
lifecycle 11/11, integration 47/47, property 244/244 (227 + 17 new
batch-3 properties), fast 1884/1884 (1841 + 43), unit 1787/1787
(1739 + 48) — `CHAIN-DONE`. The first unit run of the landing failed
exactly one case (the stale п.18 expectation described in (11)); after
the test fix the full unit suite was re-run solo, 1787/1787 exit 0.
Full `qxfx0-test` and the core slice were not re-run in this landing.
Slow groups were run sequentially: runtime at `-M12G` as one process
(no stall this time), state at `-M10G`, http/lifecycle at `-M12G`.

## Ops notes (batch 3)

- The full unit run at the landing caught the stale п.18 expectation in
  `CommitmentAwareRouting` (see (11)); the per-group slices had not
  registered that suite. The lesson matches batch 2: per-group slices
  hold their bars, the full matrix is the cross-group gate.
- Unit case count grew 1739 → 1787 (+48: the batch-3 pins in
  MemoryEpisodic, StateSanitization, ChallengeMarkers,
  TurnPipelineProtocol, CommitmentQuarantine and TraceAnalysis, plus
  the п.17/п.18 fixture updates; the six RuntimeInfrastructure pins
  live in the slow runtime group, not unit).

---

# Audit 2026-10-16 fix batch 4 — landing (2026-10-21)

Status: first group landed; the pre-registered bar (13) was registered
BEFORE any behavior change and held. Commits: pre-reg `b07d805`, code
`4603a41`.

## (13) Boot-загрузчики: границы catch-типов и async-отмена — landed

### Sites (as pre-registered)

- `ExceptionPolicy.tryBootResource` — new canonical boundary: catches
  exactly `QxFx0Exception` and `IOException`, rethrows
  `AsyncException` and every unexpected exception.
- Bootstrap: ontology (`loadOntologyForBootstrap`) and curated
  predicates (`loadBootstrapDefinitionCorpusFrom`) now catch the
  parser's `RuntimeInitError`; self-play merges behind
  `mergeSelfPlayRelationsForBootstrap`. All three preserve their
  documented fallbacks (`emptyOntology`, seed corpus, base network)
  and their WARN messages (ontology/curated now also carry `path`).
- `loadBrainKB`, `loadRuntimeParadigmsFrom`, and the SelfConfig readers
  guard their reads with `tryIO`: an unreadable file degrades to the
  empty/builtin value with a WARN instead of escaping bootstrap.
- `initializeAutonomousStorageWith` — the exported test seam; the
  production `initializeAutonomousStorage` keeps the same schema-init
  action. It uses `tryAsync`: async cancellation propagates (and closes
  the connection via `onException`), synchronous failures remain
  `Left Text` with the connection closed.
- `columnText` decodes leniently (U+FFFD); `columnTextLenient` is the
  compatibility alias. Checked-in resources keep their strict decode;
  the Engine catch type is unchanged.

### Pins

`Test.Suite.BootBoundary` (9 cases, registered in unit+fast+main):
async propagation, sync containment, `tryBootResource` class matrix,
malformed ontology, malformed curated, malformed self-play, unreadable
brain_kb, unreadable/malformed paradigms, unreadable SelfConfig.
`Test.Suite.NativeSQLiteNulls` gained the lenient `columnText` pin
(5 cases in that suite). BootBoundary slice 9/9; fast slice (boot +
native) 27/27.

### Red check (one combined revert of all nine behaviors)

Exactly the pre-registered failure set, with these messages:

- pin 1 (async): `async cancellation was swallowed into Left Text:
  thread killed`;
- pin 3 (classes): `a programming error must not be swallowed at a
  boot boundary` (the catch-all variant swallowed `ErrorCall`);
- pin 4 (ontology): `category=RuntimeInitError, component=
  semantic_ontology, operation=load_jsonl, code=ONTOLOGY_LOAD_ERROR`
  escaped the site;
- pin 5 (curated): `CURATED_PREDICATE_PARSE_ERROR` escaped;
- pin 6 (self-play): `RELATION_PARSE_ERROR` escaped;
- pins 7–9 (brain_kb / paradigms / SelfConfig): `withBinaryFile:
  permission denied` escaped;
- pin 10 (columnText): `Cannot decode byte '\x80': Data.Text.Encoding:
  Invalid UTF-8 stream`;
- pin 2 (sync containment) stayed green: the old `try` semantics are
  preserved for synchronous init failures.

### Honest limits / deviations

- The permissions-based pins (brain_kb, paradigms, SelfConfig) skip
  themselves under euid 0, because root bypasses the mode bits; the
  landing box runs as uid 1000. The malformed-content pins and the
  async pin are uid-independent.
- `initializeAutonomousStorageWith` is a test seam exported from the
  session bootstrap module; the production entry point is unchanged in
  behavior except for the async fix.
- The storage-init boundary stays catch-all-minus-async (the old
  containment semantics), while resource loaders catch only the two
  expected classes. The asymmetry is deliberate and pinned by
  `BootBoundary:1` (the sync-containment case).
- `tryBootResource` is not applied to `loadBootstrapSqlSet` (it already
  distinguishes its expected classes) or to the
  `ingestExternalKnowledge` loader (already guarded) — out of scope as
  pre-registered.
- No trace fields were added; fallbacks are observable via the existing
  WARN logs.

## Verification matrix (landing tree)

Detached chain, 2026-10-21, verdicts read from logs, all exit 0:
unit 1796/1796 (1787 + 9 BootBoundary), fast 1894/1894 (1884 + 10 =
9 BootBoundary + 1 NativeSQLiteNulls), property 244/244, integration
47/47, slow runtime 106/106, slow state 50/50, slow http 23/23, slow
lifecycle 11/11 — `CHAIN-DONE`. Slow groups were run sequentially:
runtime at `-M12G` as one process (no stall), state at `-M10G`,
http/lifecycle at `-M12G`. Full `qxfx0-test` and the core slice were
not re-run in this landing.

## Ops notes (batch 4, group 1)

- Unit count 1787 → 1796 (+9), fast 1884 → 1894 (+10). Slow counts are
  unchanged at 190: the new suite is registered in the unit, fast and
  main mains; `TestMainSlow` compiles it via test-common but does not
  register it, by design.
- The red check used one combined revert of all nine behaviors (the
  batch-3 pattern), not nine rebuild cycles; the observed failing set
  matched the prediction exactly, which is the strongest form this
  bar can take.
- The loader WARNs are now path-bearing for ontology and curated
  predicates; the pre-existing self-play and brain_kb warnings already
  carried it.
## (14) Feedback mirror: самовосстановление и атомарная перезапись — landed

Pre-reg `82b61f2`, code `4103d04`; bar (14) was registered before any
behavior change and held.

### Sites (as pre-registered)

- `Feedback.Persist.persistFeedbackNetwork`: the reader no longer calls
  the throwing `loadRelations`; each line is decoded with
  `eitherDecodeStrict` and malformed rows are skipped with one WARN
  (`[feedback-mirror] skipped N malformed line(s) in <path>`). A missing
  file is an empty base; any other read error returns early with a WARN
  and leaves the file byte-identical.
- The write goes through `writeMirrorAtomically`: unique temp file in
  the target directory (`openTempFile`, template `<name>-tmp`, no dot so
  the random part does not hide the marker), full write, `hClose`,
  `renameFile` over the target; `bracketOnError` closes and removes the
  temp on any failure. The exception still propagates to the unchanged
  `runBestEffortPostCommit "feedback_mirror"` caller.
- Format, merge semantics, and the mirror path in the handler are
  unchanged; no trace fields added.

### Pins

`Test.Suite.FeedbackMirror` (5 cases, unit+fast+main):

1. malformed line self-heals (valid rows preserved, changed rows
   merged, bad row dropped, no exception);
2. read failure (mode 000) does not escape and does not clobber the
   mirror (root-skip);
3. missing file is created with the changed relations;
4. rewrite replaces the file via rename — the inode changes — and no
   temp remains;
5. a failed write (target is a directory) throws, leaves no temp, and
   the target is intact.

### Red check

- Cycle A (HEAD reader + `BL.writeFile`): pins 1, 2, 4 fail exactly —
  `RELATION_PARSE_ERROR`, `openFile: permission denied` escaping into
  the best-effort caller, and "the rewrite must replace the file via
  rename (inode must change)"; pins 3 and 5 stay green.
- Cycle B (temp cleanup removed, temp+rename kept): pin 5 fails —
  "a failed write must not leave a temp file behind".
- The first pin-5 draft used a `.tmp` template and was blind to the
  leftover: `openTempFile` inserts its random part before the
  extension. The template is now `-tmp` (no dot); the same revert then
  fails as intended. Recorded because the weak pin existed in the
  working tree for one cycle.

### Honest limits

- Crash atomicity (kill -9 mid-write) is not tested in-process; pin 4
  verifies the rename mechanics structurally and pin 5 the failure
  cleanup.
- The temp file is created with mode 0600 (`openTempFile`) where the
  old `BL.writeFile` produced 0644; the mirror is local runtime data
  with no cross-uid consumer (deliberate change).
- Pin 2 skips under euid 0 (root ignores mode bits), same as the
  BootBoundary permission pins.
- `loadRelations` keeps its throwing contract for curated corpora
  (ingest); only the runtime mirror got the resilient reader.

## Verification matrix (landing tree)

Detached chain, 2026-10-21, verdicts read from logs, all exit 0:
unit 1801/1801 (1796 + 5 FeedbackMirror), fast 1899/1899 (1894 + 5),
property 244/244, integration 47/47, slow runtime 106/106, slow state
50/50, slow http 23/23, slow lifecycle 11/11 — `CHAIN-DONE`. Slow
groups were run sequentially (runtime at `-M12G` as one process, state
at `-M10G`, http/lifecycle at `-M12G`).

Full `qxfx0-test` and the core slice were not re-run.

## Ops notes (batch 4, group 2)

- Unit count 1796 → 1801 (+5), fast 1894 → 1899 (+5); slow counts are
  unchanged at 190.
- Two red-check cycles were needed (reader/writer revert; cleanup-only
  revert) rather than one combined revert, because pin 5 exercises a
  failure path that only exists in the new temp+rename writer.
## (15) Кризисный лексикон: первое лицо для EN и объект для «хочу покончить» — landed

Pre-reg `91d9800`, code `6d50cbf`; bar (15) was registered before any
lexicon change and held. The recall-first rule is honoured: no acute
formulation lost coverage; only topical/meta references and benign
objects left the hard gate.

### Sites (as pre-registered)

- `Safety/CrisisGuard.hs`: bare `suicide`/`suicidal` removed from the
  infix lexicon; first-person and act markers added (i am/i'm/im
  suicidal, i feel/feeling suicidal, i have/i'm having suicidal
  thoughts, thinking about/of suicide, want(s)/going/plans to commit
  suicide, take my own life, ending my life, do not want to live,
  is/are suicidal, committed suicide, suicide attempt/note).
- New `acuteCrisisExactMarkers` (`suicide`, `suicidal`) is checked
  before the infix pass on the normalized input with surrounding
  punctuation and whitespace trimmed: `Suicide!`, `suicidal.` and
  «suicide» fire; a topical sentence does not.
- RU: object-free `хочу покончить` removed; `покончить с жизнью`,
  `покончить жизнь самоубийством` and the missing future/past forms
  added (покончу/покончил с собой, лишил себя жизни, расстался с
  жизнью, совершил(а) самоубийство, планирую/планирует
  самоубийство).
- Resources, `crVersion`, `renderCrisisSurface`, `decideProtocol`,
  the Engine preflight and the R5 contour are untouched; the RU
  «самоубий» stem stays excluded (Camus trap); `normalizeCrisisInput`
  is unchanged (the punctuation trim lives in the detector).

### Pins

`Test.Suite.CrisisGuard` grew by one label (terse whole-input) and
the existing labels were extended:

- EN positives: all new first-person/act forms plus the existing
  `thinking about suicide`; third-person reports
  (`my friend committed suicide`, `she survived a suicide attempt`,
  `he left a suicide note`, `he is suicidal`);
- RU positives: object-complete completions and the new past/future
  forms;
- terse: `suicide`, `suicidal`, `Suicide!`, `suicidal.`, «suicide»;
- EN decoys: `suicide is a philosophical problem`, `the novel
  discusses suicide`, `suicidal thoughts are a theme in the book`,
  `camus wrote about suicide as a philosophical question`,
  `suicide rates have declined`;
- RU decoys: `хочу покончить с этой работой`, `хочу покончить с
  проектом`;
- the marker non-empty check covers both the infix and the exact
  lists.

### Red check

- Cycle A (HEAD lexicon, new battery): exactly three labels fail —
  RU battery, EN battery, decoys; the terse label stays green because
  the old bare infix still matches it.
- Cycle B (exact matching disabled on the fixed lexicon): exactly the
  terse label fails.

### Honest limits

- Terse RU `самоубийство` stays outside the gate (the stem is
  deliberately excluded); only the EN terse words are exact markers.
- Third-person fictional descriptions can still fire through
  `is/are suicidal` ("the protagonist is suicidal") — the accepted
  recall-first cost of keeping real third-person reports covered.
- Meta/topical EN references no longer fire; this is the audit's
  intent and is pinned by the decoy battery.

## Verification matrix (landing tree)

Detached chain, 2026-10-21, verdicts read from logs, all exit 0:
unit 1802/1802 (1801 + 1 terse label), fast 1900/1900 (1899 + 1),
property 244/244, integration 47/47, slow runtime 106/106, slow state
50/50, slow http 23/23, slow lifecycle 11/11 — `CHAIN-DONE`. Slow
groups were run sequentially (runtime at `-M12G` as one process, state
at `-M10G`, http/lifecycle at `-M12G`).

Full `qxfx0-test` and the core slice were not re-run.

## Ops notes (batch 4, group 3)

- Unit count 1801 → 1802 (+1: the terse label), fast 1899 → 1900
  (+1), main 1322 → 1323 (core 1203); slow counts are unchanged at
  190.
- Two red-check cycles were needed (lexicon revert; exact-matching
  disable) because the terse pin is masked by the old bare infix in a
  combined revert.
## (16) SessionLock: эвикция не расщепляет сессию — landed

Pre-reg `779b260`, code `4fcf839`; bar (16) was registered before the
fix and the reproduction-first order held: the deterministic scenario
was written and observed red before the pinning landed.

### Sites (as pre-registered)

- `Core/SessionLock.hs`: `SessionLockEntry` gains `slePins`;
  `acquireSessionLock` looks up/inserts and pins in one STM
  transaction; `withSessionLockPaused` releases the pin in `finally`.
  Eviction candidates require `slePins == 0`, the CAS re-checks pins,
  stamp and cap, and a failed eviction retries the insertion once
  before the overflow shard.
- `SessionLockStats` gains `slsPinnedLocks` (sum) and `slsEvictions`
  (successful LRU evictions); `slsTrackedLocks`/`slsOverflowActive` are
  unchanged.
- Test seams: `newSessionLockManagerWithCap` (explicit cap) and
  `withSessionLockPaused` (post-registry hook). Production
  `newSessionLockManager`/`withSessionLock` are the same paths with
  env resolution / an empty hook.
- Overflow shards (64), LRU stamps, `QXFX0_MAX_SESSION_LOCKS` and the
  `Runtime/Wiring/Context.hs` call site are untouched.

### Pins

`Test.Suite.SessionLockOverflow` (5 cases, unit+fast+main):

1. deterministic eviction scenario: with cap 1, A registers and pauses
   before acquiring, B forces the cap pressure, A enters, C for "a"
   must not enter within 500 ms and must enter after A releases; all
   pins are zero at the end;
2. stress: 4 threads × 200 iterations over two sessions at cap 1 —
   max concurrent entries per session is 1;
3. a throwing action propagates and releases its pin;
4. unpinned entries keep being evicted (`slsEvictions` grows on each
   insert above the cap; tracked stays at 1; overflow active);
5. a held lock is visible as pinned (`slsPinnedLocks >= 1` inside, 0
   after release).

### Red check

- Cycle A (eviction ignores pins: candidate filter and CAS guard
  removed): exactly the deterministic scenario fails.
- Cycle B (`finally` release removed): four labels fail — the
  scenario (final pin count), exception release, eviction accounting
  (the leaked pin makes the next insert overflow instead of evicting)
  and pinned visibility (final count). All four are consequences of
  the same leak.

### Honest limits

- The 500 ms "C did not enter" assertion is scheduling-dependent: on a
  loaded machine the red check on the unfixed code could pass by luck;
  it was observed red on an idle box. For the fixed code the direction
  is safe (a slower machine cannot cause a false failure).
- The stress test is a probabilistic net, not a proof.
- The test seams are exported from the production module; they are
  additive and documented as test-only.
- The overflow shard still serializes unrelated sessions (unchanged
  bounded degradation); the fix only closes the same-session split.

## Verification matrix (landing tree)

Detached chain, 2026-10-21/22, verdicts read from logs, all exit 0:
unit 1807/1807 (1802 + 5 SessionLockOverflow), fast 1905/1905 (1900
+ 5), property 244/244, integration 47/47, slow runtime 106/106,
slow state 50/50, slow http 23/23, slow lifecycle 11/11 —
`CHAIN-DONE`. Slow groups were run sequentially (runtime at `-M12G`
as one process, state at `-M10G`, http/lifecycle at `-M12G`).

Full `qxfx0-test` and the core slice were not re-run.

## Ops notes (batch 4, group 4)

- Unit count 1802 → 1807 (+5), fast 1900 → 1905 (+5), main 1323 →
  1328 (core 1208); slow counts are unchanged at 190.
- The deterministic pin required the post-registry hook; red check A
  confirms the hook exposes the real window (not a synthetic one).
- Cycle B's collateral failures (eviction accounting) are expected:
  eviction skips pinned entries by design.

## (17) SQLite: threaded RTS, safe FFI и acquire без гонки timeout/takeMVar — landed

Pre-reg `e63021c`, code `915c736`; бар (17) зарегистрирован до
изменения поведения. Reproduction-first в форме «сначала красный
сценарий» здесь не применим: дефект — свойство линковки (vanilla
RTS), а не поведенческая ветка; красные прогоны выполнены ревертом
каждого из двух условий отдельно (см. Red check).

### Sites (as pre-registered)

- `qxfx0.cabal`: `-threaded` для `qxfx0-main`,
  `qxfx0-stage1-traces` и `common test-common`; `-N` не
  фиксируется (default 1 capability), library не меняется.
- `Bridge/NativeSQLite.hs`: `sqlite3_open`, `sqlite3_close`,
  `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_exec` переведены
  в `safe`; остальные 13 биндингов остаются `unsafe`
  (не блокируют).
- `Bridge/SQLite/Pool.hs`: `timeout . takeMVar` заменён на
  дедлайн-поллинг `tryTakeMVar` (`GHC.Clock.getMonotonicTimeNSec`,
  `threadDelay 1000`); по дедлайну — тот же
  `pool_acquire`/`TIMEOUT` с `pool_size`. Production
  `withPooledDB = withPooledDBTimeout 5000000`; семантика действия,
  транзакций, WAL, busy_timeout и `withDatabaseActionLock` не
  менялась.
- Швы `withPooledDBTimeout`, `acquireConnectionsWithTimeout`,
  `poolAvailableConnections` проброшены через фасад
  `Bridge/SQLite.hs`; модуль `Pool` остаётся hidden.

### Pins

`Test.Suite.SQLiteRuntime` (3 cases, unit+fast+main):

1. blocking FFI не морозит Haskell: соединение A держит
   `BEGIN EXCLUSIVE`, соединение B делает INSERT с
   `busy_timeout=1000`; тикер (10 мс) за время блокирующего вызова
   продвигается ≥ 20 раз. Это функциональный инвариант прогресса,
   не latency-бар.
2. acquire-таймаут структурный и без потерь: на пустом `MVar`
   `acquireConnectionsWithTimeout` с 50 мс даёт
   `SQLiteErrorStructured` с кодом `TIMEOUT`; после `putMVar` тот
   же вызов возвращает ровно положенное соединение.
3. размер пула стабилен: `newDBPool` на 2 соединения,
   10 последовательных `withPooledDB`, затем
   `poolAvailableConnections` = 2.

### Red check

- Cycle A: `sqlite3_step`/`sqlite3_exec` обратно в `unsafe` при
  `-threaded` — ровно пин 1 падает (`before=9, after=9`);
  остальные два зелёные.
- Cycle B: `-threaded` убран из `test-common`
  (`+RTS --info` → `RTS way: rts_v`) — ровно пин 1 падает
  (`before=9, after=9`).
- Cycle C (реверт acquire на `timeout . takeMVar`) не даёт
  детерминированного красного: на пустом `MVar` старый и новый
  код ведут себя одинаково, а гонка вероятностная; поэтому
  структурный реверт фиксируется ревью, а не тестом — honest
  limit ниже.

### Honest limits

- Пин 1 timing-sensitive по конструкции: он проверяет прогресс, а
  не скорость, но на сильно загруженной машине тикер может не
  успеть набрать 20 тиков даже с threaded RTS. Порог выбран с
  запасом (ожидаемо ~100 тиков при блокировке ~1 с); главный
  контроль — структурный (`safe` + `-threaded`), матрица —
  поведенческий.
- Гонка `timeout`/`takeMVar` на HEAD вероятностная и прикрыта
  процесс-глобальным `withDatabaseActionLock`; пин 2 проверяет
  наблюдаемый контракт таймаута и отсутствие потери значения, а не
  саму гонку. После фикса гонка структурно невозможна
  (`tryTakeMVar` либо возвращает значение, либо оставляет его в
  `MVar`).
- `safe` для `sqlite3_close` не защищает от use-after-free при
  закрытии соединения, которое ещё используется: жизненный цикл
  соединения по-прежнему обеспечивается пулом и action-lock, это
  не менялось.
- `-threaded` меняет RTS целиком; поведенческие тесты рантайма —
  основной контроль, полная матрица обязательна. Первый же
  post-change fast-прогон поймал реальный дефект п.27 (см. (18)).

## (18) SessionLock: overflow-запись не расщепляет сессию — landed

Pre-reg `92c0a7d`, code `1d8b46c`. Вход — красная матрица (17):
под threaded RTS стресс-пин п.27 упал
(`max concurrent entries per session must be 1, got: fromList [("a",2),("b",2)]`).
Это не флак теста: overflow-путь выдавал шард, не регистрируя
сессию, и конкурентный tracked-insert той же сессии давал две
независимые критические секции.

### Sites

- `Core/SessionLock.hs`: `SessionLockEntry` получает
  `sleOverflow`; `pinOrInsertOverflow` атомарно (в одной
  STM-транзакции с проверкой сессии) либо пинит существующую
  запись, либо вставляет overflow-запись с шардом в `slmLocks`
  (выше cap). `releaseSessionLock` удаляет overflow-запись при
  последнем пине; `insertTracked` и eviction-CAS создают обычные
  записи (`sleOverflow = False`).
- Все пути входа проверяют сессию в той же транзакции, что и
  мутацию, — tracked- и overflow-вставки одной сессии не могут
  обе succeed.
- Cap, 64 шарда, LRU-эвикция (только `slePins == 0` и свободный
  `MVar`), `SessionLockStats`, env-контракт не менялись;
  `slsTrackedLocks` теперь включает активные overflow-записи
  (транзиентные, документировано в поле).

### Pins

`Test.Suite.SessionLockOverflow` — 6-й детерминированный кейс
(unit+fast+main): C держит единственный tracked-слот (cap 1,
пин до захвата `MVar`), B входит в «a» через overflow, C
отпускают, затем A входит в «a». На HEAD A эвиктит C и вставляет
tracked «a» — A и B одновременно; после фикса A пинит
overflow-запись и ждёт шард. Бар: A не входит за 500 мс, пока B
внутри; после release B — входит. Существующие 5 кейсов зелёные.

### Red check

- Отключена overflow-вставка (возврат к выдаче шарда без записи в
  реестр) → падает ровно кейс 6; остальные пять зелёные.
- После фикса стресс-пин прогнан 20/20 раз — 0 падений (под
  `-threaded`, где гонка и наблюдалась).

### Honest limits

- Карта может превысить cap на число **активных** overflow-сессий;
  записи транзиентны и удаляются при последнем пине, но при
  экстремальной конкурентности это больше cap. Это цена
  инварианта «одна сессия — одна критическая секция»; overflow-
  сессии по-прежнему делят шард (сериализация чужих сессий
  сохранена).
- Стресс-пин остаётся вероятностным нетом; детерминированный
  кейс 6 — основной бар.
- WARN `session_lock_overflow` остаётся: overflow — наблюдаемая
  деградация, а не ошибка.

## Verification matrix (landing tree)

Two detached chains on the same tree (no code changes between
them; the first was stopped at the known slow runtime test #63 and
that group was re-run cleanly), verdicts read from logs, all exit 0:
unit 1811/1811 (1807 + 3 SQLiteRuntime + 1 SessionLockOverflow),
fast 1909/1909 (1905 + 4), property 244/244, integration 47/47,
slow runtime 106/106, slow state 50/50, slow http 23/23, slow
lifecycle 11/11 — `REST-DONE` for the slow chain. Slow groups were
run sequentially (runtime at `-M12G` as one process, state at
`-M10G`, http/lifecycle at `-M12G`). Test #63
(`persisted replay trace json deterministic with fixed time source`)
was first suspected as a stall: it passed 20/20 solo in ~25 min and
then inside the clean 106/106 run; the first chain was stopped
manually, not by a failure. The pre-fix post-change fast run failure
(the п.27 stress pin) is preserved in the addendum (18) record.

Full `qxfx0-test` and the core slice were not re-run.

## Ops notes (batch 4, group 5)

- Unit count 1807 → 1811 (+4: 3 SQLiteRuntime + 1 SessionLockOverflow),
  fast 1905 → 1909 (+4), main 1328 → 1332 (core 1212); slow counts
  are unchanged at 190.
- `+RTS --info` on `qxfx0-main` and the test binaries now reports
  `rts_thr`; on the pre-fix tree it reported `rts_v`.
- The first post-change fast run failed the п.27 stress pin; the
  addendum (18) fixed the real overflow split, and the final matrix
  above is on the combined tree.
- The three acquire/pool seams are additive facade exports; the
  hidden `Bridge.SQLite.Pool` module is unchanged in visibility.
- Existing SQLite-backed suites (state persistence, learning events,
  HTTP runtime) passed inside the matrix without behavioral edits —
  the RTS switch is link-time only.

## (19) п.13. Внешние guardrails: честные имена и доки — landed

Pre-reg `61e9e12`, code `78bfd65`; enforcement не возвращался
(решение 2026-10-17 по п.13).

### Sites

- `Learning/Guardrails.hs`: `canIssueExternalAction` →
  `externalActionGuardrailDecision` (параметр `ExternalActionKind`
  удалён); `canSubmitProposal` → `proposalSubmissionGuardrailDecision`;
  заголовок и Haddock-и переписаны: это диагностическая проекция
  superseded-контура, а не enforcement.
- `Learning/Loop.hs`: заголовок фиксирует инертность
  `runLearningStep`/`applyExternalLearning` при флаге False;
  `legacyExternalLearningEnabled` помечен как permanently False;
  enabled-тело сохранено для истории/тестов.
- `Learning/Autonomous.hs`: заголовок фиксирует, что worker не
  консультируется с `GuardrailState` — это отдельный env-gated
  контур, а не забытый вызов.
- `Types/Learning/Guardrails.hs`: JSON-поля объявлены
  persisted-контрактом (переименование только с миграцией).
- `Route/Render.hs`: вызовы переименованы; `buildExternalActionRequest`
  больше не принимает вид действия (он не влиял на решение), вид
  остаётся в трейсе.
- Счётчики не удалены и не оживлены; схема `GuardrailState`, пороги
  и replay-поля не менялись.

### Pins

- `Guardrails`: новый кейс «external action projection denies on
  limit and breaker» — allowed на пустом состоянии, rate-limit и
  circuit-breaker denial (10 кейсов в suite).
- `LearningLoop`: новый кейс
  `testLegacyExternalLearningApplyDisabledPreservesGuardrails` —
  непустой `GuardrailState` (last turn 7, окно 2, streak 1,
  cooldown 15) остаётся байт-в-байт после `applyExternalLearning`
  с валидным ответом.
- `TurnPipelineProtocol`: только переименование вызовов (семантика
  та же).

### Red check

- Убран guard `| not legacyExternalLearningEnabled = ss` в
  `applyExternalLearning` → новый пин упал: окно стало 3,
  rejection streak 2, появилась quarantine-запись; старый
  apply-пин упал тем же прогоном. Restore → Guardrails+LearningLoop
  81/81 зелёные.
- `grep canIssueExternalAction|canSubmitProposal` по `src/` и
  `test/` → 0.

### Honest limits

- Изменение не поведенческое: переименование и документация.
  Slow-группы не перезапускались (нет runtime-семантики; unit+fast
  компилируют и исполняют все call sites, property/integration
  покрывают JSON/replay). Полный `qxfx0-test` и core-слайс
  по-прежнему не перезапускались.
- Имена больше не обещают enforcement, но сами счётчики остаются
  мёртвыми в production — это зафиксировано в доках, а не оживлено.

## Verification matrix (п.13)

Detached chain on the code tree, 2026-10-23, verdicts read from
logs: unit 1813/1813 (1811 + 2), fast 1911/1911 (1909 + 2), property
244/244, integration 47/47 — all exit 0 (`CHAIN-DONE`). Slow groups
were not re-run: the change is a pure rename/documentation pass with
no runtime semantics; unit+fast compile and exercise every call site,
property/integration cover JSON/replay. Full `qxfx0-test` and the core
slice were not re-run.

## (21) P3-техдолг: четыре низкорисковых пункта + верификация WIP-порогов — landed

Pre-reg `d0a60a1`, code `b1e207a`.

### Sites

- `Learning/Autonomous.hs`: `readLimit` клампит девять env-бюджетов
  и provider timeout к ≥ 0; `readIntWithDefault` сохраняет свои
  прежние семантики (негативы парсера остаются запинованными).
- `Bridge/SQLite/Queries.hs`: `bindTextOrFail` бросает структурную
  `SQLiteError` вместо проглатывания `Left`; три сырых query-пути
  (`queryExactTrigger`, `queryFTS5`, `queryTopicFallback`) переведены
  на него. Фасад `QxFx0.Bridge.SQLite` реэкспортирует хелпер.
- `maybeCheckpoint`: ошибка `wal_checkpoint` логируется в stderr
  (`[sqlite] wal_checkpoint failed: …`); обслуживание остаётся
  best-effort, без throw; гейт каждые 100 ходов не менялся.
- `Lexicon/Inflection.hs`: `lastCharOf` тотален (`Maybe Char`),
  `isConsonantEndingInf` трактует пустую строку как не-согласную;
  поведение непустых слов не менялось. Хелпер экспортирован ради
  прямого пина.
- WIP-порогов: верифицировано, что извлечение уже заленджено в
  `e2ecd0d` (`compositionShareFloor`, `analogyFallbackFloor`);
  `compositionShareThreshold`/`analogyDepth` в `src/`/`test/`/доках
  отсутствуют (кроме строки аудита). Новых констант нет; пункт
  закрыт верификацией.

### Pins

- `Autonomous` (+2, fast-only): `readLimit` (негатив → 0, валидное
  значение, default, мусор, негативный default) и config-пин с env
  `QXFX0_LEARNING_QUEUE_CAP=-5` → `awcQueueCap == 0` (переменная
  восстанавливается).
- `SQLiteRuntime` (+3, main/unit/fast): bind success (`SELECT ?` →
  значение), bind failure (`SELECT 1` + индекс 1 → `SQLiteErrorStructured`
  с `sedOperation = "bindTextOrFail-pin"`), `maybeCheckpoint` 99 —
  no-op, 100 — проход на реальной БД.
- `Lexicon` (+1, main/unit/fast): `lastCharOf "" == Nothing`,
  `lastCharOf "стол" == Just 'л'`, `dativeForm emptyMorphologyData "" ==
  ""`, `dativeForm … "стол" == "столу"`.

### Red check

- `readLimit` без `max 0` → ровно два Autonomous-пина падают
  (`readLimit clamps…`, `readAutonomousWorkerConfig clamps…`).
- Вернуть проглатывание `Left` в `bindTextOrFail` → падает ровно
  `bindTextOrFail rejects an out-of-range index` (теперь без маскировки
  ошибкой close: statement финализируется в `finally`).
- Вернуть `T.index` в `lastCharOf` → падает ровно totality-пин
  (`Data.Text…index: Negative index`).
- `maybeCheckpoint` `Left`-ветка не инъектируется через публичный
  DB API (read-only-инъекция хрупка); гейт-пин доказывает проход
  ветки на 100-м ходу, `Left`-ветка — типизированный one-liner.

### Matrix

Detached chains on the code tree, 2026-10-23, verdicts from logs:
unit 1817/1817 (1813 + 4: SQLiteRuntime +3, Lexicon +1), fast
1917/1917 (1911 + 6: Autonomous +2, SQLiteRuntime +3, Lexicon +1),
property 244/244, integration 47/47 — all exit 0 (`CHAIN1-DONE`
4672 s). Slow groups (substrate active): runtime 106/106, state
50/50, http 23/23, lifecycle 11/11 — all exit 0 (`CHAIN2-DONE`
9383 s).

### Ops note

- Первый прогон fast-слайса дал один разовый `SQLiteError,
  operation=close, rc=5` в `AutonomousIntegration` (закрытие БД при
  живом worker'е). Соло-прогон 65/65 дважды и повторный слайс 117/117
  зелёные; изменения батча не касаются жизненного цикла worker'а или
  close. Это известный класс изоляции, не регрессия батча; в полной
  матрице выше fast-прогон чистый (1917/1917).

### Honest limits

- `maybeCheckpoint` не бросает: лог — наблюдаемость, не политика
  отказа. `lastCharOf` экспортирован только ради прямого пина.

## Bootstrap-safety preflight — аудит 2026-10-16, follow-up 2026-10-23

### Finding

Свежий strict-state без `agda-witness.json` падает в
`bootstrapSession` на `HEALTH_GATE_FAILURE` **до** `Runtime.Engine`,
поэтому `--turn-json "не хочу жить"` возвращал `RuntimeInitError`
без crisis-resources. `crisisPreflightSurface` существовал, но
bootstrap-гейт был единственным путём, который его обходил.

### Behavior change (pre-registered before code)

- `--turn-json`: при ошибке **bootstrap** (не любого turn-а) и
  наличии острого crisis-маркера CLI возвращает синтетический
  Protocol B response: `status = ok`, `family = CrisisProtocolB`,
  `surface/output` = канонический `crisisPreflightSurface`, turns 0,
  без decision/trace. Non-crisis bootstrap failure по-прежнему
  пробрасывается (fail-closed).
- `--worker-stdio`: при ошибке bootstrap worker не выходит молча, а
  входит в preflight-only режим: отвечает на `hello` (handshake
  sidecar-а), отдаёт crisis-turn с тем же surface, на non-crisis turn
  возвращает `worker_bootstrap_failed` (fail-closed), на `shutdown`
  подтверждает остановку. Runtime session в этом режиме не создаётся.
- Здоровый runtime не меняется: preflight **не** выполняется перед
  bootstrap, обычный crisis-turn по-прежнему идёт через Engine и
  пишет trace/persistence. Меняется только путь «bootstrap уже
  сломан».

### Bar / pins

- `Test.Suite.CrisisGuard` +1: свежий strict-state без witness,
  `runTurnJson` с острым маркером возвращает `status=ok` и surface,
  содержащий `112` и `8-800-2000-122`; тот же state на non-crisis
  входе возвращает `Left` (fail-closed).
- Worker preflight проверяется smoke-прогоном `--worker-stdio`
  (hello → crisis turn → shutdown) на пустом strict-state; ручной
  smoke фиксируется в landing.

### Red check

- Убрать catch/bootstrap-fallback в `runTurnJson` → новый пин падает
  с `HEALTH_GATE_FAILURE` (surface не возвращается); restore →
  CrisisGuard зелёный.
- Убрать preflight-only ветку worker'а → hello на пустом state не
  приходит, sidecar получает worker-exit; restore → smoke проходит.

### Honest limits

- Синтетический response не является turn-ом: нет trace, нет
  persistence, `turns = 0`. Это аварийная выдача ресурсов, а не
  полноценный Protocol B turn; на здоровом runtime он не используется.
- Preflight-only worker рекламирует protocol capabilities, но
  non-crisis turn честно отклоняет; это не degraded runtime.
- Resource pack не менялся: 112 + 8-800-2000-122, `crVersion = 1`.

### Landing (2026-10-24)

- **Code**: `app/CLI/Turn.hs` (bootstrap-only catch + synthetic
  `CrisisProtocolB` response), `app/CLI/Worker.hs` (preflight-only
  protocol loop: `hello` handshake, crisis turns, `worker_bootstrap_failed`
  for other turns, shutdown). Healthy runtime keeps the original
  bootstrap → Engine path.
- **Catch class**: bootstrap acquisition catches the two boot-boundary
  classes explicitly: domain failures via `tryQxFx0` and I/O failures
  via `tryIO`. This is the same class matrix as
  `ExceptionPolicy.tryBootResource` (architecture rule [5] keeps
  `SomeException` out of app code). `AsyncException` and programming
  errors still rethrow: a broken disk must not hide a real bug, but
  must also not turn an acute crisis utterance into an error. The class
  matrix itself is pinned by `Test.Suite.BootBoundary` (IO caught,
  `ErrorCall` and `AsyncException` rethrown).
- **Pin**: `Test.Suite.CrisisGuard` 19 → 20 cases. The test uses an
  empty strict state with `QXFX0_AGDA_WITNESS` unset, asserts the
  surface contains `112` / `8-800-2000-122`, and asserts the non-crisis
  path is still `Left`.
- **Red check**: reverting only the CLI fallback yielded exactly one
  failure in the new CrisisGuard pin (`HEALTH_GATE_FAILURE`), with all
  other CrisisGuard cases green; restoring the fallback turned the
  slice green.
- **Smoke**: fresh strict state without witness:
  `--turn-json "не хочу жить"` → `status=ok`, `family=CrisisProtocolB`,
  surface carries both resource lines; `--turn-json "привет"` →
  `RuntimeInitError`; worker protocol: `hello` → `hello_ack`,
  crisis turn → same surface, non-crisis turn →
  `worker_bootstrap_failed`, `shutdown` → `status=ok`. A strict state
  with a freshly written witness still renders a normal `CMDefine` turn
  (`status=ok`, `turns=1`), so the healthy path was not replaced.
- **Matrix (bootstrap-safety tree)**: unit 1818/1818, fast 1918/1918,
  property 244/244, integration 47/47 (2026-10-24) — all exit 0. An
  earlier chained integration attempt hit a transient
  `No space left on device` during the nix/souffle eval
  (`Curated and ontology persistence integration`), not a runtime
  assertion; after the disk had free space the same 47 cases passed.
  Slow 190 was last green at P3 and was not re-run for this pin;
  main/core are registered at 1339/1219 and were not run as single
  processes. `qxfx0-test` and `qxfx0-test-slow` were rebuilt cleanly
  (warnings only) so the main/slow wiring is known to compile.
- **Architecture check**: at landing, `scripts/check_architecture.sh`
  reported two unrelated violations outside this change (bare partial in
  `Core/TurnPipeline/Effects.hs`; stale WP-F anti-rot label). Neither
  file was touched by the bootstrap-safety change. **Follow-up
  2026-10-24**: both are closed in the working tree (ownership-journal
  partials totalized; anti-rot label synced), and the full check is
  green. Do not cite the pre-fix red state as current.
