# Multiword topic span fix (`oov-005`) — result (2026-11-05)

- **Status**: **complete and green** — all pre-registered bars measured, the
  full matrix green, both post-fix replays done; landed 2026-11-06. Every
  number below is measured; nothing is inferred from an unrun gate.
- **Pre-registration**: `docs/closure/OOV_TOPIC_SPAN_PREREG_2026-11-03.md`,
  signed 2026-11-04 (D-1 … D-5 **as written**).
- **Landing unit**: D-1 + D-2 + D-4 in **one** commit (D-5), plus tests and
  documentation. No corpus edit, no slot row, no GF artifact, no DB migration.
- **Scope honesty**: this closes the `oov-005` substitution defect class named
  in the pre-registration. It says nothing about M6-FELT, M7 beyond the bounded
  30-prompt packet, the 500-prompt gate (still **BLOCKED**: no labelled
  Russian corpus) or release readiness.

## 1. What changed

| area | file | change |
|---|---|---|
| D-1 | `src/QxFx0/Semantic/Intent/Classifier.hs` | `canonicalTopic`: a multi-token topic is returned verbatim (whitespace-normalized); the single-token branch is byte-identical to the old rule |
| D-2 | `src/QxFx0/Semantic/ResponsePlan.hs` | `clauseShaped = (>= 3) . length . T.words`, applied **at the `buildGroundedPlan` call site**; `refineUncoveredTopic` itself untouched |
| D-4 | `src/QxFx0/Types/TurnProjection.hs`, `Route/Render.hs`, `Finalize/Projection.hs` | nullable sub-record `trcTopicResolution` (`trtIntentTopic`, `trtPlanTopic`, `trtResolution`) derived from `topic_span=` / `plan_topic=` / `topic_resolution=` tags |
| tests | `test/Test/Suite/TopicSpan.hs` (new), `IntentClassifier`, `ResponsePlan`, `ReplayDeterminism` | B1/B2/B3 corpus pins, span-shape pins, clause-gate pins, populated sub-record round-trip |
| docs | `docs/closure/TRACE_SCHEMA.md` §13, pre-registration §2 amendments | trace disclosure contract; measured corrections |

## 2. Bars (pre-registered, not tunable)

| bar | required | measured | verdict |
|---|---|---|---|
| **B1** | all 624 multiword merged keys are `canonicalTopic` fixpoints | 624/624 (0 failures) | **PASS** |
| **B2** | the 16 previously preserved spans stay byte-identical | 16/16 | **PASS** |
| **B3** | all 3 446 single-word keys canonicalize byte-identically | 3 446/3 446 | **PASS** |
| **B4** | the four OOV probes make no claim about their head noun | D-1 only: **2/4** (red, both seed-head); D-1+D-2: **0/4** (green) | **PASS** |
| **B5** | «в чём смысл моей жизни» still resolves to «смысл» | function pin green; runtime prompt takes the clarify path (`trcTopicResolution = null`), so neither changed function is on its path | **PASS** (structural) |
| **B6** | 45/45 pilot50 non-OOV surfaces byte-identical; 30/30 GF release surfaces byte-identical | GF **30/30**; pilot50 **45/45** non-OOV (49/50 overall; the one change is the expected `oov-005` abstention) | **PASS** |
| **B7** | multiword keys that become unreachable | 0 (B1 makes every key its own preimage; lowercase forms are members) | **PASS** |
| **B8** | test matrix per group, no new failures | unit 1 828, fast 1 921, property 244, integration 47, main runtime 106 + http 23, slow runtime 106 + state 50 + http 23 + lifecycle 11 — **all exit 0** | **PASS** |

Population re-counted on the landing tree (pre-registration §6 requires this to
be reported): `definitionCorpus` 172 keys, curated overlay 4 036 keys, merged
**4 070** (138 shared), of which **624** multiword and **3 446** single-word.
Counts equal the signing-time numbers.

### B1/B2/B3 evidence

