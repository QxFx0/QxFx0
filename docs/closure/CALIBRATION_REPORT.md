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
- **Residual**: predicate-level provenance (generated predicate under
  a covered topic) still renders canonical — needs a `spProvenance`
  field (schema change, deferred).
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
