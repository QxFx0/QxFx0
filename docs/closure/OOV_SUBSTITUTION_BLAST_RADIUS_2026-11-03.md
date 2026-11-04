# OOV substitution — blast radius measurement

- **Status**: measurement complete; **no behaviour changed**.
- **Date**: 2026-11-03
- **Scope**: the `oov-005` failure recorded in
  `DIALOGUE_PILOT50_RESULT_2026-11-02.md` §3.5 — the question
  «что такое термоядерный синтез?» was answered about «синтез».
- **Purpose**: size the defect *before* writing a pre-registration, so the
  pre-registration can state the expected blast radius instead of guessing it.
- **Not claimed**: this document does not pass or fail any gate, does not
  change the pilot result (one-rater, not passed), and does not reopen the
  500-prompt gate (still BLOCKED).

## 1. What the substitution actually is

Two independent mechanisms can replace the user's topic with a different one.
Both are pre-existing, documented behaviours; neither is a bug introduced by
the pilot.

### Channel A — `canonicalTopic` truncates a phrase to its first content noun

`QxFx0.Semantic.Intent.Classifier.canonicalTopic` (unit `IntentDefine` and
`IntentDistinguish`) is documented as "canonicalize a topic surface to its
nominative lemma". It is implemented as:

```haskell
canonicalTopic morph topic =
  case extractContentNouns topic of
    (lemma:_) -> lemma                     -- first content noun wins
    [] -> fromMaybe topic (M.lookup ...)    -- fallback: whole phrase
```

`extractContentNouns` keeps only tokens whose POS is `Noun`
(`src/QxFx0/Semantic/Morphology.hs:336-341`), and POS comes from `guessPOS`,
which recognises an adjective by **suffix** — `-ный`, `-ский`, `-кий`, `-ной`,
`-ый`, `-ий`, `-ой`, `-емый`, `-имый` (`Morphology.hs:guessPOS`). Everything
else falls through to `otherwise = Noun`.

Consequences, all verified by running the production function:

| phrase | POS guess of the modifier | `canonicalTopic` | outcome |
|---|---|---|---|
| термоядерный синтез | Adj (`-ный`) → dropped | `синтез` | **substitution** |
| анализ данных | both Noun, first wins | `анализ` | **substitution** |
| время года | both Noun, first wins | `время` | **substitution** |
| гравитационная волна | `-ая` not an adjective suffix → Noun | `гравитационная` | fail-closed abstain |
| авторское право | `-ое` not an adjective suffix → Noun | `авторское` | fail-closed abstain |
| атомная энергетика | `-ая` → Noun | `атомная` | fail-closed abstain |

So the damage is not "any multiword term" — it is **the subset where the
leading modifier is classified as an adjective and the head noun is a corpus
topic**. Whether the modifier is recognised depends on its ending, which makes
the behaviour look erratic from the outside.

There is a second, narrower accident in the same function: `isContentNoun`
requires `T.length lemma > 3`, so a head noun of three letters is dropped and
`canonicalTopic` returns the **whole phrase** unchanged. Those phrases are the
only multiword topics that work. Verified live:

| prompt | answer | verdict |
|---|---|---|
| что такое читальный зал? | «читальный зал это место для чтения» | correct |
| что такое исходный код? | «исходный код это текст программы…» | correct |
| что такое электрический ток? | «электрический ток это направленное движение…» | correct |

### Channel B — `refineUncoveredTopic` retries with the first covered token

`Semantic/ResponsePlan.hs:138-146`, pre-registered 2026-09-25 for
clause-shaped topics («в чём смысл моей жизни» → «смысл»). It tokenises an
uncovered topic and returns the first token that is a corpus topic.

Confirmed live: «в чём смысл моей жизни?» is answered about «смысл» with
`trcContentSource = covered_exact` and the curated predicate
«смысл ищется в условиях абсурда». The clause is not the topic, exactly as
the pre-registration intended — but nothing distinguishes a clause from a
compound term.

### The interaction that matters for the fix

Today channel A runs **before** channel B, and after A the topic is a single
token, so B has nothing to work with.

If A is fixed in isolation (stop truncating), B receives the intact span and
retries with the first token that `isCoveredTopic` accepts — and `isCoveredTopic`
is the **172-topic seed corpus**, not the 4 070-topic answering corpus. So:

- «термоядерный синтез» → B tries «синтез», which is not a seed topic → no
  retry → **abstain** (today: substitution);
- «авторское право» → B tries «право», which **is** a seed topic → retry →
  **substitution** (today: abstain).

Fixing Channel A alone therefore trades one substitution for another rather
than removing the class. It is neither a no-op nor a fix — see §9.

## 2. Observed blast radius — the pilot

| slice | exposure | substitution | share |
|---|---:|---:|---:|
| all 50 prompts | 50 | 1 | 2% |
| OOV (5) | 3 multiword | 1 | 20% of 5 |
| anchor (30) | 0 multiword topics | 0 | 0% |
| held-out (15) | 0 multiword topics | 0 | 0% |