`/tmp/opencode/counts.hs` (compiled against the working tree) prints the
population and `B1 failures (new): 0`. The same properties are pinned
permanently in `Test.Suite.TopicSpan` (three cases, registered in the unit and
fast suites).

### B4 red check (D-1 only) and green check (D-1+D-2)

Harness `/tmp/opencode/b4probe.py`: one fresh strict session per prompt against
a throwaway DB, claim extracted from the surface (prefix strip, cut at
`Следующий ход:` / `Контрпункт:` / `Проверка:` / `(основание`), compared with
the bare head noun's claim.

- **Red (D-1 only)**: `clauseShaped` forced to `const True` in a temporary
  working-tree build (file restored byte-identically afterwards, sha256
  `6efe9c6b…`) — **2/4 violations**, exactly as pre-registered:
  «цифровая свобода» → `Тезис: свобода предполагает возможность выбора.`,
  «коллективная память» → `Тезис: память сохраняет прошлое для настоящего.`
  «термоядерный синтез» and «гравитационная волна» abstain.
  Artifact: `/tmp/opencode/b4run-d1only/summary.json`.
- **Green (D-1+D-2)**: `/tmp/opencode/b4run-d1d2/summary.json` — **0/4**, all
  four compounds abstain (`uncovered_generic`), each head noun still answers
  its own claim.

## 3. D-4 disclosure (runtime, measured)

`/tmp/opencode/d4probe.py` and `/tmp/opencode/d4refined.py` read
`trcTopicResolution` from the persisted `replay_trace_json` envelope
(`turn_quality`):

| prompt | `trtIntentTopic` | `trtPlanTopic` | `trtResolution` | surface |
|---|---|---|---|---|
| что такое смысл жизни? | смысл жизни | смысл жизни | `exact` | «Гипотеза: смысл жизни это цель существования…» |
| что такое цифровая свобода? | цифровая свобода | — | `fallback` | abstain |
| что такое свобода воли? | свобода воли | — | `fallback` | abstain |
| что такое смысл человеческой жизни? | смысл человеческой жизни | смысл | `refined` | «Определение: смысл ищется в условиях абсурда…» |
| что такое свобода? | свобода | свобода | `exact` | «Тезис: свобода предполагает возможность выбора…» |
| в чём смысл моей жизни | — | — | `null` | clarify path, no semantic-first artifact |

The `refined` row is the pre-registered residual (§3): a 3+-token span whose
first covered token is a seed topic still refines. It is shown here because the
disclosure must make it visible, not because it is desired.

## 4. Measured costs the pre-registration did not fully name

1. **Inflected multiword queries** — predicted as answer→abstain; measured as
   **not materialising** for «о смысле жизни» because the compositional
   classifier already returns `IntentDefine "смысл"` before canonicalization
   (pre-registration §2 amendment, 2026-11-05).
2. **Capitalised multiword spans** — **new, measured**: the loader lowercases
   every corpus key (`normalizeTopic = T.toLower . T.strip`), so the merged
   population has **0** mixed-case keys; the pre-registration's case rationale
   was inverted. Preserving case makes «Что такое Смысл жизни?» abstain
   (`trtResolution = fallback`) while the lowercase surface answers. The three
   mixed-case JSONL rows («Raspberry Pi», «Spring Boot», «Standing ovation»)
   are reachable only in lowercase — which D-1 newly enables; the old rule
   truncated them to a first noun that was not a key. Recorded in the
   pre-registration §2 amendment; the signed rule is unchanged.
3. **Any OOV 2-token span with a covered head** now abstains instead of
   answering about the head — this is the intended D-2 gate. Measured instance
   beyond the four B4 probes: «что такое свобода воли?» → `fallback` (the old
   rule answered about «свобода»). Same accepted class, not a new decision.

## 5. Test matrix (B8)

Sequential, per group, as in `TEST_MATRIX_2026-11-01.md`. Full single-process
`qxfx0-test` remains unsupported on 15 GB with the substrate active.

