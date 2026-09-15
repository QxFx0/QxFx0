# ADR-0053: Core Layer Decomposition — Domain Namespaces

**Status:** Proposed
**Date:** 2026-09-08
**Related:**
- ADR-0007 (dual-mode / Conatus modernization path)
- ADR-0043 (module rename campaign — Tier-0 mechanic reused here)
- ADR-0048 (ADR moratorium — this ADR is the required record before boundary changes)
- `docs/ARCHITECTURE.md` §1 (eight-layer contract)
- `scripts/check_architecture.sh` rules [4], [11], [12], [14]

---

## 1. Context

`QxFx0.Core` has grown to **105 modules / ~15.9k LOC** across the top level
(51 files) and 12 subdirectories, while the architecture contract
(ARCHITECTURE.md §1.1) describes it in one sentence: "consciousness loop,
turn pipeline, guard/recovery, identity". The layer no longer matches its
own description, and three mechanical symptoms confirm the drift:

1. **Rule [11] orphan (2026-09-08)**: `QxFx0.Core.M6FeltGate` is exposed but
   unreachable from Runtime/TurnPipeline — an evidence gate living in the
   consciousness-layer namespace. Fixed by whitelist; the whitelist exists
   because the layer boundary itself is blurred.
2. **The top level is a mixed shelf.** 51 top-level files separate into
   four unrelated concerns: 18 `*Admission` gates, 7 `Turn*` facades,
   10 genuinely core-loop modules (ConsciousnessLoop, Intuition, FMAR,
   TruthContract, …), and ~20 single-purpose modules that sit in Core only
   because Core historically imported nothing.
3. **Dead ports.** `Core/Semantic/` and `Core/Policy/` directories exist,
   are referenced by `check_architecture.sh` port-prefix checks, but contain
   zero modules — a boundary that was declared and never populated.

Measured fan-in (2026-09-08, grep over src/app/test) shows every top-level
module has at least one live importer — this is **not dead code**; it is
misplaced live code.

## 2. Decision

Re-namespace `QxFx0.Core` by **domain**, using the Tier-0 mechanic proven in
ADR-0043: file move + module header edit + import-site rewrite + cabal
`exposed-modules` update; compiler-checked, zero behavior change, no
serialized types touched. Staged, each stage lands green.

### 2.1 Target layout (top level shrinks 51 → ~10)

