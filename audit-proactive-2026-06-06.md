# Proactive Audit — 2026-06-06

Hunt for NEW defects (no red test pointing at them), verified individually
against code. Subagents fanned out by bug-class; every claim below was
hand-confirmed (and several agent claims were refuted — see bottom).

## Confirmed defects

### A. Toxic output is emitted, not blocked (fail-OPEN safety guard) — HIGH
- `Core/Guard/Checks.hs:87-93` `checkToxicity` returns **`InvariantWarn`**.
- `Core/Guard/Recovery.hs:18-22` `fallbackSurfaceOnBlock` diverts to the
  recovery surface **only on `InvariantBlock`**; `InvariantWarn` returns the
  original (toxic) surface.
- `Core/TurnLegitimacy/Output.hs:25-28` marks provenance `FromDB` (trusted) for
  the `_` (incl. Warn) case.
- `finalSafetyStatus` → `finalizeMetrics` → `tmSafetyStatus` is a **log string
  only** (`Observability.hs:104`). Verified: nothing in src/ acts on
  `InvariantWarn` (grep = only definition + severity ladder). No second
  toxicity gate exists.
- **Net:** toxic rendered text reaches the user verbatim; only logged.
- **Design contradiction, not a typo:** `CoreBehavior.hs:798` *asserts*
  toxicity → `isWarning`. The intent was locked as advisory. But the README
  sells "fail-closed, typed safety," and the guard's own ladder ranks
  Warn=1/Block=2. Decision needed: should toxicity block (→ change checkToxicity
  to InvariantBlock + update the test), or is detect-and-log truly intended?
  Stuck-repetition staying advisory is defensible; toxicity is not, for a
  safety guard.

### B. predictiveDelta not clamped on DESERIALIZE — MEDIUM (gap in my own 565d73d fix)
- `Learning/Loop.hs` (565d73d) clamps predictiveDelta at fruit CREATION.
- `Learning/KnowledgeTree.hs:104` `FromJSON` reads `predictiveDelta` with
  `.!= 0.0` and **no clamp**.
- `KnowledgeTree.hs:338` `authoritativeNetDelta = conatus + predictive` gates
  promotion (`>=0.0`, line 267) and retention (`>=-0.3`, line 319).
- **Net:** a fruit persisted before 565d73d (or a hand-edited/corrupted row)
  with `predictiveDelta: 999.0` deserializes at 999.0 and sails through
  promotion. The write path is closed; the read-back path is not. Fix: clamp in
  FromJSON (or in authoritativeNetDelta) with the same bound as Sandbox.hs:186.

### C. LocalRecoveryCause / LocalRecoveryStrategy round-trip is broken — MEDIUM (latent)
- `Types/Recovery.hs:44,78` derive **generic `FromJSON`** (expects constructor
  name, e.g. `"RecoveryLowLegitimacy"`).
- `Types/Recovery.hs:46-47,80-81` hand-written `ToJSON` writes the **rendered
  snake_case** (e.g. `"low_legitimacy"`, lines 88-96 / 99+).
- **Net:** `decode (encode x) ≠ Just x` — decode fails. Latent today because
  `TurnReplayTrace` has no `FromJSON`, but these are `trcRecoveryCause/Strategy`
  fields — it detonates the moment trace-replay-from-DB is built (the deferred
  item #1). Fix: hand-write FromJSON to parse the rendered text (mirror render),
  or make ToJSON use generic encoding.

### D. Full-trace replay-from-DB is blocked by missing FromJSON — HIGH for item #1
- `TurnReplayTrace` (`Types/TurnProjection.hs:316` area) is ToJSON-only.
- Plus nested ToJSON-only types: `PreActorFailureKind`/`PreActorFailureEvent`
  (TurnProjection.hs:41,48), and the broken-round-trip Recovery enums (C).
- **Net:** the production replay round-trip (DB blob → FromJSON → replay) that
  item #1 needs cannot be built without first giving the trace + these nested
  types working FromJSON. Scopes item #1 honestly: it's not "add one instance."

## Refuted agent claims (checked, NOT bugs)
- **MVar stale-state across failed turns** — FALSE. The consciousness/intuition
  MVar (`Context.hs:142`) is written ONLY via `TurnReqCommitRuntimeState`
  (`Commit.hs:198`), at commit. Route/prepare thread the loop functionally
  (`Resolve.hs:115` perConsciousLoop), no mid-turn mutation. A pre-commit throw
  leaves the MVar at last-committed value. No leak.
- **Replay delegates to test defaults = bug** — NOT new; that's the documented
  narrow-fix scope of mkReplayPipelineIO (legitimacy-path only). Real point is
  D (no full FromJSON), already captured.
- **NixGuard timeout fail-open** — UNVERIFIED/likely-overstated. The agent's own
  trace showed `Unavailable` IS propagated (not dropped); it contradicted itself.
  Not asserting without the rigor the others got.

## Severity order
A (toxic fail-open) > D (replay blocked) > B (deserialize clamp gap) ≈ C (recovery round-trip).

---

## E. runtime_sessions.state_revision missing from schema — CRITICAL (found pursuing #1 DB round-trip)

While building the on-disk DB round-trip (item #1 second half), the slow suite
showed **63/133 tests erroring** with `PersistenceTxError(stage=StageUnknown,
<redacted>)`. Un-redacting the detail revealed the root cause:
`prepare failed for loadStateRevision … no such column: state_revision`.

- `loadStateRevisionDirect` (StatePersistence.hs:410) `SELECT state_revision
  FROM runtime_sessions` and the CAS `UPDATE runtime_sessions SET state_revision
  = state_revision + 1` (line 189) depend on a column that was **never declared**
  in the embedded DDL, the migrations, OR the schema contract. Added in the v3
  port (`98d140f`); every save-with-revision threw. Production-affecting, not
  just tests.
- **Contract blind spot:** `schemaContractColumns` listed migration-added cols
  for `turn_quality`/`shadow_divergence_log` but NOT `runtime_sessions` — the
  drift-checker that exists to catch exactly this had no column contract for the
  one table with the missing column.

**Fixed (full + contract guard):** column added to canonical `schema.sql`,
migration-001 snapshot, embedded SQL (synced), Haskell `EnsureColumn` v3→v4
runtime repair, schema contract (Haskell + TSV manifest), `currentSchemaVersion`
3→4, migration-004 marker. All 3 schema gates green; 63 TxError → 0; the #1 DB
round-trip test (live turn → on-disk SQLite → blob → decode → mkReplayPipelineIO)
now passes; unit 1103 green.

### Unmasked by E (pre-existing, NOT caused by the fix) — to triage later
Clearing the TxError flood revealed ~7 pre-existing slow-suite failures the mask
hid (verified not in my diff; same family as A/audit 6/8/9/12):
- `RecoveredCorruptOrigin` vs `RestoredOrigin` (corruption-recovery origin).
- legacy numeric trajectory-hash decode: `$.ssSelfState.selfEssence.contents[1]
  .ecWitnessHash: expected TrajectoryHash, but encountered Object` (a real
  FromJSON gap — smells like a genuine decode defect).
- `expected [PdSchemaMissingFields …] but got []` (blob diagnostics).
- `DialogueOutput` vs `SemanticIntrospectionOutput` (introspection mode).
- structured-error-constructor rot (`RuntimeInitError`/`SQLiteError` flat-pattern
  tests vs `*Structured`) — the same migration trap as embedding 6/8.
These were already red on a clean-HEAD baseline (masked as TxError); deferred as
a separate known-issue batch.