| suite / group | cases | result | log |
|---|---:|---|---|
| `qxfx0-test-unit` | 1 828 | **green** (exit 0) | `/tmp/opencode/matrix-unit-final.log` |
| `qxfx0-test-fast` | 1 921 | **green** (exit 0) | `/tmp/opencode/matrix-fast.log` |
| `qxfx0-test-property` | 244 | **green** (exit 0) | `/tmp/opencode/matrix-property.log` |
| `qxfx0-test-integration` | 47 | **green** (exit 0) | `/tmp/opencode/matrix-integration.log` |
| `qxfx0-test` — `runtime` | 106 | **green** (exit 0) | `/tmp/opencode/matrix-runtime.log` |
| `qxfx0-test` — `http` | 23 | **green** (exit 0) | `/tmp/opencode/matrix-http.log` |
| slow — `runtime` | 106 | **green** (exit 0) | `/tmp/opencode/slow-runtime.log` |
| slow — `state` | 50 | **green** (exit 0) | `/tmp/opencode/slow-state.log` |
| slow — `http` | 23 | **green** (exit 0) | `/tmp/opencode/slow-http.log` |
| slow — `lifecycle` | 11 | **green** (exit 0) | `/tmp/opencode/slow-lifecycle.log` |

The fast row was produced **before** two test-only corrections landed (the
mixed-case rationale in `TopicSpan` and an assertion label in
`IntentClassifier`). After the rebuild, the full unit suite re-ran green
(1 828) and `TopicSpan` re-ran green in the fast binary
(`QXFX0_FAST_SUITE=topicspan`, 3/3). No library or executable source changed
between the two fast runs.

One comment-only correction landed after the matrix: the `canonicalTopic`
Haddock still repeated the pre-registration's inverted mixed-case rationale and
now states the measured fact instead. The library was rebuilt and the full unit
suite re-ran green on that exact tree (1 828/1 828, exit 0,
`/tmp/opencode/matrix-unit-final.log`); no executable semantics changed.

Log paths in the table are ephemeral (`/tmp` is wiped by this environment — see
§8); the case counts and exit codes above are the measured values.

New cases in this change: `TopicSpan` 3 (unit + fast), `IntentClassifier` 2
(unit), `ResponsePlan` 2 (unit); the `ReplayDeterminism` P5 case gained two
`Just`-valued round-trip assertions without changing its count.

## 6. Post-fix replay (B6)

Two frozen packets were replayed on the landing tree (strict runtime, isolated
session per row, default DB path — the same environment as the baselines).

### 6.1 M7 GF release packet — 30/30 byte-identical

| item | value |
|---|---|
| packet | `/tmp/opencode/m7-gf-case-30.tsv`, regenerated mechanically from `spec/gf/release_corpus_prompts.txt` (`gf-rel-NNN`, prompt, `CMDefine`); ids and prompts verified identical to the baseline run programmatically |
| baseline | `reports/eval_runs/m7-gf-confirm-20261031` |
| after | `reports/eval_runs/m7-gf-span-20261105` |
| surfaces | **30/30 identical**, 0 unexpected changes (`/tmp/opencode/surface_compare.py`) |
| counters | `authority_canonical 30/30`, `trace_available 30/30`, `intent_fit 30/30`, `fallback_drift 0`, `critical_mismatch 0`, `morphology_defect 0`, `runtime_or_parse_error 0`, `gf_mapped_fallback_count 14` (same as baseline) |
| gate | `python3 scripts/m7_gate_check.py reports/eval_runs/m7-gf-span-20261105` → **GATE PASSED**, 30/30, 5/30 exact-surface matches (informational) |

All 30 prompts are single-token topics, so D-1/D-2 cannot touch them by
construction; the byte comparison confirms it rather than assuming it.

### 6.2 pilot50 packet — 45/45 non-OOV byte-identical, one expected OOV change

