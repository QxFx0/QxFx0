# Pre-registration — multiword topic spans (2026-11-03)

- **Status**: **SIGNED (D-1…D-5 as written, 2026-11-04).** Nothing is
  implemented: the code change, the red checks and the matrix land under this
  document.
- **Owner signature**: 2026-11-04, all five decisions of §9 as written,
  including the accepted costs — inflected multiword queries abstain (§2) and
  OOV 3+-token seed-head spans still refine (§3).
- **Predecessor**: `docs/closure/OOV_SUBSTITUTION_BLAST_RADIUS_2026-11-03.md`
  (mechanism, probe, corpus blast radius, options). Its §9 recommendation is
  corrected here in §1; its population numbers are re-measured against today's
  data files (correction note in the predecessor's §9).
- **Trigger**: `pilot50-20261102b`, `oov-005` («что такое термоядерный
  синтез?») answered about «синтез» — a different domain, framed as the
  system's own hypothesis. The pilot row failed; the mechanism predates it.
- **Scope**: semantic core only — `canonicalTopic`
  (`Semantic/Intent/Classifier.hs`), the `refineUncoveredTopic` call site
  (`Semantic/ResponsePlan.hs`), and one replay-trace sub-record. No corpus edit,
  no GF change, no prompt-file change, no routing/anomaly/essence change.
- **Not a math change**: no scoring, no threshold, no encoder. `currentMathVersion`
  stays at 3.

## 0. What the fix must and must not do

Must:

1. stop replacing a multiword topic with one of its parts;
2. keep the pre-registered 2026-09-25 clause behaviour («в чём смысл моей
   жизни» → answered about «смысл»);
3. leave every single-word topic byte-identical;
4. make the substitution visible in the replay trace.

Must not:

1. change any surface that is already correct (anchors, held-out, the 16
   working multiword topics);
2. turn an abstention into a *wrong* answer anywhere (§4 is exactly this risk);
3. require a corpus rewrite, a lexicon addition, or a new heuristic lexicon.

## 1. Corrections to the predecessor document

Measured today with the production functions against
`resources/knowledge/curated_predicates.jsonl` (6 238 rows, 4 036 distinct
topics) and the 172-key seed corpus:

| item | predecessor | measured today |
|---|---:|---:|
| curated topics | 4 046 | **4 036** |
| merged runtime topics | 4 080 | **4 070** (138 shared keys) |
| multiword curated topics | 624 | 624 |
| `canonicalTopic` preserves the span | 16 | 16 |
| collapses onto another corpus topic | 234 | **235** |
| …of those onto a seed topic | 69 | 69 |
| collapses onto nothing (abstain) | 374 | **373** |

The predecessor's §9 claim that **option 2 alone turns «авторское право» into a
substitution is wrong**: «авторское право» is itself a curated corpus topic
(1 predicate, «авторское право защищает права авторов произведений»), so
span preservation makes it *covered*, and `refineUncoveredTopic` is never
reached (`buildGroundedPlan` only refines an uncovered topic). The class the
predecessor was reaching for is real, but its examples were wrong:

| compound | merged corpus | `refineUncoveredTopic` | today | option 2 alone |
|---|---|---|---:|---|
| цифровая свобода | **absent** (OOV) | → **свобода** (seed) | abstain | **substitution** |
| коллективная память | **absent** (OOV) | → **память** (seed) | abstain | **substitution** |
| авторское право | present | not reached | abstain (today truncates to «авторское») | answers «авторское право» |
| термоядерный синтез | absent | → none («синтез» is not a seed topic) | substitution | abstain |

So: option 2 alone repairs 608 corpus topics and introduces a **new, measured**
substitution class — OOV compounds whose head is one of the 172 seed topics.
It is not neutral. Option 3 alone remains inert (§9 of the predecessor holds).

## 2. Decision D-1 — the span rule is exact lookup, not lemmatization

The obvious implementation — "keep every token and lemmatize each one" — is
disqualified by measurement. The corpus keys are **surface phrases, not
lemmas**: «смысл жизни» (genitive head), «анализ данных», «время года»,
«осознанность выбора». Running per-token lemmatization over the 624 keys:

```
non-fixpoints: 247/624   (39.6%)
  автоматизация процессов -> автоматизация процесс
  акт доверия             -> акт доверие
  смысл жизни             -> смысл жизнь
  время года              -> время год
```

Under that rule 247 corpus topics would become unreachable — a 40% regression
of the population the fix exists to repair.

**Signed rule (proposed):**

```text
canonicalTopic morph topic =
  case T.words (T.strip topic) of
    [w]  -> <today's behaviour, byte-identical>   -- one token: its lemma
    span -> T.unwords span                        -- multi-token: NO rewriting,
                                                  -- not even case folding
```

Case matters: three multiword keys are mixed-case English («Raspberry Pi»,
«Spring Boot», «Standing ovation») and `buildGroundedPlan` tests membership in
`csTopicPredicates` with a case-sensitive `M.notMember`, so a lowercased span
would make them unreachable. No key contains a double space, so `T.words`
collapsing is safe today (checked over the 624).

The existing whole-phrase `mdNominative` lookup is kept as the last fallback:
`mdNominative` is keyed by single words, so for a span it can only miss and
return the span unchanged — which is exactly the wanted answer.

Consequence, stated as an accepted cost rather than hidden: an **inflected
multiword** query («о смысле жизни») no longer resolves to any topic and
abstains. Today the same query is answered about the head noun («смысл»), i.e.
the defect being removed. Queries that already abstain today, such as
«атомной энергетики» (truncates to «энергетики», which is not a key), keep
abstaining — nothing is lost there. A form-tolerant multiword lookup (a
lemma-signature index that normalizes keys and queries identically) is the
principled successor and is **out of scope**
(§8): it changes corpus *lookup*, not topic canonicalization, and it belongs
in its own pre-registration with its own collision measurement.

## 3. Decision D-2 — the refine gate lives at the call site

`refineUncoveredTopic` is itself unchanged: six unit pins in
`Test.Suite.ResponsePlan` (`testRefineUncoveredTopic`) stay byte-identical,
including `refine "свобода" == Just "свобода"` and the negation guard. The
gate is applied in `buildGroundedPlan` before retrying:

```haskell
-- retry only for clause-shaped spans: the 2026-09-25 pre-registration
-- produced 4-token clauses; every measured substitution is a 2-token term.
            [t]
              | clauseShaped t -> case refineUncoveredTopic (csLemmaMap selector) t of
                  Just t2 | t2 /= t -> buildGroundedPlan goal [t2] mActiveQuestion selector field mActivation
                  _ -> fallbackPlan goal TopicNotCovered (Just topic)
              | otherwise -> fallbackPlan goal TopicNotCovered (Just topic)
  where
    clauseShaped = (>= 3) . length . T.words
```

Why a token count and not "contains a function word": `guessPOS` classifies
«моей» as `Noun` (`-ей` is not an adjective or verb suffix), so a
function-word test needs a **new hand-written lexicon**, which is the exact
kind of heuristic this project has been removing. A count is total,
deterministic, and needs no data.

Residual class, stated explicitly: an **OOV 3+-token** span whose first covered
token is a seed topic still refines (e.g. a hypothetical «цифровая свобода
воли»). The gate removes the measured 2-token class; it does not prove the
general property. That weakness is why §6 pins the four measured cases by
name rather than claiming the class is closed.

## 4. Decision D-3 — the three different-concept cases need no special case

The predecessor's §5 asks for a product decision on three seed-head collapses.
Measured today, all three are curated corpus topics **with on-topic content**:

| topic | curated predicates |
|---|---|
| время года | «время года это сезон»; «время года определяет погоду» |
| млечный путь | «млечный путь это галактика в которой находится солнечная система»; «млечный путь виден на ночном небе» |
| язык программирования | «язык программирования это формальный язык для написания программ»; «… имеет свой синтаксис и семантику» |

So the correct outcome for all three is "answer the compound", and it follows
from D-1 mechanically — no per-topic branch, no alias table, no corpus edit.

**Accepted framing cost (not fixed here):** all three are curated, not seed,
topics, so the answer renders as `Гипотеза:` /
`trcContentSource = uncovered_generic` instead of `Определение:` /
`covered_exact` — the 172-vs-4 070 boundary of the predecessor's §8. That
boundary is a **separate** decision (§8); this pre-registration only requires
that the *topic* be right.

## 5. Decision D-4 — disclosure is part of this change, not a follow-up

Verification of D-1/D-2 needs the answered topic in the replay trace, and
`trcBestTopic` is the **frame-level** best topic (§7 of the predecessor:
`термоядерный` vs `синтез`, `читальный` vs `читальный зал`). Without disclosure
the post-fix claim "the compound was answered" would rest on surface text
alone — the same weakness that made `oov-005` invisible.

**Signed rule (proposed):** one nullable sub-record, following the
`trcUserRegime` precedent (P1-4: new clusters grow a sub-record, not the
god-record):

```haskell
data TopicResolutionTrace = TopicResolutionTrace
  { trtIntentTopic :: !Text          -- span after canonicalTopic
  , trtPlanTopic   :: !(Maybe Text)  -- topic the plan actually used; Nothing on fallback
  , trtResolution  :: !Text          -- "exact" | "refined" | "fallback"
  }
```

Wiring follows the existing `content_source=` mechanism: Render emits
`topic_span=…`, `plan_topic=…`, `topic_resolution=…` derivation tags,
`Finalize/Projection.hs` extracts them into `trcTopicResolution`
(`trcContentSource` / `trcAnalogicalSource` are built exactly this way, so no
new `TurnArtifacts` field is required). JSON is backward-compatible:
absent → `Nothing`, `*.cabal` unaffected. Existing tests that construct a
`TurnReplayTrace` by hand get one more `Nothing` default (§7 pins them).

## 6. Population and bars (pre-registered, not tunable after the run)

Population: the 624 multiword curated topics, the 4 036 − 624 single-word
curated topics, and the 172 seed topics (union after the 138 shared keys:
4 070 topics, of which 3 446 single-word), from the files on disk at
implementation time. If the curated file changes between signing and landing, the population
is re-counted **and reported**, not silently substituted.

| bar | statement | today | required after |
|---|---|---:|---:|
| **B1** | `canonicalTopic(key)` returns `key` byte-identically for all 624 multiword keys (3 of them mixed-case) | 16/624 | **624/624** |
| **B2** | the 16 currently preserved spans are byte-identical | 16/16 | 16/16 |
| **B3** | every single-word merged topic (4 070 − 624 = 3 446 keys) canonicalizes byte-identically | 3 446/3 446 | 3 446/3 446 |
| **B4** | four OOV probes produce **no** claim about their head noun: цифровая свобода≠свобода, коллективная память≠память, термоядерный синтез≠синтез, гравитационная волна≠волна | 1/4 violate (термоядерный синтез) | **0/4**; D-1 alone gives 2/4 |
| **B5** | «в чём смысл моей жизни» still resolves to «смысл» (2026-09-25 pin) | yes | yes, same surface |
| **B6** | 30 anchors + 15 held-out surfaces byte-identical | 45/45 | 45/45 |
| **B7** | multiword keys that become unreachable | — | **0** |
| **B8** | test matrix per group | green at `c2383d9` | green, no new failures |

**B4 is a two-part bar on purpose**: under D-1 alone the count must *not fall*
(1/4 → 2/4 — it repairs «термоядерный синтез» and introduces the two seed-head
substitutions), and under D-1+D-2 it must be zero, so the gate earns its place
instead of being assumed. The red check is: implement D-1 only, run the four
probes, observe exactly 2 violating rows, both seed-head.

Reporting bars (measured, **not** gated — they shift for reasons unrelated to
this change and must not be read as improvement or regression): intended
family fit, `fallback_drift`, `gf_mapped_fallback`, `trcContentSource`
distribution. After the fix a large number of turns move from
`uncovered_generic` to `covered_*`, so **no before/after comparison of those
rates is admissible**; the pilot50 baseline stays valid only as a "before"
measurement.

## 7. Verification mechanics

- **B1/B2/B3/B7** — new suite `Test.Suite.TopicSpan` (fast suite, it reads the
  curated file): O(3 446) byte-identity check plus the 624-key fixpoint
  enumeration; pure cases (span preserved, single-word unchanged, punctuation
  edges) in the unit suite. Registration in `test-common` + `TestMainFast` +
  `TestMainUnit`.
- **B4** — probe harness `/tmp/opencode/blast_probe.py` style, 2 persistent
  `--worker-stdio` sessions, one prompt per turn, claim equality against the
  bare head noun. Three runs: today (expect 1/4 violating rows), D-1 only
  (expect 2/4, both seed-head → red), D-1+D-2 (expect 0/4 → green).
- **B5** — pinned in `Test.Suite.ResponsePlan` as a call-site test (the six
  existing `refineUncoveredTopic` pins are untouched).
- **Trace schema** — `docs/closure/TRACE_SCHEMA.md` gains the sub-record in the
  same commit; `scripts/check_replay_trace_fields.py` is untouched (it asserts
  *required* fields only, and the new one is optional).
- **B6** — replay the frozen `spec/gf/release_corpus_prompts.txt` and the
  pilot50 harness file; compare `surface` bytes against
  `m7-gf-confirm-20261031` and `pilot50-20261102b`.
- **B8** — per group, sequential, as in `TEST_MATRIX_2026-11-01.md`:
  `qxfx0-test` core is not re-run in one process (15 GB / substrate OOM
  contour); runtime and http groups are.

## 8. Out of scope (explicitly)

1. **The 172-vs-4 070 corpus boundary** (predecessor §8) — `isCoveredTopic`,
   `isCorpusPredicate`, `lookupDefinitionContent`, `isFallbackTopic` reading the
   seed corpus while the selector reads the merged one. This is the *framing*
   bug (`Гипотеза:` for human-curated content) and it outranks this fix in
   severity. Separate pre-registration.
2. **Form-tolerant multiword lookup** (lemma-signature index) — the principled
   replacement for the accepted cost in §2.
3. **GF slot coverage** — S2 (bars) and S3 (staging) remain open in
   `GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md`. No slot rows are added here.
4. **The 500-prompt gate** — still blocked on a labeled corpus.
5. **Corpus data hygiene** found while measuring: the multiword key set
   contains non-topics and typos — «к полезности», «не согласиться»,
   «почему а не зачем», «преемственность я», «э эксперимент», «чуваство вины»
   (sic). They are kept untouched; B1 counts them like any other key.
6. **Warm-latency stage split** — needs its own instrumentation pre-reg.

## 9. Open decisions (owner signature)

| id | decision | recommendation |
|---|---|---|
| D-1 | exact-span rule, no per-token lemmatization, accepting abstention for inflected multiword queries | **sign as written** (§2); the alternative loses 247/624 keys |
| D-2 | refine gate = "≥ 3 tokens", applied at the call site | **sign as written** (§3); no new lexicon |
| D-3 | no special-casing for время года / млечный путь / язык программирования | **sign as written** (§4); corpus content is on-topic |
| D-4 | disclosure sub-record `trcTopicResolution` inside this change | **sign as written** (§5); without it the post-fix claim is unverifiable |
| D-5 | landing order: D-1+D-2+D-4 in one commit, matrix, then post-fix measurement | **sign as written**; splitting D-1 alone would land a known regression (§1) |

**All five signed 2026-11-04 as written.** This document now authorises
exactly one change — D-1 + D-2 + D-4 in a single commit (D-5) — and nothing
else: no corpus edit, no slot rows, no §8 boundary work.

## 10. Rollback

Two pure functions plus one nullable trace sub-record. Reverting the two
functions restores the exact pre-change behaviour (`git revert` of the code
commit); the trace field is `Maybe` and JSON-backward-compatible, so a revert
leaves old traces readable and new ones merely unpopulated. No persisted state,
no DB migration, no corpus file, no GF artifact is touched.

## 11. Evidence (local, gitignored, reproducible)

- `/tmp/opencode/classifybin` (source `classify.hs`) — production
  `canonicalTopic` over the 624 multiword keys, classified against the merged
  corpus; produced the §1/§2/§6 numbers above.
- `/tmp/opencode/spanbin` (source `span.hs`) — the per-token-lemmatization
  candidate, 247/624 non-fixpoints; `refineUncoveredTopic` over the OOV
  seed-head class.
- `/tmp/opencode/member.hs` — merged-corpus membership of every example quoted
  in §1 and §4.
- `/tmp/opencode/b4bin` (source `b4.hs`) — today's `canonicalTopic` for the
  four B4 probes: «цифровая свобода» → «цифровая», «коллективная память» →
  «коллективная», «термоядерный синтез» → «синтез» (the single violation),
  «гравитационная волна» → «гравитационная».
- `/tmp/opencode/blast-probe/` — the original 10 probe turns (§3 of the
  predecessor); the harness is reused unchanged for B4.
- Build recipe: `cabal exec -- ghc -package=qxfx0 …` then run with
  `LD_LIBRARY_PATH=/home/liskil/gf-core/src/runtime/c/.libs` (pgf2 links
  `libpgf.so.0`).
