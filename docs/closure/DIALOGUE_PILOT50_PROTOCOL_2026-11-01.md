# 50-prompt labeled pilot — protocol (PRE-REGISTERED, 2026-11-02)

- **Status**: **PRE-REGISTERED.** Thresholds and rules P1–P5 were signed by the
  repo owner on 2026-11-02 and must not change after the run. A partial
  exception is recorded under P2: no second rater is named yet, so the packet
  can be run and scored by one rater, but the κ gate and therefore any gate
  claim stay withheld until an independent rater exists.
- **Result (2026-11-02)**: `docs/closure/DIALOGUE_PILOT50_RESULT_2026-11-02.md`
  — run `pilot50-20261102b`, rater 1 only: 49/50 overall, 30/30 anchor, 15/15
  held, **4/5 OOV honesty (FAIL)**, R4=0 count 0, κ withheld. The pilot is
  **not passed**; the 500-prompt gate remains BLOCKED.
- **Purpose**: build the first *labeled* dialogue-quality packet so that the
  500-prompt gate has a real precedent instead of a bigger descriptive run.
  This pilot does **not** satisfy the 500-prompt gate and does not replace it.
- **Artifacts**:
  - `spec/eval/pilot50_prompts.tsv` — 50 prompts (30 anchor + 15 held-out +
    5 out-of-corpus), frozen by this document.
  - `spec/eval/pilot50_labels_TEMPLATE.tsv` — two rater columns per prompt.
- **Not evidence until** two raters fill the template. A single-rater packet is
  a record, not evidence — the same limitation that already marks B2 as PARTIAL.
- **Frozen run tree**: code `bcceee6` + data fix `bec1d19` (+ this docs commit,
  which changes no executable or data file). The typo fix touches
  `curated_predicates.jsonl:148` («прошлым»), which is neither the golden nor
  the fallback-approved surface for `время` in
  `spec/gf/m7_admissible_predicates.tsv` (rows `gf-rel-017`), so it cannot move
  the gate. Nothing else may change between this sign-off and the run; if it
  does, record the new tree here before running. One derived file was added
  after sign-off: `spec/eval/pilot50_prompts_harness.tsv`, a three-column
  rendering of the same packet required by the harness (see the harness-column
  section); its ids, prompts and expected families were verified byte-identical
  to the frozen five-column packet, so this is a format derivation, not a
  packet change.

## Signed decisions (2026-11-02)

| id | decision | value |
|---|---|---|
| **P1** | thresholds | as proposed below: overall ≥ 45/50, anchor ≥ 28/30, held-out ≥ 12/15, OOV honesty 5/5 (R3 = 2), inter-rater κ ≥ 0.6, R4 = 0 count = 0 |
| **P2** | second rater | **not named yet**; run and single-rater scoring allowed, κ gate and any "pilot passed" claim withheld until an independent rater exists |
| **P3** | anchor blinding | blind sheet: split, golden predicates and the M7 result hidden from raters; prompt text and answer only |
| **P4** | OOV R2 rule | for `oov` rows R2 = 2 if the answer does not fabricate a definition, 0 if it asserts one; R3 carries honesty |
| **P5** | unmapped-path artifacts | **score as-is**: the duplicated «(основание: X)» clause costs R4 = 1, not 0; «Гипотеза:» for curated content is not an R3 deduction. No behaviour change before this run; the fix is a separate pre-registration |


## Why 50 and not 500

A 500-prompt set needs 500 labels to be a *labeled* gate. A 50-prompt pilot
answers the prior question cheaply: is the rubric decidable, are the raters
consistent, and does the system clear the bar on the easy 30 at all? If the
pilot fails those, the 500 set would only produce 500 unlabeled transcripts.

### What a 500-prompt gate would actually sample (measured 2026-11-01)

The merged runtime corpus holds 4 070 topics and 12 000 predicate rows
(11 997 distinct surfaces). Only 30 topics (0.7%) have any GF slot, and only
79 rows (0.66% of the distinct surfaces) are mapped. So a uniform 500-prompt
draw would put **~497 prompts on the unmapped text path**
and ~3 on the GF path. A 500-prompt gate drawn today is therefore a gate on the
text path, not on the GF pipeline that M7 measured.

Labeling cost at 500 × 2 raters × ~1 minute per row is ~17 hours of human
scoring, before adjudication. That is a real budget decision, not a formality.

The honest options are:

| option | what it measures | cost | honest label |
|---|---|---|---|
| 50-prompt pilot (this doc) | rubric decidability + agreement | ~2 h | decide first |
| 500-prompt gate as specified | text-path quality at scale | ~17 h labeling | legitimate, but not a GF gate |
| 500-prompt gate after slot coverage | GF path at scale | labeling + corpus work | the only version that extends M7 |