Every anchor and held-out prompt is a single-word topic, so those 45 rows had
**zero structural exposure** — the pilot could not have detected this defect
outside the OOV slice. `oov-004` («гравитационная волна») and `oov-001`
(«квантовая пена») failed closed; only `oov-005` produced content.

## 3. Observed blast radius — controlled probe

Seven compound/bare pairs, two persistent worker sessions, one prompt per turn.
The measure is *claim equality*: the answer is a substitution when the claim is
the same as for the bare head noun (the echoed question differs by design).

| compound | bare | claim identical | truncated to | verdict |
|---|---|---:|---|---|
| термоядерный синтез | синтез | **yes** | `синтез` | substitution, different domain |
| анализ данных | анализ | **yes** | `анализ` | substitution, genus-preserving |
| время года | время | **yes** (byte identical) | `время` | substitution, **different concept** |
| гравитационная волна | волна | no | `гравитационная` | fail-closed |
| авторское право | право | no | `авторское` | fail-closed |
| атомная энергетика | энергетика | no | `атомная` | fail-closed |
| аварийный выход | выход | no | `аварийный` | fail-closed |

3/7 substituted. The sample was chosen adversarially (I picked compounds likely
to truncate), so **3/7 is not a population rate** — it is the confirmation that
the mechanism predicted in §1 is the one that fires.

The three positive controls in §1 (читальный зал, исходный код, электрический
ток) show the complementary half: when the span survives, the answer is correct
and on-topic.

## 4. Structural blast radius — the corpus

Measured by running the **production** `canonicalTopic` over every multiword
curated topic (no adjective-ending heuristic; the real morphology resource).

| population | count |
|---|---:|
| curated topics | 4 036 (re-measured 2026-11-03; see the correction note in §9) |
| multiword curated topics | **624** (15.5%) |
| seed topics | 172 |
| multiword seed topics | **0** |

Outcome of `canonicalTopic` on the 624:

| outcome | count | share of multiword | share of curated |
|---|---:|---:|---:|
| collapses onto **another corpus topic** | **235** | 37.7% | 5.8% |
| …of those, onto a **seed** topic (canonical framing) | **69** | 11.1% | 1.7% |
| collapses onto no topic → fail-closed abstain | 373 | 59.8% | 9.2% |
| span preserved (head noun ≤ 3 letters) → reachable | 16 | 2.6% | 0.4% |

The 69 seed-head cases are the highest-severity class: the answer is rendered
with canonical framing (`Тезис:`/`Определение:`, `trcContentSource =
covered_exact`) about a different concept.

## 5. Semantic severity

Structural collapse is not the same as a false answer. Hand-classified with two
explicit labels:

- **genus-preserving** — the head noun is a hypernym, so the answer is off-target
  but not false («атомная энергетика» → «энергетика», «кислотный дождь» → «дождь»);
- **different concept / domain shift** — the head noun denotes something else in
  the corpus («время года» = season answered as time).

All 69 seed-head cases classified:

| class | count | examples |
|---|---:|---|
| genus-preserving | 64 | свобода слова → свобода; закон природы → закон; сила тяжести → сила |
| **different concept** | **3** | время года → время; млечный путь → путь; язык программирования → язык |
| borderline (needs a product decision) | 2 | смысл жизни → смысл; долг памяти → долг |

Deterministic 30-item sample of the other 165 (step = 165/30):

| class | count |
|---|---:|
| genus-preserving | 30 |
| different concept | 0 |

So the honest summary is: **the collapse is structural and common (234 topics),
the false-answer class is small (≈3-5 topics, ~1-2% of the multiword set)**.
`oov-005` is not in the 69 (its head «синтез» is curated-only, framed as
`Гипотеза:`), but it belongs to the same different-domain class: nuclear fusion
answered with a philosophical predicate about synthesis.

## 6. What this defect does not touch

- **Anchors (30/30)** and **held-out (15/15)**: all single-word topics.
- **M6-FELT bounded benchmark**: its 12 turns are single-word seed topics
  (`covered_exact` requires the 172-topic seed corpus, which contains no
  multiword keys), so the felt gate is structurally blind to this class.
- **M7 30-prompt packet**: same — single-word topics.

A green run of any existing gate is therefore not evidence about this defect.

## 7. Observability gap (found while measuring)

`trcBestTopic` is the **frame-level** best topic, not the topic the answer was
built from, and the two diverge in both directions:

| prompt | `trcBestTopic` | topic actually answered | what the trace shows |
|---|---|---|---|
| что такое термоядерный синтез? | `термоядерный` | `синтез` | looks like an uncovered term |
| что такое читальный зал? | `читальный` | `читальный зал` (correct) | looks identical to the row above |
| что такое атомная энергетика? | `энергетика` (covered) | none — abstained on `атомная` | shows a covered topic, yet the answer abstains |

So a replay reader cannot tell a substitution from a correct multiword answer,
and cannot explain the abstention in the third row. Any pre-registration that
wants the defect to be auditable needs a trace field carrying the *plan* topic
alongside the intent span.

## 8. Side finding — the corpus boundary is 172 topics, the answering corpus is 4 070