| item | value |
|---|---|
| packet | `spec/eval/pilot50_prompts_harness.tsv` (frozen 3-column rendering) |
| baseline | `reports/eval_runs/pilot50-20261102b` |
| after | `reports/eval_runs/pilot50-20261105-after` |
| surfaces | **49/50 identical**; the only change is `oov-005`, i.e. **45/45 non-OOV identical** and **0 unexpected changes** (`/tmp/opencode/surface_compare.py --expect-change oov-005`) |
| counters | identical to the baseline: `intent_fit 45`, `fallback_drift 20`, `gf_mapped_fallback 14`, `critical_mismatch 5`, `morphology_defect 0`, `runtime_or_parse_error 0`, `trace_available 50`, `authority_canonical 30`, `authority_shim 20` |

The one changed row is the defect being fixed:

```
oov-005  «что такое термоядерный синтез?»
before: Гипотеза: синтез объединяет части в целое (основание: синтез объединяет
        части в целое). Следующий ход: вернуться к открытому вопросу: …
after : Я вижу тему, но в локальной модели нет достаточного основания для
        содержательного тезиса. Могу предложить только явно отмеченную
        гипотезу после уточнения рамки.
```

`oov-004` («гравитационная волна») was already an abstention in the baseline and
is byte-identical after the fix, so the gate changes exactly one measured
surface. As pre-registered, the **reporting** bars (`trcContentSource`
distribution etc.) are not compared before/after: after the fix a large number
of turns move from `uncovered_generic` to `covered_*`, so such a comparison
would be inadmissible (pre-registration §6). The counters above are reported
only to show that no harness-level rate moved, not as evidence of improvement.
The pilot50 baseline remains a one-rater record; this replay does **not** turn
it into a passed pilot, and the 500-prompt gate stays BLOCKED.

## 7. Rollback

`git revert` of the landing commit restores the exact pre-change behaviour.
The trace field is nullable and JSON-backward-compatible, so old traces stay
readable and new ones merely go unpopulated. No persisted state, DB schema,
corpus file or GF artifact is touched.

## 8. Evidence index (local, gitignored, reproducible)

**Durability caveat (measured twice).** This environment wipes `/tmp/opencode`
(observed 2026-11-03 and again 2026-11-06). The paths below are the harness
locations used for the measurements in this document; they are **not durable**
and some were already gone when this commit was prepared. The durable evidence
is (a) the committed test suites that pin the bars permanently
(`Test.Suite.TopicSpan`, `IntentClassifier`, `ResponsePlan`,
`ReplayDeterminism`) and (b) the eval run directories under
`reports/eval_runs/` (gitignored by project convention). Every harness is
reproducible from the recipe in the section that cites it; the recipes are
deliberately short (a `canonicalTopic`/`legacyCanonical` probe, a CLI-turn
probe reading `turn_quality.replay_trace_json`, and a last-JSON-line surface
comparator).

- `/tmp/opencode/counts.hs` — population counts + B1/B2/B3 over the merged
  corpus (recipe: `mergeCuratedIntoDefinitionCorpus` + the pre-change
  first-content-noun oracle).
- `/tmp/opencode/b4probe.py` — B4 red/green harness (recipe: one fresh strict
  session per prompt against a throwaway `QXFX0_DB`, claim extraction, compare
  with the bare head noun).
- `/tmp/opencode/d4probe.py`, `/tmp/opencode/d4refined.py` — D-4 runtime probes
  (recipe: run a turn, then read `turn_quality.replay_trace_json` for the
  session and decode the `trace` envelope).
- `/tmp/opencode/caseprobe2.hs`, `/tmp/opencode/case_runtime.py` — case finding.
- `/tmp/opencode/surface_compare.py` — B6 surface comparison (generic; last
  JSON object carrying `response`/`surface` per raw log).
- `/tmp/opencode/m7-gf-case-30.tsv` — M7 packet regenerated mechanically from
  `spec/gf/release_corpus_prompts.txt`; ids and prompts verified identical to
  `m7-gf-confirm-20261031` programmatically before the replay.

