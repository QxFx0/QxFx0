# ADR Index

**Status:** drafted 2026-06-02; renumbering applied
2026-06-02 (§16) — all 4 collision ADRs in
`proposed/` are now 0034/0035/0036/0041.

**Purpose:** canonical index of every ADR in the
project. Two views: chronological (by number) and
thematic (by phase/contour).

This document is the **disambiguation** layer
between `docs/adr/` (the "landed" ADRs) and
`docs/adr/proposed/` (the "staging" ADRs).

---

## 1. The numbering collisions (resolved in §16)

The `proposed/` folder was created during the
closure plan (2026-05-19 — 2026-06-02) and used
the next-available 4-digit number without
checking `docs/adr/`. This created **three
collisions**:

| Old number | `docs/adr/` (landed) | `docs/adr/proposed/` (staging) |
|------------|----------------------|---------------------------------|
| 0013 | (none) | (TWO ADRs in proposed/: role split + cross-session) |
| 0017 | Post-Commitment Bounded Self-Tuning | Domain-Specific Reasoning Packs |
| 0018 | Deterministic Time Injection in Prepare Stage | Promote Essence Commitment |

The 0013 collision was **internal to proposed/**
(two ADRs sharing the same number); the 0017 and
0018 collisions were **between folders**.

### Resolution (applied 2026-06-02, §16)

The 4 colliding proposed/ ADRs were renumbered
to 0034-0041 (after the landed 0033):

| Old | New | ADR |
|-----|-----|-----|
| 0013-self-core-role-split | **0034**-self-core-role-split | central closure decision |
| 0017-domain-reasoning-packs | **0035**-domain-reasoning-packs | future-work triage stub |
| 0018-promote-essence-commitment | **0036**-promote-essence-commitment | F-14 promotion ADR |
| 0013-cross-session-essence-persistence | **0041**-cross-session-essence-persistence | future-work triage stub |

The remaining 8 proposed/ ADRs keep their
original numbers (0014, 0015, 0016, 0019, 0020,
0021, 0022, 0023) since they don't collide with
main/. **Future-work note**: when these are
accepted into main/, the next contributor
should renumber them into the 0034-0041 range
to maintain the discipline (all closure-plan
additions in 0034+).

### Renumbering procedure (for the record)

The renumbering applied in §16 was 4 `mv`
operations + 50+ `sed` references in
`docs/adr/proposed/*.md` and
`docs/closure/*.md`. The renumbering is **wired**
(documented in this index) but the **landed**
state requires `git add` + a CI test pass that
verifies the cross-references resolve. Until
then, references in the docs that point to
`./0034-self-core-role-split.md` are
**drafted** (intended) and may have stale
references.

---

## 2. Chronological index (by number)

### 2.1 Landed (`docs/adr/`)

| # | Title | Phase | Status |
|---|-------|-------|--------|
| 0001 | Turn Effect State Machine | freeze-0 | landed |
| 0002 | Local Modeled Embedding Backend | freeze-0 | landed |
| 0003 | Datalog Runtime Fact Injection | freeze-0 | landed |
| 0004 | Canonical Shadow Snapshot Parity | freeze-0 | landed |
| 0005 | Replay-Grade Turn Trace Envelope | freeze-0 | landed |
| 0006 | Narrative As Route Hint (Bounded) | freeze-0 | landed |
| 0007 | Dual-Mode Self-Preserving Architecture (Conatus + Adjunction) | Phase 1-2 | landed |
| 0008 | Left ⊣ Right Adjunction as the Dual-Mode Backbone | Phase 3 | landed |
| 0009 | Right-Hemisphere Field Components | Phase 4 | landed |
| 0010 | Salience Controller | Phase 5 | landed |
| 0011 | Deliberation Framework | Phase 8 | landed |
| 0012 | Essence Commitment | Phase 9-10 | landed |
| 0017 | Post-Commitment Bounded Self-Tuning | Phase 9-10 | landed |
| 0018 | Deterministic Time Injection in Prepare Stage | Phase 6 / M6.1 | landed |
| 0025 | Rooted Knowledge Tree | Phase 7-8 | landed |
| 0026 | Phase 7 Calibration Signal | Phase 7 | landed |
| 0027 | Phase 8 External Learning Loop | Phase 8 | landed |
| 0028 | Phase 8 Hardening — Real Transport, Typed Fallback, API Key Redaction | Phase 8 | landed |
| 0029 | Phase 9 Calibration Signal Pipeline — Snapshots and Gated Apply | Phase 9 | landed |
| 0030 | Phase 9 MVP — Autonomous Exploratory Learning | Phase 9 | landed |
| 0031 | Phase 10 — Offline Training Cycle Contract | Phase 10 | landed |
| 0032 | Dialogue Development Contours | Phase 5+ | landed |
| 0033 | Parser Variant B - Local Rule-Based Production Parser | Phase 5+ | landed |

23 ADRs landed as of 2026-06-02.

### 2.2 Proposed (`docs/adr/proposed/`) — after §16 renumbering

| # | Title | Type | Status |
|---|-------|------|--------|
| **0034** | Self/Core Role Split | closure-plan decision | proposed (central) — **renumbered from 0013** |
| **0035** | Domain-Specific Reasoning Packs | future work | triage stub — **renumbered from 0017** |
| **0036** | Promote Essence Commitment | promotion ADR | proposed (F-14) — **renumbered from 0018** |
| 0014 | Multiple Essences per Session | future work | triage stub |
| 0015 | External Essence Summons | future work | triage stub |
| 0016 | Essence-Aware Conatus Weights | future work | triage stub |
| 0019 | Promote Family Divergence | promotion ADR | proposed (F-14, **first candidate**) |
| 0020 | Promote Perspective Operator | promotion ADR | proposed (F-14) |
| 0021 | Promote External LLM Transport | promotion ADR | proposed (F-14) |
| 0022 | Promote Adaptive Mutation | promotion ADR | proposed (F-14) |
| 0023 | Demotion Procedure | procedure ADR | proposed (F-15) |
| **0041** | Cross-Session Essence Persistence | future work | triage stub (older) — **renumbered from 0013** |

12 ADRs in proposed/ as of 2026-06-02 (4 renumbered
in §16 to resolve 3 collisions).

---

## 3. Thematic index (by phase/contour)

### 3.1 Phase-1/2 (SelfBlanket + Conatus)

- **0007** — Dual-Mode Self-Preserving Architecture (Conatus + Adjunction)

### 3.2 Phase-3 (Holistic ⊣ Formal)

- **0008** — Left ⊣ Right Adjunction as the Dual-Mode Backbone

### 3.3 Phase-4 (Field)

- **0009** — Right-Hemisphere Field Components

### 3.4 Phase-5 (Salience)

- **0010** — Salience Controller

### 3.5 Phase-5.5d/e (Field pre-turn + trace observability)

- **0018** (landed) — Deterministic Time Injection in Prepare Stage
- (no separate ADR — folded into 0018)

### 3.6 Phase-6 / M6.1 (Single-source-of-truth Conatus)

- **0018** (landed) — same as 3.5 (the determinism + shared `tiConatusEnergy`/`tiField` refactor)

### 3.7 Phase-7 (Calibration infrastructure)

- **0025** — Rooted Knowledge Tree
- **0026** — Phase 7 Calibration Signal

### 3.8 Phase-8 (Deliberation + Learning)

- **0011** — Deliberation Framework
- **0027** — Phase 8 External Learning Loop
- **0028** — Phase 8 Hardening — Real Transport, Typed Fallback, API Key Redaction

### 3.9 Phase-9 (Calibration pipeline + Autonomous learning)

- **0029** — Phase 9 Calibration Signal Pipeline — Snapshots and Gated Apply
- **0030** — Phase 9 MVP — Autonomous Exploratory Learning

### 3.10 Phase-10 (Essence commitment + Offline training)

- **0012** — Essence Commitment
- **0017** (landed) — Post-Commitment Bounded Self-Tuning
- **0031** — Phase 10 — Offline Training Cycle Contract

### 3.11 Phase-5+ (Dialogue + Parser)

- **0032** — Dialogue Development Contours
- **0033** — Parser Variant B - Local Rule-Based Production Parser

### 3.12 Closure plan (role split + promotion + demotion)

- **0034** (proposed, self-core-role-split) — Self/Core Role Split (the central closure decision)
- **0036** (proposed, promote-essence-commitment) — Promote Essence Commitment
- **0019** (proposed, promote-family-divergence) — Promote Family Divergence
- **0020** (proposed, promote-perspective-operator) — Promote Perspective Operator
- **0021** (proposed, promote-external-llm-transport) — Promote External LLM Transport
- **0022** (proposed, promote-adaptive-mutation) — Promote Adaptive Mutation
- **0023** (proposed, demotion-procedure) — Demotion Procedure

### 3.13 Future work (triage stubs)

- **0041** (proposed, cross-session-essence-persistence)
- **0014** (proposed, multiple-essences-per-session)
- **0015** (proposed, external-essence-summons)
- **0016** (proposed, essence-aware-conatus-weights)
- **0035** (proposed, domain-reasoning-packs)

These 5 are **triage stubs**: short notes that
flag a future-work item. They are not
implementation-ready ADRs.

---

## 4. Cross-references by ADR

### 4.1 ADR-0034 (proposed, self-core-role-split) — the role split

This is the **central** closure-plan ADR. It
defines the 7 boundary rules of `Self/*` vs
`Core/*`:

- **R1** — `Self/*` is canonical-only; no downward writes
- **R2** — `Core/*` supplier must not import canonical-orchestrator writers
- **R3** — `Core/*` observer modules emit into trace only
- **R4** — `Render/*` is the only outbound text producer
- **R5** — `Bridge.ExternalLLM` is the only authority-bearing supplier opt-in by feature flag
- **R6** — `canonical-flag-off` modules are not in the authority path until the flag is flipped
- **R7** — Derived modules must remain regenerable

The 7 rules are enforced by:

| Rule | Script | Test | Doc | Status |
|------|--------|------|-----|--------|
| R1 | `check_architecture.sh` [13]+[17] | `Test.Suite.SelfEssence`, `Test.Suite.SelfPerspective` | `AUTHORITY_MAP.md §3.1` | green |
| R2 | `check_architecture.sh` [14] | `Test.Suite.ArchitectureInvariants.r2SupplierDoesNotImportOrchestrator` | `AUTHORITY_MAP.md §3.2` | green (rev. 3) |
| R3 | `check_architecture.sh` [19] | `Test.Suite.ObserverDiscipline` | `AUTHORITY_MAP.md §3.3` | green (rev. 2) |
| R4 | `check_architecture.sh` [18] | `Test.Suite.RenderDialogueCoverage` | `GF_AUTHORITY_SUBSET.md §2` | green |
| R5 | `check_architecture.sh` [15] | `Test.Suite.RenderAuthorityStub` | `ADR-0021`, `AUTHORITY_MAP.md §6` | green |
| R6 | `check_architecture.sh` [20] | `Test.Suite.SelfEssenceCommit`, `Test.Suite.SelfEssence`, `Test.Suite.PromotionFlagDiscipline` | `SELF_LAYER_STATUS.md §2`, `PROMOTION_PLAYBOOK.md §3` | green |
| R7 | `check_architecture.sh` [16] + `check_generated_artifacts.sh` | `Test.Suite.RegenerableDerived` | `AUTHORITY_MAP.md §3.5` | green (rev. 2) |

See `docs/closure/ENFORCEMENT_MATRIX.md` for
the full matrix.

### 4.2 The 5 promotion ADRs (0036, 0019-0022 proposed)

Each promotion ADR follows the 4-gate discipline
in `docs/closure/PROMOTION_PLAYBOOK.md`:

- **G1 (Pre-flight)** — the contour is canonical-flag-off
- **G2 (Gate)** — the runtime path is exercised in shadow
- **G3 (Release)** — the flag flips; the env var is preserved
- **G4 (Post-flight)** — observability confirms no regression

The 5 promotion ADRs are:

- **0036** (proposed) — Promote Essence Commitment (essence-commitment-enabled flag)
- **0019** (proposed) — Promote Family Divergence (`familyDivergenceEnabled` flag at `Cascade.hs:74`; **first candidate** per playbook)
- **0020** (proposed) — Promote Perspective Operator (`QXFX0_PERSPECTIVE_OPERATOR_ENABLED` flag, **not yet in code** per AGENTS.md P4)
- **0021** (proposed) — Promote External LLM Transport (`QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED` flag)
- **0022** (proposed) — Promote Adaptive Mutation (`QXFX0_ADAPTIVE_MUTATION_ENABLED` flag, gated by bounded `ssAdaptiveMutationLog`)

### 4.3 The demotion procedure (0023 proposed)

- **0023** (proposed) — Demotion Procedure (F-15) — the
  sister of the 5 promotion ADRs. Defines the
  D1-D4 conditions under which a canonical
  contour is demoted back to canonical-flag-off.

### 4.4 The 5 freeze-0 ADRs (0001-0006 landed)

These are the pre-closure architecture ADRs:

- 0001-0005 are the runtime + replay foundation
- 0006 is the narrative-as-route-hint boundary

### 4.5 The 7 phase ADRs (0007-0012 landed)

These are the canonical contour definitions:

- 0007 → Conatus (Phase 1-2)
- 0008 → Adjunction (Phase 3)
- 0009 → Field (Phase 4)
- 0010 → Salience (Phase 5)
- 0011 → Deliberation (Phase 8)
- 0012 → Essence (Phase 9-10)

Plus 0017 (Post-Commitment Bounded Self-Tuning)
and 0018 (Deterministic Time Injection) are
extensions to the phase ADRs.

### 4.6 The 5 phase-7+ ADRs (0025-0029 landed)

The phase-7 (calibration) through phase-9
(calibration pipeline) ADRs:

- 0025 → knowledge tree
- 0026 → Phase 7 calibration signal
- 0027 → Phase 8 external learning loop
- 0028 → Phase 8 hardening
- 0029 → Phase 9 calibration pipeline

### 4.7 The 4 phase-9+ ADRs (0030-0033 landed)

- 0030 → Phase 9 autonomous exploratory learning
- 0031 → Phase 10 offline training cycle
- 0032 → Dialogue development contours
- 0033 → Parser Variant B (local rule-based)

---

## 5. Promotion status (as of 2026-06-02)

Per `docs/closure/AUTHORITY_MAP.md §6`, the
5 promotion candidates are all in
**canonical-flag-off** state:

| Contour | Flag | Status | First promotion candidate? |
|---------|------|--------|----------------------------|
| Essence | `essenceCommitmentEnabled` | off | no (depends on calibration data) |
| Family Divergence | `familyDivergenceEnabled` | off | **YES** (per playbook) |
| Perspective Operator | `QXFX0_PERSPECTIVE_OPERATOR_ENABLED` | off (flag not in code) | no (requires flag addition) |
| External LLM | `QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED` | off | no (depends on Bridge hardening) |
| Adaptive Mutation | `QXFX0_ADAPTIVE_MUTATION_ENABLED` | off | no (depends on production data) |

The **first candidate** is ADR-0019 (Family
Divergence): the flag is already in code at
`src/QxFx0/Core/TurnRouting/Cascade.hs:74` as
`familyDivergenceEnabled = False` literal.

The promotion playbook (`docs/closure/PROMOTION_PLAYBOOK.md`)
defines the 4 gates (G1-G4) for this candidate.

---

## 6. Honest limits

- This index is **read-only**: it does not
  resolve the 2 numbering collisions (§1). The
  fix is renumbering proposed/ to 0034-0045.
- The "phase" tags in §3 are based on the
  AGENTS.md landed-phase list. They reflect
  the **status at landing**; some ADRs were
  refined in later phases (e.g. 0009 was
  refined by 0008's caller-mapping fix in
  Phase 8 Package D).
- The 5 triage-stub ADRs (§3.13) are not
  implementation-ready. They are placeholders
  for future-work items.
- The 4 closure-plan role-split ADRs (0013,
  0018-0023 proposed) are **not landed**;
  they are the closure-plan's central
  decisions. Landing the first promotion
  (ADR-0019) is the next contributor's
  S-sized task.
- This index does **not** claim exhaustiveness
  of the cross-references. The
  `ENFORCEMENT_MATRIX.md §4.1` table has the
  per-rule cross-references; this index has
  the per-ADR view.
