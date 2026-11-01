# M7 fallback content review — 14 turns (2026-11-01)

- **Status**: content review of the 14 turns that used
  `DeriveGfMappedFallback` in the confirmatory packet
  `m7-gf-confirm-20261031`.
- **Scope**: quality of the emitted predicate, not the gate. The gate already
  passed 30/30 under the pre-registered rule; nothing here re-opens it.
- **Method**: for every fallback turn the trace carries three predicates —
  the golden predicate, the predicate the system selected *before* the GF
  filter (`pdRejectedAlternatives[0]`), and the predicate actually emitted
  (`pdPredicateRefs[0]`). All three were compared semantically.
- **Who judged**: an analytical pass by the agent. This is not the owner's
  content sign-off; the rows marked `weak` below still need a human decision.

## Structural finding first

**0 of the 14 selected predicates have GF slots.** That is why the fallback
fires: the system picks predicate A, A has no entry in
`curated_predicate_slots.tsv`, so the builder substitutes the highest-ranked
*mapped* predicate B for the same topic.

So the fallback is behaving correctly (it keeps authority and grammar), but it
overrides the system's own content choice on **47% of the curated packet**
(14/30). The fix is coverage, not logic — but *not* the 14 observed rows: that
would be fitting one recorded run. S1 signed on 2026-11-02 is the
anchor-complete scope (207 rows), see
`docs/closure/GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md`. It is a behaviour
change and needs its own admissible-set pre-registration, because it will change
surfaces.

### Measured coverage (2026-11-01)

The runtime corpus is the merge of the 172 hand-written topics in
`src/QxFx0/Semantic/Content.hs` and the curated JSONL file
(`mergeCuratedIntoDefinitionCorpus`). Numbers below are counted against that
merged corpus, not against the JSONL alone:

| quantity | value |
|---|---:|
| JSONL lines | 6 238 |
| distinct topics in the JSONL (1 011 topics are duplicated; the loader merges them and drops only exact-duplicate predicates) | 4 036 |
| merged runtime topics (4 036 curated + 172 seed, overlap merged) | 4 070 |
| merged predicate rows | 12 000 |
| distinct predicate surfaces | 11 997 |
| rows in `spec/gf/curated_predicate_slots.tsv` | 84 |
| slot-table surfaces that match a merged-corpus predicate verbatim | **79** |
| **corpus coverage** | **0.66%** |

The 4 036 figure is confirmed by the runtime itself: bootstrap logs
`Curated predicates loaded topics=4036`.

Per split:

| scope | predicate rows | with slots | coverage |
|---|---:|---:|---:|
| 30 anchor topics (seed topics, enriched by curated rows) | 286 | 79 | 28% |
| 15 pilot held-out topics | 96 | 0 | 0% |
| everything else | ~11 600 | 0 | 0% |

Consequences:

1. **The slot table is a hand-curated sample, not a corpus projection.** Its 84
   rows are hand-written `subject/relation/object` triples; 5 of the 84
   `source_ru` surfaces do not appear in the merged corpus at all
   (e.g. «власть определяет, чья воля становится законом»).
2. **Its subject coverage is exactly the 30-topic release corpus.** Counted by
   `subject_ru`, the 84 rows span 30 distinct topics — precisely the 30 anchors
   of `spec/gf/release_corpus_prompts.txt`, with 2–8 rows each (истина 8,
   свобода 6, ответственность 6, …). None of the other 4 040 merged topics has
   a slot. So the table is co-extensive with the *release corpus*, not with the
   runtime corpus, and `gf_mapped_fallback` is the price of that scoping, paid
   even inside the 30 (`14/30`).
3. **No gate keeps the two artifacts in sync.** `scripts/export_lexicon.py`
   reads `curated_predicate_slots.tsv` and emits
   `src/QxFx0/Lexicon/Generated/SemanticSlots.hs`; its `--check` mode (wired
   into `scripts/check_generated_artifacts.sh` and CI) only verifies that the
   generated Haskell is up to date with the slot table. Nothing compares either
   with `curated_predicates.jsonl`. `scripts/gf_quality_gate.sh` check 3 only
   looks for 9 core nouns in the GF lexicons. This is the root cause: every new
   curated topic is born without GF slots and will silently take the fallback.

