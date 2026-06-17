# B2-EXEC-001 — Evaluation Packet

- **Status**: Packet defined, not yet generated (requires intended env).
- **Date**: 2026-06-17
- **Front**: B2-EXEC-001 (packet/harness) → B2-EXEC-002 (rating run)
- **M6-FELT**: **NOT PROVEN** — remains so until human results exist.
- **B3 precondition**: PASS (conjunction Gates 1-5, commit `d2e0182`)

## Purpose

A reproducible evaluation packet for blind paired discrimination
(B2 protocol, `docs/closure/B2_HUMAN_EVAL_PROTOCOL.md`). This packet
is the /harness/ — the corpus, control configuration, rubric, and
generation script. The actual human rating run is B2-EXEC-002, a
separate step.

## Packet contents

| File | Purpose | Shared with raters? |
|---|---|---|
| `test/fixtures/b2-eval/corpus.jsonl` | Fixed scripted user turns (23 turns, 10 tasks: 5 definition + 5 distinction, each with challenge turns) | ❌ no (raters see transcripts only) |
| `test/fixtures/b2-eval/control-a-config.json` | Control-A definition: what is disabled, what is preserved, fluency-matching rationale | ❌ no |
| `test/fixtures/b2-eval/rubric-form.md` | Rating form: D1 (semantic depth), D3 (repair), D5 (identity continuity), D6 (non-fallback), forced-choice + reason + overall preference | ✅ yes (this IS the rating form) |
| `test/fixtures/b2-eval/pre-registration.md` | Locked fail/pivot conditions — no rubric tweaking, no post-hoc threshold changes | ✅ yes (transparency) |
| `scripts/generate_b2_packet.sh` | Harness script: runs System + Control-A, creates blind pairs, answer key, metadata | ❌ no (operator only) |
| `generated/` (output) | System transcripts, Control-A transcripts, blind pairs, answer key, metadata | blind-pairs/ + rubric only |

## Corpus design

### Definition tasks (5)

| Task | Topic | Turns | Challenge type |
|---|---|---|---|
| def-ru-01 | свобода | 3 | "разве свобода не означает делать всё что угодно?" |
| def-ru-02 | истина | 3 | "истина — это просто то, во что верит большинство" |
| def-ru-03 | сознание | 3 | "разве сознание не просто обработка информации?" |
| def-ru-04 | ответственность | 3 | "разве ответственность не просто наказание?" |
| def-ru-05 | память | 3 | "разве память не просто хранит?" |

### Distinction tasks (5)

| Task | Pair | Turns | Challenge type |
|---|---|---|---|
| dist-ru-01 | свобода / произвол | 2 | "разве произвол — не просто свобода без ограничений?" |
| dist-ru-02 | истина / мнение | 2 | "разве наука не меняет свои мнения?" |
| dist-ru-03 | сознание / самосознание | 2 | "разве самосознание — не просто более сложное сознание?" |
| dist-ru-04 | память / воспоминание | 2 | "разве воспоминание — не просто акт памяти?" |
| dist-ru-05 | свобода / ответственность | 2 | "разве ответственность не ограничивает свободу?" |

All topics are B3-covered (from `Semantic.Content`). All challenge
turns are designed to exercise D3 (repair/revision) — they present a
domain-valid counter-argument that should force the system to revise,
defend, or acknowledge its prior position.

## Control-A definition

Control-A is **structure-ablated, fluency-matched**:

| Disabled | Mechanism |
|---|---|
| Essence commitment | `shouldCommit` always returns `Nothing` |
| Commitment admission | CTS-42 bypassed: all claims admitted (no quarantine) |
| Repair routing | Challenge routed to generic response, not repair path |
| Semantic content layer | `Semantic.Content` predicates not appended (template-only) |

| Preserved | Why |
|---|---|
| GF linearization | Fluency unchanged — the surface engine is identical |
| Morphology resolver | Fluency preserved |
| Turn pipeline structure | Same Prepare → Route → Render → Finalize flow |

The fluency-matching is by construction: the same surface engine
produces both System and Control-A output. The only difference is
the removal of subject-structure. If raters cannot tell them apart,
fluency explains the output.

## Generation harness

`scripts/generate_b2_packet.sh`:

1. Verifies prerequisites (corpus, rubric, pre-registration, config)
2. Verifies governed-evidence conditions (`QXFX0_GOVERNED_EVIDENCE=1`)
3. Runs System transcripts (full pipeline, all features enabled)
4. Runs Control-A transcripts (structure-ablated env vars set)
5. Creates blind pairs (randomized labels, seed=42 for reproducibility)
6. Creates answer key (separate file, SHA-256 hashed)
7. Records packet metadata (admissibility, B3 verdict, M6-FELT status)

**Must be run in intended env**: GHC 9.6.6, GF runtime, morphology,
nix-instantiate, `QXFX0_GOVERNED_EVIDENCE=1`.

## Evidence admissibility

All transcripts must carry `trcEvidenceAdmissibility = EvidenceGoverned`
(SLICE-012). The generation script verifies this and records the status
in `packet-metadata.json`. Transcripts with
`EvidenceDegradedGuardUnavailable` or `EvidenceInadmissible` are
**excluded** from the packet.

## Pre-registered fail/pivot

See `test/fixtures/b2-eval/pre-registration.md`:

- **Fail**: System indistinguishable from Control-A on D1 and/or D3 →
  M6-FELT not evidenced. Fluency explains the output.
- **Pivot**: (i) redesign target (M4 approach change) or (ii) terminal-
  thesis reclassification (North Star reframe).
- **No rubric tweaking**: rubric dimensions and anchors are locked.
- **No averaging**: D1 ∧ D3 must pass independently; D5/D6 cannot
  carry a pass alone.

## What this packet does NOT do

- **No human rating** — that is B2-EXEC-002.
- **No M6-FELT claim** — M6-FELT remains NOT PROVEN.
- **No LLM** — System output is deterministic, no LLM involvement.
- **No semantic content engine changes** — the content layer is fixed
  from M4-001/M4-002.
- **No threshold setting** — numeric pass thresholds are calibration-
  pending, to be set in B2-EXEC-002 before the main rating run.

## DoD

- [x] Evaluation packet defined (corpus, config, rubric, pre-registration)
- [x] Harness script created (`scripts/generate_b2_packet.sh`)
- [x] Control-A definition documented
- [x] Corpus/rubric/answer-key separated
- [x] Evidence admissibility recorded in pre-registration
- [ ] Fast gate green (verify after commit)
- [x] No claim upgrade (M6-FELT = NOT PROVEN)
- [ ] Packet generated in intended env (B2-EXEC-002 prerequisite)
