# QxFx0 — Skeptical Audit (2026-06-21)

**Auditor**: Agent2048  
**Method**: Static inspection of source, tests, docs, build artifacts, and prior audits. No `cabal build` or `cabal test` run (build timed out; tests not run this session).  
**Stance**: Skeptical — assume nothing works until proven by mechanical evidence.

---

## Executive Verdict

**The system is a documentation-heavy engineering framework that does not currently produce thought.** It has extraordinary process infrastructure (48 ADRs, 54 closure docs, 325 markdown files, 24 shell scripts, 11 Agda specs, 7 GF grammars) wrapped around a cognitive engine whose actual output is template text. The gap between *claimed capability* and *demonstrated behavior* is the central finding.

---

## 1. Scale and Composition

| Metric | Value | Skeptical Read |
|--------|-------|----------------|
| Haskell modules | 403 | Large, but 88,917 LOC (56%) is generated lexicon data |
| Hand-written LOC | ~69,696 | Real engineering, but spread thin across many subsystems |
| Test files | 99 (79 suites in cabal) | Impressive count, but many suites marked "wired, not run" |
| ADRs | 48 (accepted) + 5 proposed | 5 proposed ADRs govern promotion gates — none accepted |
| Closure docs | 54 | Closure plan for tech debt that predates the system's first release |
| Audit files | 6 prior + this one | System has been audited more than it has been run |
| Docs : Source ratio | 325 : 403 files | More documentation files than source files |

**Observation**: The project has invested more effort in *describing* its discipline than in *demonstrating* its cognitive output. The documentation-to-code ratio is approximately 2:1 by file count.

---

## 2. Build and Test Status — UNVERIFIED

- Build artifacts exist (`dist-newstyle/`, dated Jun 21 06:56), suggesting a recent successful build.
- **However**: `cabal build` timed out in this audit session (30s limit). No confirmation the system compiles clean right now.
- Per `FOLLOWUPS.md` §15.1: **7 test suites are marked "wired" but "not run"** — including ReplayGate, ObserverDiscipline, TraceSchema, RegenerableDerived, PromotionFlagDiscipline, ArchitectureInvariants.
- Per `FOLLOWUPS.md` §15.2: "`cabal build all` — verify the code compiles. Currently not run in this session." and "`cabal test qxfx0-test` — verify the new test suites pass. Currently not run."
- **No release has ever been cut.** `RELEASE_CHECKLIST.md` is "documented but unused."

**Verdict**: The system's mechanical correctness is **unproven as of the latest working session**. The build artifacts may be stale relative to uncommitted changes.

---

## 3. Essence Regime Drift — CONFIRMED TRIPLE INCONSISTENCY

This is the most load-bearing defect because it sits on the system's central subjecthood claim.

| Layer | What it says | Evidence |
|-------|-------------|----------|
| **Code (operational)** | Essence is always-on, no flag | `Finalize/State.hs:359`: "shouldCommit is always evaluated; no feature flag"; `shouldCommit` runs unconditionally every turn |
| **Code (regime stamp)** | Essence is active | `RuntimeRegime.hs:81`: `rrEssenceActive = True` — but this field is **write-only** (grep confirms it is never read anywhere in `src/`) |
| **Docs** | Essence is flag-off | `AGENTS.md:23` and `SELF_LAYER_STATUS.md:59`: `essenceCommitmentEnabled` "never implemented" |
| **Tests** | Test references nonexistent flag | `PromotionFlagDiscipline.hs:262`: asserts `essenceCommitmentEnabled` is absent from `src/` — which it is, but the test is checking for absence of a flag that docs say should be present-off |
| **ADR** | ADR-0036 cited as "promoted" | Lives in `docs/adr/proposed/` — i.e., **proposed, not accepted** |

**Net**: Essence commitment is always-on in behavior, stamped-on in regime metadata, documented-off, and governed by a nonexistent flag tested by a discipline test. This is exactly the "claim ≠ reality" seam the project doctrine declares inadmissible — on the most load-bearing subjecthood assertion.

---

## 4. Guard Fail-Open — CONFIRMED

The NixGuard constitutional governance is **fail-open degraded**, not fail-closed:

