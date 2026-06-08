# QxFx0 — Audit Synthesis (2026-06-06)

Not a defect list (that is `audit-proactive-2026-06-06.md`). This is the
system-level read after a long session inside the code: what *classes* of defect
this codebase produces, where they cluster, why, and what that implies for
decisions made between sessions. Grounded in 8 real defects fixed this session
(A–E + the masked batch), not impressions.

---

## 1. The one-line diagnosis

**The skeleton is genuinely load-bearing; the failure modes live almost entirely
at boundaries the type system doesn't reach — serialization, schema, and error
provenance — and they hid for months because the things that should have caught
them (schema contract, slow suite) had blind spots or were drowned in noise.**

The architecture invariants, the determinism spine, the typed routing — those
held up under a full session of adversarial probing. Nothing I found was a flaw
in the *core model*. Every real defect was at a **seam**: JSON in/out, SQL
schema vs code, or a typed error that lost its shape in transit.

---

## 2. The defect taxonomy (what actually broke)

Eight real defects, and they fall into **three classes** — not eight unrelated
bugs. This is the important pattern:

### Class I — Trust-boundary leaks (remote/external data trusted verbatim)
- **B**: remote `predictiveDelta: 999.0` stored into the knowledge tree
  (write-path clamped, read-path not).
- **#7**: embedding remote path had no host allowlist (would send creds to any
  https host).
- **918/919**: untrusted-host override needed only one factor, not two.

These are the most dangerous (a peer writes authority/destination into the
system) and the easiest to miss, because the *happy path* works — only an
adversarial or corrupted input reveals them.

### Class II — Serialization asymmetry (encode ≠ decode)
- **C**: `LocalRecoveryCause/Strategy` — hand-written ToJSON (snake_case) +
  generic FromJSON (constructor name) → round-trip broken.
- **D**: `TurnReplayTrace` ToJSON-only → replay-from-DB impossible.
- **907**: legacy state rejected because a field became required on read.
- **the masked batch**: `ecWitnessHash: expected TrajectoryHash, encountered
  Object` — another encode/decode gap.

Root: **ToJSON and FromJSON are written/derived independently**, so they drift.
The codebase has *both* hand-written (render-based) and generic-derived
instances, and mixing them on one type is silently fatal. There is **no
round-trip property test discipline** — `decode . encode == id` is asserted
almost nowhere, so these only surface when a persisted blob is actually read
back (which, for the trace, never happened until I built it).

### Class III — Error-provenance loss (typed error → flat string → mismatch)
- **E**: `PersistenceTxError(StageUnknown, <redacted>)` masked
  `no such column: state_revision` across 63 tests — the redaction hid the
  cause and `StageUnknown` hid the location.
- **structured-constructor rot** (embedding 6/8, runtime-init/sqlite in the
  masked batch): error types migrated `FooError Text → FooErrorStructured`, but
  call-sites and tests still pattern-match the flat constructor → fall through.

Root: an error-model migration (`*Error Text` → `*ErrorStructured`) was done
**half-way** — the new constructors exist (ExceptionPolicy.hs:74-82, five such
pairs) but consumers weren't all updated. Plus `renderQxFx0ExceptionForLog`
redacts the detail, so when something *does* fail, the log actively hides why.

---

## 3. Where the defects cluster (the map)

