# GF slot batch, group 1 — measurement result (2026-11-08)

- **Status**: **measured, not landed.** The batch lives in the working tree
  over HEAD `3f6c3da` and is uncommitted.
- **Scope measured**: group 1 only — 123 rows appended to
  `spec/gf/curated_predicate_slots.tsv` (207 data rows total), the duplicate
  object id `otsutstvie_ogranichenij` unified to `otsutstvie_ogranicheniy`,
  three regenerated files (`QxFx0Syntax.gf`, `QxFx0SyntaxRus.gf`,
  `SemanticSlots.hs`), GF recompiled (`QxFx0Syntax.pgf` + manifest), test pin
  `84` → `207`, new generator `scripts/add_gf_slot_rows.py`.
- **Not in scope**: group 2 (102 rows, new relations required).
- **Runs**: `reports/eval_runs/m7-gf-batch-20261108a` and `…b`, strict /
  isolated, 30-prompt packet, same harness and checker as
  `m7-gf-confirm-20261031`.
- **Packet**: the original `/tmp/opencode/m7-gf-case-30.tsv` was lost with the
  temp dir. The packet was reconstructed verbatim from
  `reports/eval_runs/m7-gf-confirm-20261031/results.jsonl`
  (`id`, `prompt`, `expected_family`; all 30 rows `CMDefine`) and frozen as
  `spec/gf/m7_gf_case_30.tsv` (sha256
  `d1a6615476b40e481674813175c3359c78603d532e1f48f99f339c1fb662d9cb`).
  `scripts/eval/check_prompt_file.py` accepts it.
- **Admissible set**: the runs were judged with the **frozen 2026-10-28 set**
  (`spec/gf/m7_admissible_predicates.tsv`, sha256 `ef75231d…033766`), exactly
  as pre-registered. S2 anticipates a **new** set because emitted predicates
  change; this document reports the candidate additions, it does not sign them.

## Bars (S2, signed 2026-11-06)

| # | bar | measured | verdict |
|---|---|---|---|
| 1 | gate pass 30/30 | structural **30/30**; semantic **26/30** after the 2026-11-08 amendment (9 of 13 candidates signed; 4 group-2 substitutes deferred) | **FAIL** |
| 2 | `gf_mapped_fallback` ≤ 2 | **5/30** (was 14/30) | **FAIL** |
| 3 | emitted = system's own selection ≥ 28/30 | **25/30** | **FAIL** |
| 4 | new rows failing the 4-point check = 0 | **207/207, 0 failures** (constructors, generated Haskell, GF round-trip, corpus identity against a 12 325-line runtime dump) | **PASS** |
| 5 | determinism, two runs | **0/30** predicate mismatches, **0/30** surface mismatches | **PASS** |
| 6 | full test matrix on the landing tree | not run yet | **PENDING** |
| 7 | no new `drift`/`weak` row vs the 14-row verdicts | 13 changed turns; 2 look weaker (020, 025); owner review needed | **PENDING** |

Notes:

- Bars 2 and 3 are two views of the same substitution: a turn can emit the
  system's own predicate only if that predicate has slots. Both moved together
  (14 → 5), as expected.
- Bar 1's semantic failures are **not** regressions of the old gate: the old
  set froze the 2026-10-31 emitted predicates, and 13 of those are now
  different. The owner signed 9 own-selection additions on 2026-11-08; the
  4 substitute rows (013, 017, 020, 025) stay unsigned until group 2 removes
  the substitution. The amended set is
  `spec/gf/m7_admissible_predicates.tsv` (54 rows, sha256
  `aa606938…b2add0`); `scripts/m7_gate_check.py` accepts the two signed
  dates.
- Exact-surface match is informational only (D4): 4/30 (was 5/30).

## Why bars 2/3 stop at 25/30

All 5 remaining fallbacks are group-2 rows — their selected predicates need
relations that do not exist in the slot table yet:

| id | topic | emitted (substitute) | system's own selection (discarded) |
|---|---|---|---|
| gf-rel-013 | доверие | доверие требует уязвимости | доверие открывает возможность сотрудничества |
| gf-rel-017 | время | время выражает последовательность становления | время устанавливает границы между прошлым и будущим |
| gf-rel-020 | история | история сохраняет память о прошлом | история складывается из событий и их интерпретации |
| gf-rel-024 | одиночество | одиночество выражает отсутствие значимого другого | одиночество обнаруживает границу между я и другими |
| gf-rel-025 | любовь | любовь это глубокое чувство привязанности | любовь преодолевает границу между я и другим |

Group 1 cannot close bars 2/3. Group 2 (102 rows, new relations) is the only
signed path to ≥28/30.

## The 13 changed turns (bar 7 input)