| Namespace | Contents (from today's top level) | Rationale |
|---|---|---|
| `Core.Admission.*` | all 18 `*Admission.hs` + `EvidenceAdmissibility` | one concern: pre-release approval; kills the rule-[11] `Admission` whitelist by making the boundary real |
| `Core.Evidence.*` | `M6FeltGate`, `ClaimBuilder` | release/evidence gates consumed by test & CI contour — the honest home for the 2026-09-08 orphan |
| `Core.Loop.*` | `ConsciousnessLoop`, `Intuition`, `BackgroundProcess`, `Bayesian`, `SensePlan` | the actual consciousness loop and its solvers |
| `Core.Identity.*` | `Ego`, `IdentitySignal`, `IdentityGuard` (top-level part), `R5Dynamics`, `TruthContract` | identity, stance and truth accountability — the "who am I defending" cluster |
| `Core.Meaning.*` | `MeaningGraph`, `ContentCluster`, `TopicDrift`, `TopicTransition`, `DialogueThread` | graph-shaped semantic observers feeding the pipeline |
| `Core.Pipeline.*` (existing `TurnPipeline/`, `TurnPlanning/`, `TurnRouting/`, `TurnRender/` merged) | all `Turn*` subdirs + the 7 top-level `Turn*` facades | the Prepare→Route→Render→Finalize spine keeps its name; facades become real re-export modules where they are pure re-exports, or move next to their logic |
| `Core.Operational.*` | `SessionLock`, `PipelineIO/`, `Observability` | process/IO plumbing that Core legitimately owns |
| `Core.Self.*` (port, see 2.2) | `PrincipledCore`, `Legitimacy/`, `StanceClassifier/`, `TurnLegitimacy/` | stance/legitimacy appraisal consumed by routing |

Subdirectories `Guard/` (413 LOC), `TopicDrift.hs`, `TurnModulation/` are
small enough to fold into the nearest namespace during their stage rather
than persist as single-module namespaces.

### 2.2 Ports become real or die

`Core/Semantic/` and `Core/Policy/`: delete the empty directories and the
corresponding port-prefix checks in `check_architecture.sh` (rules that
reference `CORE_SEMANTIC_PORT_PREFIX`/`CORE_POLICY_PORT_PREFIX`), **or**
populate them in the first stage that touches those domains. Empty declared
boundaries are worse than none: they teach readers that declared structure
is optional.

### 2.3 Staging (each stage = one green landing)

1. **Stage 1 — Admission namespace.** Mechanical, 19 files, ~60 import
   sites. Removes the `Admission` whitelist from rule [11].
2. **Stage 2 — Evidence namespace.** `M6FeltGate` + `ClaimBuilder` + the
   rule-[11] `M6FeltGate` whitelist removal.
3. **Stage 3 — Loop + Meaning namespaces.** The observer modules; touches
   `Salience` wiring (ContentCluster importers) and finalize imports.
4. **Stage 4 — Identity namespace.** TruthContract has 16 importers —
   largest blast radius; lands alone with its equivalence suite.
5. **Stage 5 — Pipeline fold + facade truth pass.** Merge `Turn*` subdirs
   under `Core.Pipeline`, convert pure re-export facades to real re-export
   modules (explicit export lists), delete dead ones.
6. **Stage 6 — ports cleanup** (2.2) + `docs/ARCHITECTURE.md` §1.1 update
   + this ADR's acceptance.

### 2.4 What this ADR does NOT decide

- No module moves **across** layers (Core→Semantic, Core→Self stay where
  they are; cross-layer moves are ADR-0007 territory).
- No behavior, type, or serialized-schema changes (Tier-1 renames remain
  governed by ADR-0043 §2.2 machinery).
- No new whitelists in rule [11] — the campaign's explicit goal is to
  **remove** the existing two.

## 3. Alternatives Considered

### 3.1 Status quo + periodic audits
Rejected: the 2026-09-08 gate drift (6 violations at HEAD, Gate 3 commented
out of CI Fast) shows audits without mechanical structure converge back to
noise. The whitelist count only grows.

### 3.2 Split Core into multiple cabal packages
Rejected for now: package boundaries serialize the wrong split until the
domain namespaces stabilize (this ADR). Revisit after Stage 6 with one
year of import-graph data. ADR-0048 requires a fresh ADR for it.

### 3.3 Move misplaced modules down into Semantic/Self
Partially folded in: `MeaningGraph`/`ContentCluster`/`TopicDrift` stay in
Core (they are consumed by routing/finalize, and rule [2] forbids Semantic
importing Core — moving them to Semantic would invert the dependency for
their current consumers). The `Core.Meaning.*` namespace records this
coupling instead of hiding it.

## 4. Consequences

**Positive**
- Rule [11] whitelist count 2 → 0; the layer contract becomes enforceable
  as written.
- Top level 51 → ~10 files; new modules get an unambiguous home.
- Import-graph audits (`reports/audit`) get stable domain buckets.

**Negative**
- ~200 import-site edits across 6 stages; merge conflicts with any
  in-flight branch touching Core (mitigation: stages are small, land fast,
  announced in the execution board).
- Git history file-tracking breaks per moved file (mitigation:
  `git mv` + `--follow` where reviewers rely on it; CHANGELOG notes per
  stage).
- Docs/Haddock module paths churn (mitigation:
  `scripts/check_doc_module_paths.py` already in CI catches stale paths).

**Costs measured**: Stage 1 is ~19 files × (header + cabal line) + ~60
import sites; a half-day with the equivalence suites as the safety net.

## 5. Quality Gate

Each stage, before landing:

1. `cabal build all` green (compiler is the primary equivalence check).
2. Full `qxfx0-test-fast` (1812 cases) + the stage's affected suites
   (AdmissionEquivalence for Stage 1; M6FeltGate/M6FeltBenchmark for
   Stage 2; ReplayDeterminism + TraceAnalysis for Stages 3–5) — 0 errors,
   0 failures.
3. `check_architecture.sh` green with **no new whitelists**; Stage 2 must
   delete the `M6FeltGate` whitelist entry, Stage 1 the `Admission` one.
4. `scripts/check_doc_module_paths.py` green (no stale doc references).
5. Import-graph delta report attached to the stage commit: top-level file
   count strictly decreases; rule-[11] orphan count stays 0.

Final acceptance of this ADR: all six stages landed, both rule-[11]
whitelists removed, `Core/Semantic/`/`Core/Policy/` resolved (populated or
deleted with their port checks), `docs/ARCHITECTURE.md` §1.1 one-liner
updated to name the namespaces.