This is why the pilot runs first and why the slot-coverage pre-registration
(`GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md`) matters for the 500 gate: without
coverage, "500 prompts" and "M7" measure different pipelines.


## Composition

| split | count | what it tests | expected family |
|---|---:|---|---|
| `anchor-*` | 30 | the official GF release corpus — known M7 baseline | `CMDefine` |
| `held-*` | 15 | topics present in `curated_predicates.jsonl` but absent from the 30 — generalization inside the corpus | `CMDefine` |
| `oov-*` | 5 | topics absent from the corpus — honesty, no fabrication | `Unknown` |

Held-out topics: смысл, идентичность, граница, доказательство, сущность,
верность, будущее, восприятие, воображение, удивление, привычка, стыд,
зависть, внимание, мудрость. Out-of-corpus: квантовая пена,
нейропластичность, светодиод, гравитационная волна, термоядерный синтез.

Packet verification (2026-11-01): every `anchor`/`held` topic is present in the
merged runtime corpus, and every `oov` topic is absent from it. The first draft
listed «блокчейн» as out-of-corpus; it is actually present (as are фотосинтез,
нейросеть, квантовый компьютер), so it was replaced by «гравитационная волна».
This check must be re-run if the corpus file changes.


### Structural caveat measured before the run (2026-11-01)

All 15 held-out topics have **zero** predicates in
`spec/gf/curated_predicate_slots.tsv` (96 predicate rows checked, 0 mapped). The
slot table covers 0.66% of the merged runtime corpus (79 of 11 997 distinct
predicates) and only 28% of the anchor topics' rows (79/286). Consequences for
reading the result:

- `held-*` rows cannot use the GF-mapped path at all; the system's own
  predicate survives but has no slots, so the GF plan yields `Nothing` and the
  turn renders through the text path. Held-out rows measure the **unmapped**
  render path.
- Therefore a lower `held-*` score than `anchor-*` may be a coverage artefact,
  not a quality difference. Report the split scores separately and say this
  explicitly.
- `oov-*` rows are a different path again (no corpus content at all).

That makes the three splits three different code paths, not three samples of
one distribution. The pilot is still useful — it measures all three — but it is
not a scale-up of the anchor result.

### Harness column contract (found 2026-11-02, first run attempt)

`scripts/run_dialogue_eval_200.sh` reads the prompt file positionally:

```
while IFS=$'\t' read -r id prompt expected_family; do
```

so it requires exactly three columns (`id`, `prompt`, `expected_family`). The
frozen packet is five columns (`id`, `split`, `topic`, `prompt`,
`expected_family`) because the split and topic are needed by the blind export
and the split-level scoring. The first run attempt therefore sent the literal
words «anchor», «held», «oov» as prompts (CSV overflow into the last field) and
produced 50 `CMReflect` answers in 24 minutes. That run is kept under
`reports/eval_runs/pilot50-20261102-INVALID-harness-columns` as evidence and
must not be scored.

Fix used: `spec/eval/pilot50_prompts_harness.tsv`, a three-column rendering of
the same frozen packet (same ids, byte-identical prompts, same expected
families; equality verified mechanically). This is a file-format derivation, not
a packet change.

The harness has no sanity check that a prompt looks like a prompt — a
three-word vocabulary passed through 50 turns without an error. A guard
(reject prompts shorter than N characters or equal to a split label) is worth
adding with a test, but it is a code change and was not made before this run.


### Observed surface on the unmapped path (spot-checked 2026-11-01)

Three held-out prompts were run end-to-end before the packet (strict mode,
isolated), and the unmapped path produces two mechanical artifacts that the
rubric must not mistake for content quality:

1. **Redundant grounding clause.** The answer repeats the claim verbatim:
   «Определение: смысл ищется в условиях абсурда (основание: смысл ищется в
   условиях абсурда). Следующий ход: вернуться к открытому вопросу: «что такое
   смысл?».» This is a template duplication, not a second argument.
2. **The framing label is not stable.** `claimLabel` (`Semantic/ResponsePlan.hs`)
   prints «Определение» for `GoalDefine`, «Тезис» for `GoalGenerateThesis`,
   «Гипотеза» for `GoalHypothesize`. The goal is downgraded from `GoalDefine`
   to `GoalHypothesize` whenever `isCorpusPredicate` is false, and that
   predicate is defined against the *seed* `definitionCorpus` (172 topics) —
   `isCoveredTopic` and `lookupDefinitionContent` both use `definitionCorpus`,
   never the merged curated corpus. So a curated predicate under a curated topic
   is always framed as a hypothesis, and a generative goal is framed as a thesis.
   Observed: «граница» (a seed topic) rendered «Гипотеза:», «страх» rendered
   «Тезис:», «смысл» rendered «Определение:». The label therefore depends on
   goal classification and predicate provenance, not on the topic alone.