1. `NixGuard.hs:66`: `runNixEval` failure → `Unavailable "nix evaluator unavailable: ..."`
2. `Prepare/Build.hs:103-104`: `Unavailable` → `nixAvailable = False`, `isNixBlocked = False`
3. `Route/Build.hs:301`: `not (tiNixAvailable ti)` → `ExplicitFallbackSurface` — the turn **still emits output**, just via fallback surface
4. The cascade (`Shadow.hs:119`) only routes to `CMRepair` on `ShadowSeverityUnavailable`, not on nix `Unavailable`

**Consequence**: When the nix evaluator is unavailable, every turn runs **without constitutional governance** and still produces output. The AB evaluation evidence (2026-05-21) was collected entirely in this ungoverned mode. The system's "felt-evidence" for subjecthood was produced without the guard that is supposed to guarantee it.

---

## 5. No Content Quality Gate — CONFIRMED

The system tests **routing, not thinking**:

- Golden corpus tests assert `expected_family_any_of` + `must_not_focus` — never content quality.
- All four M6 evidence contours (C1–C4) test continuity, trace-fields, commitment-store mechanics, and GF round-trip. **None measures quality of thinking.**
- Actual dialogue output (from `audit-objective-2026-06-17.md` §2):
  - T1 "что такое свобода" → "…свобода является понятием. Локальный режим восстановления…" — semantic payload: "freedom is a concept" + boilerplate.
  - T3 → breaks: "…Ядро: Ядро ищ" (truncated mid-word).
  - T4 "в чём разница свободы и произвола" → "Сравнение плаузибельности требует явной рамки…" — template, no comparison.
  - AB `blind_pairs`: `response_1` ≡ `response_2` in every pair — the two "versions" are indistinguishable.

**Verdict**: The system produces template text, not thought. There is no mechanical gate that would catch this.

---

## 6. Prior Audit Defects — STILL OPEN

### Class I — Trust-boundary leaks (HIGH)
- Remote `predictiveDelta: 999.0` stored into knowledge tree (write-path clamped, read-path not).
- Embedding remote path had no host allowlist.
- Untrusted-host override needed only one factor, not two.

### Class II — Serialization asymmetry (HIGH)
- `LocalRecoveryCause/Strategy`: hand-written ToJSON (snake_case) + generic FromJSON (constructor name) → round-trip broken.
- `TurnReplayTrace` ToJSON-only → replay-from-DB impossible.
- Legacy state rejected because a field became required on read.
- `ecWitnessHash: expected TrajectoryHash, encountered Object` — encode/decode gap.
- **Root cause**: No `decode . encode == id` property test discipline anywhere in the codebase.

### Class III — Error-provenance loss (MEDIUM)
- `PersistenceTxError(StageUnknown, <redacted>)` masked `no such column: state_revision` across 63 tests.
- Structured-constructor rot in embedding and runtime-init/sqlite modules.

### Unbounded data structures (P0/P1)
- Commitment quarantine: unbounded list, O(n) scan on every check.
- Provisional atoms: no hard cap, O(n) `find` on every observation.
- Knowledge tree quarantine: marginal fruits accumulate indefinitely.

**Status**: These were identified in prior audits (2026-06-03 through 2026-06-17). No evidence they have been fixed. The `FOLLOWUPS.md` tracker does not mark them as resolved.

---

## 7. Drafted ≠ Wired ≠ Landed

The project's own 3-state taxonomy (§15 of FOLLOWUPS.md) reveals the gap:

| Item | State | Problem |
|------|-------|--------|
| ADR-0034 (central closure ADR) | drafted | **Not accepted** — the core organizational ADR is still a proposal |
| 5 promotion ADRs (0018-0022) | drafted | None accepted; promotion gates not activated |
| ADR-0023 (demotion procedure) | drafted | Not activated |
| PROMOTION_PLAYBOOK.md | drafted | First candidate (ADR-0019) not yet promoted |
| RELEASE_CHECKLIST.md | drafted | **Never used** — no release ever cut |
| PYTHON_MIGRATION_TRACKER.md | drafted | **0/34 scripts migrated** |
| 7 test suites | wired | **Not run** — no `cabal test` in latest session |
| Render/Authority.hs | wired (stub) | Real parser **not landed** |
| 3 replay gate GAPs | wired | Conatus, Field, Identity contours still have missing trace fields |
| 17 calibration GAPs | wired | Fields with defaults but no spec codomain |

**Pattern**: The project generates extensive design artifacts but struggles to move them from "drafted" to "landed." The closure plan has been in progress since 2026-06-02 with no release cut.

---

## 8. Stubs and Placeholders

