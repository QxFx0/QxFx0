# M7 confirmatory run — PASSED (bounded 30-prompt packet, 2026-10-31)

- **Status**: **GATE PASSED** — 30/30 turns satisfy the pre-registered rule.
  This closes the bounded M7 acceptance question only; it is not a claim about
  general answer quality, and it does not touch the 500-prompt gate.
- **Rule**: `docs/closure/M7_GOLDEN_ACCEPTANCE_RULE_2026-10-28.md`
  (PRE-REGISTERED 2026-10-28; D1-A / D2-A / D3 30/30 / D4 informational).
- **Frozen admissible sets**: `spec/gf/m7_admissible_predicates.tsv`,
  sha256 `ef75231d65b1bf4bae20a55c93721c034dd020e2a6da66654848a34945033766`
  (45 rows = 30 golden + 15 owner-approved alternatives).
- **Tree**: `f34cf62` (`test: pre-register M7 golden acceptance rule and gate
  checker`). Runtime behavior is identical to `bcceee6`; the commit adds the
  rule document, the frozen TSV and the checker only.
- **Run**: `m7-gf-confirm-20261031`, 30 isolated strict turns, harness exit 0.

## Frozen command

```
QXFX0_RUNTIME_MODE=strict QXFX0_EVAL_SESSION_MODE=isolated \
  bash scripts/run_dialogue_eval_200.sh m7-gf-confirm-20261031 \
  /tmp/opencode/m7-gf-case-30.tsv
```

The packet file is generated mechanically from
`spec/gf/release_corpus_prompts.txt` (`gf-rel-NNN`, prompt, `CMDefine`), in
corpus order. Nothing in the rule, the packet or the admissible sets was
changed between pre-registration and this run.

## Gate result

Checker: `python3 scripts/m7_gate_check.py reports/eval_runs/m7-gf-confirm-20261031`,
exit 0.

| gate | requirement | result |
|---|---|---:|
| authority | `AuthorityCanonical` on every turn | 30/30 |
| linearization | `trcLinearizationOk == true` | 30/30 |
| fallback reason | `trcFallbackReason == null` | 30/30 |
| shim | `authority_shim_count == 0` | 0 |
| structure | `Тезис:` + `Проверка:` present | 30/30 |
| harness markers | `fallback_drift_count == 0` | 0 |
| semantic | predicate ∈ frozen admissible set | 30/30 |
| **overall** | **30/30, no exceptions** | **PASS** |

Supporting counters from `summary.json`: `intent_fit 30/30`,
`trace_available 30/30`, `critical_mismatch 0`, `morphology_defect 0`,
`runtime_or_parse_error 0`.

## Determinism

The confirmatory run is the third packet on this corpus and reproduces the
descriptive ones exactly:

- predicates identical to `m7-gf-case-20261028` on all 30 turns;
- surfaces identical to `m7-gf-case-20261028` on all 30 turns;
- same 5 exact-surface hits (`gf-rel-001`, `005`, `010`, `012`, `016`);
- `gf_mapped_fallback_count = 14` in all three packets.

This is a useful side result: the pipeline is byte-stable across runs on a
fixed tree, so future packet differences can be attributed to code changes
rather than sampling noise.

## Informational (D4, non-blocking)

| metric | value |
|---|---:|
| exact-surface match | 5/30 |
| `gf_mapped_fallback` derivations | 14/30 |
| latency, mean | 78,699 ms |
| latency, median | 74,151 ms |
| latency, min / max | 56,659 ms / 236,094 ms |

**Latency caveat.** Every prompt runs in its own isolated process, so each of
the 30 numbers includes a full bootstrap. The first turn (236 s) is clearly
cold-start dominated, but turns 2–30 still cost 57–74 s each, which means the
per-turn *warm* cost is not measured here at all. Do not read these numbers as
"a turn takes 70 s"; read them as "an isolated eval turn costs 57–74 s with
bootstrap included". A warm multi-turn session is the only way to separate the
two, and that measurement is still open.

**Fallback caveat.** 14/30 curated-corpus turns still go through
`DeriveGfMappedFallback`. The gate accepts them because the substituted
predicate is an owner-approved admissible predicate for the same topic, not
because the substitution is desirable. The 14-row content review remains open
and is the main quality debt behind this PASS.

## What this proves and what it does not

- **Proves**: on the frozen 30-prompt Russian GF definition corpus, with the
  frozen rule and the frozen admissible sets, every turn is canonical, fully
  linearized, structurally complete (thesis + check), and emits an admissible
  predicate. The result is reproducible byte-for-byte.
- **Does not prove**: general answer quality; quality outside the 30 curated
  topics; that fallback substitutions are good (they are merely admissible);
  that exact-surface replay matches the golden file (5/30, informational by
  D4); anything about the 500-prompt gate, which has no labeled corpus.

## Reproduction

```
/usr/bin/python3 scripts/m7_gate_check.py reports/eval_runs/m7-gf-confirm-20261031
```

The checker aborts (`INVALID`, exit 2) if the admissible-set file no longer
matches the pre-registered sha256, so a PASS cannot be manufactured by editing
the sets after the fact.

## Open follow-ups

1. 14-row fallback content review (quality, not gate).
2. Warm-session latency decomposition (bootstrap vs per-turn).
3. Test matrix on this tree: `qxfx0-test` runtime/http groups and the slow
   groups have not been re-run since `bcceee6`.
4. 500-prompt gate: still **BLOCKED** (no labeled corpus; B2 second rater
   unavailable).