| Subsystem | src modules | defects found | risk read |
|---|---|---|---|
| **Bridge** (SQLite/persistence) | 23 | E (+ enabled #1) | **highest** — schema/code drift, the contract blind spot |
| **Learning** | 14 | B, 884-887 | high — trust boundary + audit-trail integrity |
| **Types** (serialization) | (Types/*) | C, D, 907 | high — the encode/decode asymmetry lives here |
| **Semantic/Embedding** | 42 | #7, 6/8 | high — network boundary + error rot |
| **Core/Guard** | 124 | A (toxicity fail-open) | medium — design contradiction, not a crash |
| **Self, Render, Lexicon, Policy** | 14/5/8/11 | none | clean under probing |

The cluster is unmistakable: **persistence + serialization + external I/O.**
The "philosophical core" (Self/*, the conatus/adjunction/essence layer) produced
**zero** defects — it's pure, well-tested, and the type system actually guards
it. The bugs are all in the plumbing that carries data *across* the pure core's
edges.

---

## 4. Why it hid for months

Three guards exist that *should* have caught these, each with a hole:

1. **The schema contract** (`SchemaContract.hs`) checks tables + some columns —
   but had no column contract for `runtime_sessions`, the exact table missing a
   column (E). Fixed; the blind spot is now closed.
2. **The slow suite** runs real turns against on-disk SQLite — but 63/133 of it
   was dead with `PersistenceTxError`, and that was read as "environment flaky"
   rather than "every save is broken." A red suite that everyone learns to
   ignore is worse than no suite.
3. **No round-trip test discipline** — `decode . encode` is the natural catch
   for Class II, and it essentially didn't exist. I added it for EffectSnapshot,
   the full trace, and the recovery enums; it should be the *default* for any
   persisted type.

The deeper lesson: **the codebase's self-checking machinery is real but
under-maintained.** It's the same signature as the doc-drift from earlier
sessions — the verification layer exists, but reality outgrew it in the seams.

---

## 5. Standing structural smells (not yet defects, but defect factories)

- **5 `*Error Text` / `*ErrorStructured` pairs** in ExceptionPolicy.hs — every
  flat constructor still in use is a future Class-III mismatch. Either finish
  the migration (drop the flat forms) or lock each with a test.
- **64 `*Admission` modules** — the boilerplate fronton. 18 are now on the
  generic (P1-1); the rest, plus the ~4 two-guard / 2 predicate variants, remain
  duplicated. Mass without proportional logic; a refactor magnet.
- **4 residual stringly-typed gate dispatches** (`== "SelfStateQ"` in Core) —
  the typed-enum migration (P0-3) only reached the render edge, not the gates.
- **Toxicity guard is advisory (A)** — documented, but it's a "safety" guard
  that doesn't block; a content-moderation expectation would be violated.
- **Redacting error renderer** — good for prod privacy, but there's no
  un-redacted debug path, so every persistence/SQLite failure is opaque until
  someone patches the renderer (as I had to, to find E). A `--debug-errors`
  escape hatch would have saved hours.

---

## 6. What this means for between-session decisions

**If the goal is production-readiness of the water-pipe** (the part with real
value, per earlier sessions): the work is now *bounded and known*. Class I/II/III
are each a finite, enumerable sweep:
- Class I: audit every external-input → stored-state path for clamping/validation
  (B and #7 were two; there may be 1–2 more in Learning/Bridge).
- Class II: add `decode . encode == id` tests for every persisted type; finish
  giving FromJSON to anything ToJSON-only that touches persistence.
- Class III: finish the error-model migration; add the debug-errors hatch; make
  the slow suite green and *keep* it green (a green slow suite is the single
  highest-leverage thing — it's the only place these seam bugs surface).

**If the goal is the research thesis** (functional selfhood made executable):
the Self/* layer is clean and the bugs are all in infrastructure that the thesis
doesn't depend on. The thesis is *not* threatened by any of this. But the corona
(conatus/adjunction/essence) still runs nearly idle in the live config — that's
an intellectual-completeness question, separate from these defects.

**The honest headline for both:** this session moved the system from "looks
deterministic and safe" to "is measurably more deterministic and safe, with the
remaining gaps mapped." The state_revision finding (E) is the proof that the gap
between *claimed* and *actual* was real and load-bearing — every production save
with revision-checking was failing, masked as flakiness. That's now fixed and
the masking removed.

---

## 7. Deferred (explicitly, not hidden)

- **Masked batch** (~7 pre-existing decode/corruption failures revealed by E) —
  triage rot vs real, batch noted in `audit-proactive §E`.
- **#1 on-disk round-trip is proven for the trace**, but only one effect
  (apiHealthy) is replayed; the *wide* path (all effects as replay inputs) is
  the documented next step in `mkReplayPipelineIO`.
- **Toxicity block-vs-warn** — a product decision (A), documented in README.
- **Two-guard / predicate admission variants** — out of P1-1 scope; need a
  richer generic.

Nothing here is a landmine; all of it is on the map.