| id | topic | old emitted (2026-10-31) | new emitted | own selection now? |
|---|---|---|---|---|
| gf-rel-007 | воспоминание | воспоминание есть акт обращения к личному прошлому | воспоминание восстанавливает прошлое в настоящем | yes |
| gf-rel-008 | сознание | сознание объединяет восприятие и рефлексию | сознание есть основание субъектности | yes |
| gf-rel-013 | доверие | доверие предполагает уязвимость перед другим | доверие требует уязвимости | no (group 2) |
| gf-rel-016 | справедливость | справедливость требует соразмерности между деянием и воздаянием | справедливость требует равенства возможностей | yes |
| gf-rel-017 | время | время задаёт порядок следования событий | время выражает последовательность становления | no (group 2) |
| gf-rel-020 | история | история связывает прошлое с настоящим через интерпретацию | история сохраняет память о прошлом | no (group 2) |
| gf-rel-021 | язык | язык структурирует опыт через различение и именование | язык выражает и структурирует мысль | yes |
| gf-rel-023 | смерть | смерть обозначает необратимое прекращение существования | смерть выражает конечность бытия | yes |
| gf-rel-025 | любовь | любовь направлена на конкретного другого как на безусловно ценного | любовь это глубокое чувство привязанности | no (group 2) |
| gf-rel-026 | труд | труд преобразует материал через целенаправленное усилие | труд выражает целенаправленное усилие | yes |
| gf-rel-027 | покой | покой обозначает отсутствие движения и напряжения | покой выражает отсутствие напряжения | yes |
| gf-rel-028 | власть | власть требует легитимности для устойчивости | власть это способность и возможность влиять на поведение людей | yes |
| gf-rel-030 | молчание | молчание может быть актом отказа или знаком присутствия | молчание выражает позицию через отсутствие слов | yes |

Reading:

- **9 turns** (007, 008, 016, 021, 023, 026, 027, 028, 030) now emit the
  system's own selection. Two of them repair the two rows the 2026-11-01
  review flagged: 021 restores the link to thinking (was `drift (aspect)`),
  028 defines power as the ability to influence (was `weak`).
- **4 turns** (013, 017, 020, 025) still fall back, but the *substitute*
  changed because the mapped candidate set grew. Two of them look like
  regressions against the 2026-11-01 verdicts: 020 and 025 previously emitted
  the golden predicate (`harmless (equals golden)`), now emit a narrower
  substitute. 013 and 017 are lateral rewrites.
- The batch therefore **does not** satisfy bar 7 as it stands: it needs an
  owner content review of the 13 rows, and the 020/025 regressions are a
  real finding, not a wording preference.

## Candidate admissible-set additions (13)

Owner decision 2026-11-08: **9 own-selection rows signed** (new set sha256
`aa606938…b2add0`, 54 rows); the **4 substitute rows deferred** until group 2
removes the substitution. These are the emitted predicates the gate rejects
against the 2026-10-28 set:

| id | topic | candidate predicate | provenance proposal | signed |
|---|---|---|---|---|
| gf-rel-007 | воспоминание | воспоминание восстанавливает прошлое в настоящем | curated-approved | **yes** |
| gf-rel-008 | сознание | сознание есть основание субъектности | curated-approved | **yes** |
| gf-rel-013 | доверие | доверие требует уязвимости | fallback-approved | deferred |
| gf-rel-016 | справедливость | справедливость требует равенства возможностей | curated-approved | **yes** |
| gf-rel-017 | время | время выражает последовательность становления | fallback-approved | deferred |
| gf-rel-020 | история | история сохраняет память о прошлом | fallback-approved | deferred |
| gf-rel-021 | язык | язык выражает и структурирует мысль | curated-approved | **yes** |
| gf-rel-023 | смерть | смерть выражает конечность бытия | curated-approved | **yes** |
| gf-rel-025 | любовь | любовь это глубокое чувство привязанности | fallback-approved | deferred |
| gf-rel-026 | труд | труд выражает целенаправленное усилие | curated-approved | **yes** |
| gf-rel-027 | покой | покой выражает отсутствие напряжения | curated-approved | **yes** |
| gf-rel-028 | власть | власть это способность и возможность влиять на поведение людей | curated-approved | **yes** |
| gf-rel-030 | молчание | молчание выражает позицию через отсутствие слов | curated-approved | **yes** |

## What this establishes

- Group 1 is **mechanically realizable and deterministic**: 207/207 on the
  4-point rule, identical surfaces and predicates across two runs.
- It cuts GF-mapped fallback from 14/30 to 5/30 and restores the system's own
  predicate on 9 turns, including the two flagged in the 2026-11-01 review.
- It **does not** close S2: bars 2/3 need group 2, bar 1 needs a new
  admissible set, bar 7 needs the owner's content review, bar 6 needs the
  matrix.

## Owner decisions (2026-11-08)

1. **Landing shape**: commit group 1 as a measured coverage increment, with
   bars 2/3 honestly recorded as open. Group 2 is a separate landing.
2. **Admissible set**: sign the 9 own-selection rows; defer the 4 group-2
   substitutes. Gate on this tree is **26/30**, not 30/30.
3. **Bar 7**: the 13-row content review is recorded above; 020/025 are
   flagged as regressions and are expected to disappear with group 2. Bar 7
   itself remains **PENDING** — this is not a content sign-off.
4. **Bar 6**: run the full matrix on the landing tree (≈5 h 46 min).

## Remaining open items

- Bars 2/3: need group 2 (102 rows, new relations).
- Bar 1: needs group 2 plus the 4 deferred admissible rows.
- Bar 6: matrix on the committed tree.
- Bar 7: owner content sign-off on the 13 rows (020/025 are the open
  question).

## Artifacts

- `reports/eval_runs/m7-gf-batch-20261108a/` — results, summary, raw logs,
  `gate-check.txt` (exit 1, 26/30 semantic), `slot-realizability.txt`
  (4/4 points PASS, 207 rows).
- `reports/eval_runs/m7-gf-batch-20261108b/` — determinism replica, same gate
  output.
- `spec/gf/m7_gf_case_30.tsv` — reconstructed packet.
- `spec/gf/gf_slot_gap_2026-11-06.tsv` — frozen 225-row gap (group 1 = 123,
  group 2 = 102).
