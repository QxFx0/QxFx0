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
  (55/120 topics without lexemes) recorded as data backlog.
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
  entry blocks (asserted 120 topics). Results:
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