### What this predicts for the 50-prompt pilot

The pilot's 15 held-out topics (смысл, идентичность, граница, …) have **0 of
their 96 predicates in the slot table — 15 topics out of 15**. In
`buildGroundedPlan` the mapped selection is empty for such a topic
(`selected = if null mappedSelected then originalSelected else mappedSelected`),
so the system's own predicate survives, but `lookupSlots` then fails and the GF
plan yields `Nothing`. The held-out split therefore measures the **unmapped
render path**, not the GF path the 30 anchors exercise — held-out rows cannot
be a like-for-like extension of the anchors. This has to be stated in the pilot
result before any pass-rate comparison across splits. (Behaviour predicted from
code; an end-to-end confirmation turn is the first item after the test matrix
finishes.)

## The 14 rows

| id | topic | golden | selected (discarded) | emitted | verdict |
|---|---|---|---|---|---|
| gf-rel-007 | воспоминание | восстанавливает пережитое в новой рамке | восстанавливает прошлое в настоящем | воспоминание есть акт обращения к личному прошлому | acceptable |
| gf-rel-008 | сознание | способность осознавать мир и себя | есть основание субъектности | сознание объединяет восприятие и рефлексию | acceptable |
| gf-rel-013 | доверие | строится через повторяемый позитивный опыт | открывает возможность сотрудничества | доверие предполагает уязвимость перед другим | acceptable |
| gf-rel-016 | справедливость | соразмерность деяния и воздаяния | требует равенства возможностей | справедливость требует соразмерности между деянием и воздаянием | harmless (equals golden) |
| gf-rel-017 | время | необратимо, прошлое недоступно | устанавливает границы между прошл**и**м и будущим | время задаёт порядок следования событий | acceptable |
| gf-rel-020 | история | зависит от точки зрения рассказчика | складывается из событий и их интерпретации | история связывает прошлое с настоящим через интерпретацию | acceptable |
| gf-rel-021 | язык | связан с мышлением, формирует мысль | выражает и структурирует мысль | язык структурирует опыт через различение и именование | **drift (aspect)** |
| gf-rel-023 | смерть | необратимое прекращение существования | выражает конечность бытия | смерть обозначает необратимое прекращение существования | harmless (equals golden) |
| gf-rel-024 | одиночество | отсутствие значимого другого | обнаруживает границу между я и другими | одиночество выражает отсутствие значимого другого | harmless (equals golden) |
| gf-rel-025 | любовь | направлена на конкретного другого как безусловно ценного | преодолевает границу между я и другим | любовь направлена на конкретного другого как на безусловно ценного | harmless (equals golden) |
| gf-rel-026 | труд | связан с потребностью и распределением | выражает целенаправленное усилие | труд преобразует материал через целенаправленное усилие | acceptable |
| gf-rel-027 | покой | отсутствие движения и напряжения | выражает отсутствие напряжения | покой обозначает отсутствие движения и напряжения | harmless (equals golden) |
| gf-rel-028 | власть | способность влиять на действия других | способность и возможность влиять на поведение людей | власть требует легитимности для устойчивости | **weak** |
| gf-rel-030 | молчание | контрастирует с речью, не тождественно пустоте | выражает позицию через отсутствие слов | молчание может быть актом отказа или знаком присутствия | acceptable |

## Tally

| verdict | count | ids |
|---|---:|---|
| harmless (emitted = golden) | 5 | 016, 023, 024, 025, 027 |
| acceptable substitute | 7 | 007, 008, 013, 017, 020, 026, 030 |
| drift (aspect) | 1 | 021 |
| weak | 1 | 028 |

## The two rows that need an owner decision

- **gf-rel-028 (власть).** Golden and the system's own choice both define power
  as *the ability to influence others*. The emitted predicate is
  «власть требует легитимности для устойчивости» — a true statement, but it
  answers "what does power need", not "what is power". This is the one row
  where the fallback visibly degrades the answer.
