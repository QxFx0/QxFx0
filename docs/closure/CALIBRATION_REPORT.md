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