`isCorpusPredicate`, `isCoveredTopic`, `lookupDefinitionContent` and
`isFallbackTopic` all read the hardcoded `definitionCorpus` (172 seed topics),
while `csTopicPredicates` is built from the **merged** corpus
(curated 4 036 + seed 172, 138 shared keys → 4 070 merged topics,
`Runtime/Session/Bootstrap.hs:805`).

Consequence: a predicate that is human-curated corpus content under a curated
topic is classified as the system's own construction, so it renders as
`Гипотеза:` and traces as `uncovered_generic`. This is exactly the pilot's
held-out split: 12/15 «Гипотеза», and only the 3 seed topics
(смысл, сущность, будущее) got «Определение». The positive controls in §1 show
the same: three correct curated answers, all labelled `Гипотеза` /
`uncovered_generic`.

This is independent of the substitution, but it inflates the "hypothesis"
framing that the pilot read as honesty. It should be decided separately.

## 9. Options for the pre-registration (none implemented)

The four options are not independent: Channel A stops the span from ever
reaching Channel B, and Channel B is restricted to the **172 seed topics**
(`refineUncoveredTopic` tests `isCoveredTopic`, not `csTopicPredicates`, i.e.
not the 4 070-topic answering corpus — a third boundary inconsistency).

Projected effect on the 7 probe pairs and on the 624 multiword curated topics
(definitional question form only — other question shapes do not canonicalize):

| # | change | multiword corpus topics (624) | ООV compound | risk |
|---|---|---|---|---|
| 1 | **Disclose** — trace the intent span and the plan topic; no surface change | unchanged | unchanged | none; makes the defect auditable but does not fix it |
| 2 | **Stop truncating** in `canonicalTopic` — keep the span, exact lookup only (no per-token lemmatization, see the correction note) | **608 → answer the correct compound** (all 624 spans are corpus topics; today only the 16 with a 3-letter head are reachable) | термоядерный синтез → abstain ✓, анализ данных → correct compound ✓, **цифровая свобода → substitution ✗** (refine reaches `свобода`, a seed topic) | mixed: large corpus win, small OOV regression |
| 3 | **Gate `refineUncoveredTopic`** — retry only for clause-shaped topics | none (the span is already truncated before refine runs) | none on its own | inert without 2 |
| 4 | **2 + 3 together** | 608 → correct compound | термоядерный синтез → abstain ✓; анализ данных / авторское право / цифровая свобода → correct compound or abstain, never the head noun | largest surface churn; the only combination that removes the substitution |

Two things a pre-registration must therefore state explicitly:

- **Option 2 alone is not a fix and is not neutral.** It repairs 608 corpus
  topics and, by unblocking Channel B, turns today's fail-closed abstention on
  an **OOV compound whose head is a seed topic** into a substitution
  («цифровая свобода» → «свобода», «коллективная память» → «память», both
  verified 2026-11-03). A "fix the obvious truncation" commit would pass the
  anchors and still fail the honesty bar on OOV.
- **Option 3 alone is inert.** Today `canonicalTopic` has already reduced the
  topic to a single token before `refineUncoveredTopic` sees it, so gating
  refine changes no observed surface.

Both are behaviour changes and need the pre-registration to pin:
the exact population (the numbers in §4), a red-check that fails before the fix
and passes after, a pin that the 30 anchors stay byte-identical, and a decision
on the 3 different-concept cases in §5.

### Correction note (2026-11-03, after re-measuring with the production functions)

- Population re-counted against today's `resources/knowledge/curated_predicates.jsonl`:
  4 036 curated topics / 4 070 merged / 235 collapse / 69 seed-head / 373 abstain
  (was 4 046 / 4 080 / 234 / 69 / 374). The 16 span-preserved cases are unchanged.
- **The «авторское право» example was wrong**: it is itself a curated corpus
  topic, so span preservation makes it *covered* and `refineUncoveredTopic` is
  never reached. The class is real but its examples are OOV compounds whose head
  is a seed topic: «цифровая свобода» → «свобода», «коллективная память» →
  «память».
- **"Stop truncating" must not mean per-token lemmatization.** The corpus keys
  are surface phrases («смысл жизни», «анализ данных»), and per-token
  lemmatization breaks **247/624** of them («смысл жизни» → «смысл жизнь»).
  The span rule is exact lookup only; see
  `docs/closure/OOV_TOPIC_SPAN_PREREG_2026-11-03.md` §2.
- The **3 different-concept cases** (§5) all have on-topic curated predicates
  («время года это сезон», «млечный путь это галактика…», «язык программирования
  это формальный язык…»), so "answer the compound" needs no special case.


## 10. Evidence

Local, gitignored, reproducible:

- `/tmp/opencode/blast-probe/` — 10 probe turns, per-turn `surface` + trace.
- `/tmp/opencode/trunc.out` — production `canonicalTopic` over all 624
  multiword curated topics.
- `/tmp/opencode/blast_exact.json` — the 234/69/374 classification.
- `/tmp/opencode/trunc.hs` — the probe harness (loads the real morphology
  resource; no runtime turn, no state).

Probe design: one prompt per turn, two persistent `--worker-stdio` sessions, so
each pair differs only in the question text; the session is reused, so carried
state is a shared confound for both halves of a pair.