- **gf-rel-021 (язык).** Emitted «язык структурирует опыт через различение и
  именование» is defensible, but it drops the golden's link to *thinking* and
  moves the topic to *experience*. Borderline; acceptable only if the owner
  considers the experience framing equivalent for this corpus.

## Defects found along the way

- **Corpus typo**: `resources/knowledge/curated_predicates.jsonl:148` has
  «время устанавливает границы между **прошлим** и будущим» — missing «е»
  («прошлым»). It surfaces whenever that predicate is selected, and it is
  currently invisible only because the fallback replaces it. **Fixed
  2026-11-02** in the data-only commit `bec1d19` (owner decision); verified with
  the `CuratedPredicates` suite slice (18 cases green).
- **A second corpus typo found while fixing this one**:
  `curated_predicates.jsonl:147` has «воспоминание преобразкет пережитое в новую
  рамку» («преобразкет» for «преобразует»). Not fixed — outside the approved
  one-line change; recorded here so it is not lost.
- **Coverage hole**: the same 14 predicates are absent from
  `curated_predicate_slots.tsv`. Worth checking whether the whole
  `curated_predicates.jsonl` and the GF slot table are kept in sync by any
  gate; if not, that is the root cause and it will recur for every new topic.

### Corpus-level findings (measured 2026-11-01)

These matter for the *unmapped* text path, which serves 99.3% of topics.

| finding | count |
|---|---:|
| predicate rows with no punctuation at all (`, — : ; ( )`) | 12 455 / 12 474 (99.8%) |
| «X это Y» predicates | 5 244 |
| … of those, missing the dash/comma that Russian requires | 5 241 |
| «который» clauses with no comma | 21 |
| topics containing Latin characters (IT terms: `devops`, `docker`, `vpn`, `C#`, `Go`, `AI`) | 746 / 6 238 lines |
| topics with leading/trailing/double spaces (`" office"`, `" климат"`, `" novel"`) | 3 |
| prefix-junk topic (`«э эксперимент»`) | 1 |
| one surface shared by two different topics (excluding the two junk topics) | 1 (`роман …` under `роман` and ` novel`) |

Consequence: on the GF path the grammar supplies the punctuation, so the defect
is invisible. On the text path the surface is emitted as stored — the observed
held-out answer «Определение: смысл ищется в условиях абсурда» carries no
punctuation of its own, and a predicate of the «X это Y» form would render as
«X это Y» with no dash or comma («смысл это значение которое придается жизни»)
because nothing in the text path repairs it. That is a render/quality issue to
fix before the pilot's held-out split is judged, or the `held-*` rows will lose
R4 points for a corpus artefact rather than a runtime defect.


## Recommended order of work

1. Fix the corpus typo (data-only, no behaviour change for the packet because
   that predicate is currently discarded anyway).
2. Pre-register + extend `curated_predicate_slots.tsv`. **Do not scope this to
   the 14 observed fallbacks**: selection is Field-dependent (three repeats of
   «что такое свобода?» in one session produced two different predicates), so
   14 rows would only fit one recorded run. The honest scopes are 207 rows
   (anchor-complete) or 303 (anchor + pilot held-out) — see
   `GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md`.
3. Re-run the packet. Expect the fallback count to drop and the emitted
   predicate to become the system's own choice.
4. After that re-run, re-derive the admissible sets — **a new pre-registration
   is required**; the current frozen TSV stays as the record of what passed on
   2026-10-31.
5. Only then re-judge 021 and 028, because both may disappear once the
   selected predicate survives the GF filter.

Separately, the unmapped path needs its own fix list (behaviour change, own
pre-registration): the duplicated «(основание: X)» clause and the
`Определение:`/`Гипотеза:` flip. Neither is an M7 gate issue, but both will
dominate any evaluation that leaves the 30 anchors.

## Honest limits

- Verdicts are a single analytical pass, not inter-rater agreement.
- The comparison is predicate-level; it does not score the full surface,
  counterpoint quality, or conversational appropriateness.
- "Acceptable" here means "a correct definition of the topic", not "the best
  definition" and not "the definition a user would want".
