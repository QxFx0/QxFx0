# Pre-registration — eval trace instrumentation (2026-10-28)

- **Status**: PRE-REGISTERED; implementation and verification recorded below.
- **Trigger evidence**: the M7 pre-fix packet reported
  `fallback_drift_rate = 0.000` while 14/30 turns rendered as
  `AuthorityShim` (`docs/closure/M7_BOUNDED_PACKET_2026-10-26.md`), and
  `trcContentSource = covered_exact` appeared on shim turns
  (`docs/closure/M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`).
- **Scope**: eval/reporting scripts only (`scripts/run_dialogue_eval_200.sh`).
  No runtime, routing, GF, or prompt-file change.
- **Owner decision**: make the dialogue gate consume the replay trace, not
  only text markers, 2026-10-28.

## Problem

`run_dialogue_eval_200.sh` classifies drift from response text alone. A
canonical-plan turn that falls back to an exploratory `AuthorityShim`
surface can still pass the marker list, so `fallback_drift_rate` was blind
to a real authority downgrade. The release gate
(`run_release_dialogue_gate.sh`) consumes that rate, so the blindness
propagated to the go/no-go decision.

## Proposed change

For every prompt row, after the CLI turn:

1. Resolve the runtime DB path with the same precedence as
   `QxFx0.Runtime.Paths.resolveDbPath`:
   `QXFX0_DB` → `QXFX0_DB_PATH` → `QXFX0_STATE_DIR/qxfx0.db` →
   `XDG_STATE_HOME/qxfx0/qxfx0.db` → `$HOME/.local/state/qxfx0/qxfx0.db`.
2. Read `turn_quality.replay_trace_json` for `(row_session_id, turn)` using
   the turn index reported by the CLI payload, unwrap
   `replayTraceEnvelopeVersion` when present, and retry for up to 5 s.
3. Add row fields: `turn`, `trace_available`, `authority_class`,
   `linearization_ok`, `trace_fallback_reason`, `derivation_rules`,
   `gf_mapped_fallback`, `authority_shim`.
4. Redefine `fallback_drift` as:

   ```text
   fallback_drift = legacy_text_markers OR authority_class == "AuthorityShim"
   ```

   Text markers remain (they catch template fallbacks); the shim class is
   added. `gf_mapped_fallback` stays informational: a mapped fallback is
   canonical by design and must not count as drift.
5. Extend `summary.json` / `summary.md` with
   `trace_available_count`, `authority_canonical_count/rate`,
   `authority_shim_count/rate`, `gf_mapped_fallback_count/rate`.
6. If the trace cannot be read, keep the row (`trace_available=false`,
   `authority_class=null`) and fall back to the legacy text-marker
   classification. Do not abort the run; the summary exposes how many rows
   lacked trace evidence.

`run_release_dialogue_gate.sh` is unchanged: its existing
`fallback_drift_rate <= 0.05` check now sees shim turns.

## Acceptance

- A 3-prompt mini-run over `spec/gf/release_corpus_prompts.txt` records
  `trace_available=true`, a non-null `authority_class`, and the new summary
  fields.
- On a shim-producing turn the row has `authority_shim=true` and
  `fallback_drift=true`; on a canonical turn with
  `DeriveGfMappedFallback`, `gf_mapped_fallback=true` but
  `fallback_drift=false`.
- The script still runs without a trace DB (legacy behavior preserved) and
  reports `trace_available_count=0`.
- `git diff --check` and `bash scripts/check_architecture.sh` remain green
  (scripts are outside the Haskell architecture rules but are checked for
  hygiene).

## Non-goals

- No new hard threshold and no change to the 0.05 drift bound.
- No change to prompt corpora, golden files, or the CLI JSON contract.
- No new runtime trace field; this consumes existing trace fields.
- No claim that the 500-prompt gate is unblocked.

## Risks and rollback

- Reading the DB adds one SQLite query per prompt; the eval already spends
  tens of seconds per isolated turn, so overhead is negligible.
- A custom `QXFX0_DB` that the eval process cannot read makes
  `trace_available=false`; the summary shows it instead of silently
  pretending the trace was checked.
- Rollback is a revert of the script; no persisted data changes.

## Implementation and verification (2026-10-28)

Implemented in `scripts/run_dialogue_eval_200.sh`:

- `resolve_eval_db_path` mirrors `QxFx0.Runtime.Paths.resolveDbPath`
  (`QXFX0_DB` → `QXFX0_DB_PATH` → `QXFX0_STATE_DIR/qxfx0.db` →
  `XDG_STATE_HOME/qxfx0/qxfx0.db` → `$HOME/.local/state/qxfx0/qxfx0.db`);
  the resolved path and `trace_wait_seconds` are recorded in `meta.env`.
- The per-row classifier reads `turn_quality.replay_trace_json` for
  `(row_session_id, payload.turns)` with a 5 s retry window
  (`QXFX0_EVAL_TRACE_WAIT_SECONDS` overrides it) and unwraps
  `replayTraceEnvelopeVersion`.
- New row fields: `turn`, `trace_available`, `authority_class`,
  `linearization_ok`, `trace_fallback_reason`, `derivation_rules`,
  `gf_mapped_fallback`, `authority_shim`, plus `legacy_fallback_drift`
  for transparency.
- `fallback_drift = legacy_fallback_drift OR authority_shim`;
  `gf_mapped_fallback` remains informational.
- Summary adds `trace_available_count`, `trace_missing_count`,
  `authority_canonical_count/rate`, `authority_shim_count/rate`,
  `gf_mapped_fallback_count/rate`, and `legacy_fallback_drift_count`.
  Authority rates use traced rows as the denominator; the release gate
  still consumes `fallback_drift_rate` over all rows.
- The script header now documents that the historical `_200` name does not
  mean 200 prompts.

Verification:

| check | result |
|---|---|
| `bash -n scripts/run_dialogue_eval_200.sh` | exit 0 |
| 3-prompt canonical run `gf-case-instr-20261028` (strict, isolated) | `trace_available=3/3`, `AuthorityCanonical=3/3`, `gf_mapped_fallback=2/3`, `fallback_drift=0` |
| `gf-rel-007` in that run | `AuthorityCanonical`, `trcLinearizationOk=true`, `trcFallbackReason=null`, nominative surface after the GF fix |
| 1-prompt shim run `gf-shim-instr-20261028` ("что такое добро?", strict, isolated) | `AuthorityShim=1`, `authority_shim=true`, `fallback_drift=true`, `legacy_fallback_drift=false` — the exact blindness this slice closes |
| no-trace branch (embedded classifier against an empty DB) | `trace_available=false`, `authority_class=null`, `fallback_drift` from legacy markers only |

The shim run shows the release dialogue gate will now count an
`AuthorityShim` turn as drift even when no legacy text marker appears. That
is intended: the gate was previously blind to this authority downgrade.
M7 and the 500-prompt gate remain unchanged (OPEN / BLOCKED).