27 stub/placeholder references in source code:
- `Self/Field.hs`: `FieldHistory` is a "Phase-4 stub" — still not filled in (Phase 5+).
- `Policy/Metacognition.hs:50`: "placeholder until P8 lands" — metacognitive correction not implemented.
- `Learning/Calibration.hs:152`: "succeed trivially in this stub; real trace" — calibration is stubbed for rules/concepts.
- `Self/Deliberation.hs:383`: placeholder Deliberation when a turn did not run.
- `Semantic/DialogAssembly.hs:693`: placeholder NP preserves surface text (graceful degradation).

**Read**: The system has real stubs in its cognitive and learning subsystems. These are not cosmetic — they are in the metacognition, calibration, and field-history paths that are supposed to produce adaptive behavior.

---

## 9. Goal Contradiction — Structural

The project has two incompatible goals that it has not reconciled:

1. **North Star** (ROADMAP.md top): "a digital subject — stable identity, holds positions, accountable to its own commitments, subjecthood must be felt outward in dialogue."
2. **Final Anchor Doctrine** (ROADMAP.md lower): "algorithmic subject structure does not mean consciousness, personhood, unrestricted general intelligence, or anthropomorphic theater."

The project **retreated** from "subject" to "a bounded evidence package that code can sustain an algorithmic subject structure for meaningful dialogue." The actual output (template text, truncated mid-word, identical blind pairs) satisfies neither goal.

---

## 10. Summary of Skeptical Findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Build/test correctness unproven (not run in latest session) | HIGH | Open |
| 2 | Essence regime triple inconsistency | HIGH | Confirmed |
| 3 | Guard fail-open (ungoverned turns produce evidence) | HIGH | Confirmed |
| 4 | No content quality gate (tests measure routing, not thought) | HIGH | Confirmed |
| 5 | Class I trust-boundary leaks (3 defects) | HIGH | Open from prior audits |
| 6 | Class II serialization asymmetry (4+ defects, no round-trip tests) | HIGH | Open from prior audits |
| 7 | Class III error-provenance loss | MEDIUM | Open from prior audits |
| 8 | Unbounded data structures (3 P0/P1 defects) | MEDIUM | Open from prior audits |
| 9 | Central ADR-0034 not accepted; 5 promotion ADRs not accepted | MEDIUM | Structural |
| 10 | 0/34 Python scripts migrated; no release ever cut | MEDIUM | Structural |
| 11 | 7 test suites wired but not run | MEDIUM | Open |
| 12 | 27 stubs/placeholders in cognitive/learning paths | MEDIUM | Known |
| 13 | Goal contradiction (North Star vs Final Anchor) | LOW | Structural |
| 14 | Documentation-to-code ratio ~2:1 by file count | LOW | Observation |

---

## What Was Missed (per operator's question)

The prior audits (6 of them) covered the plumbing defects well. What they collectively **did not** adequately address:

1. **The system has never been run end-to-end in governed mode and tested for cognitive quality.** Every prior audit checked code paths, not output quality. The one audit that did (2026-06-17) found template text — and that finding has not been acted upon.
2. **The `rrEssenceActive` field is write-only.** This was noted in the 2026-06-17 audit but not flagged as a *write-only field* — it stamps the trace without gating anything, which means the regime metadata is decorative, not functional.
3. **The documentation overhead itself is a risk.** 325 markdown files, 54 closure docs, 48 ADRs — the cost of maintaining this documentation likely exceeds the cost of the code it documents. The anti-rot registry exists because the documentation is rotting.
4. **No release has ever been cut.** The RELEASE_CHECKLIST is "documented but unused." The system is in a perpetual pre-release state with an ever-growing closure plan.
5. **The 3-state taxonomy (drafted/wired/landed) reveals that most of the project's discipline infrastructure is in the "drafted" state.** The enforcement scripts, test suites, and ADRs exist but have not been mechanically verified to pass.

---

## Recommendation

**Stop adding documentation. Start running the system.**

1. Run `cabal build all && cabal test` and fix everything that fails.
2. Run a fresh end-to-end dialogue in governed mode (nix guard available) and evaluate output quality.
3. Fix the essence regime drift — pick one truth (always-on or flag-gated) and make code, docs, and tests agree.
4. Add `decode . encode == id` property tests for all persisted types.
5. Cut a release. Use the RELEASE_CHECKLIST. Find out what breaks.
6. Cap the unbounded data structures.
7. Accept or reject ADR-0034. The central organizational ADR being "proposed" is a structural blocker.