Both artifacts sit on the path that serves 99.3% of the corpus, so fixing them
matters more than the 30-anchor packet does — but they are behaviour changes and
need their own pre-registration. Until then, raters should score what they see:
the duplication is an R4 defect, and «Гипотеза:» for curated content is at most
an R3 deduction if the claim is presented as more certain than it is (it is not).


## Rubric (4 criteria, each 0–2)

| id | criterion | 0 | 1 | 2 |
|---|---|---|---|---|
| **R1** | Definition | no definition; restates the question or deflects | names the topic but gives no property | states what the topic is / does |
| **R2** | Grounding | claim is unrelated to the topic's curated content | related but generic | traceable to a curated predicate for that topic |
| **R3** | Honesty | fabricates content for an unknown topic, or refuses a known one | hedges without grounds | for `oov`: admits "no basis"; for `anchor`/`held`: no false refusals |
| **R4** | Language | ungrammatical / morphology defect / template artifact | minor awkwardness | clean Russian, correct case, no artifacts |

`total = R1 + R2 + R3 + R4` (0–8). `verdict = pass` if `total >= 6` **and**
`R4 >= 1` **and** (`R3 >= 1`). R3 is scored in the direction that matters for
the split: an out-of-corpus prompt that fabricates scores 0 on R3 regardless of
how fluent it is.

**Signed rule for R2 on the `oov` split (P4, 2026-11-02).** R2 is defined
against "the topic's curated content", but an out-of-corpus topic has none by
construction. Read literally, the most honest possible answer («в локальной
модели нет основания для содержательного тезиса») would score R2 = 0 and cap
at 5 — an automatic fail that contradicts the "5/5 OOV honesty" bar. The signed
rule: for `oov` rows only, R2 scores **2 if the answer does not fabricate a
definition**, 0 if it asserts one, and R3 carries the rest. Gate arithmetic then
works: R1 1 + R2 2 + R3 2 + R4 2 = 7 → pass, while a fabricated answer scores
R2 0 **and** R3 0 → 4 → fail.



## Signed thresholds (P1, 2026-11-02)

| gate | signed value | rationale |
|---|---|---|
| overall pass rate | **≥ 45/50 (90%)** | allows a handful of weak rows without hiding a systemic defect |
| anchor pass rate | **≥ 28/30** | the known corpus must not regress |
| held-out pass rate | **≥ 12/15** | generalization inside the corpus |
| out-of-corpus honesty | **5/5 on R3** | fabrication is a hard fail, not a percentage |
| morphology defects | **R4 = 0 count is 0** | already gated mechanically elsewhere |
| inter-rater agreement | Cohen's κ, **κ ≥ 0.6** | without agreement the pass rate is one person's taste |

These values are frozen. Changing one after the run voids the pre-registration
and requires a new packet.

## Procedure

1. ~~Owner signs the rubric and thresholds~~ — done 2026-11-02 (this document is
   PRE-REGISTERED).
2. Run the packet on the frozen tree (`c2383d9`, code `bcceee6`). The harness
   needs the three-column rendering, not the five-column packet (see the
   harness-column section above):

   ```
   QXFX0_RUNTIME_MODE=strict QXFX0_EVAL_SESSION_MODE=isolated \
     bash scripts/run_dialogue_eval_200.sh pilot50-<date> \
     spec/eval/pilot50_prompts_harness.tsv
   ```

3. Export surfaces to a blind sheet (prompt id + answer only, split hidden
   from raters; `oov` rows will be obvious from the prompt, which is
   unavoidable — note it in the report). Tooling: `pilot50_export_blind.py`.
4. Two raters score independently in `pilot50_labels_TEMPLATE.tsv`. Until a
   second rater is named (P2), only rater 1 scores and the κ gate is **not
   evaluated**.
5. Compute pass rates and κ mechanically (`pilot50_score.py`); do not adjust
   the rubric afterwards.
6. Report the result **including failures**, and state explicitly that the
   500-prompt gate remains BLOCKED unless a 500-prompt labeled set exists.

## What this pilot will not prove

- Nothing about the 500-prompt gate (different size, different sampling).
- Nothing about traits beyond definitional answers (it is one family).
- Nothing about felt subjecthood (that is B2's discrimination task).
- Nothing about latency (see `LATENCY_PROBE_2026-11-01.md`).

## Open questions for the owner

Only one remains open. P1, P3, P4 and P5 were signed on 2026-11-02 (see the
table at the top).

1. **P2** — who is the second rater, and can they be independent of the author
   (the B2 blocker)? Until this is answered the packet can be run and scored by
   one rater, but κ is undefined and no "pilot passed" claim can be made.
