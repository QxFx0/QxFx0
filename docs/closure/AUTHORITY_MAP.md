# Authority Map (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 1)
- **Date**: 2026-06-02
- **Refines**: `docs/AUTHORITY_BOUNDARY.md` (2026-05-26), AGENTS.md, ADRs 0007–0012
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/adr/proposed/0034-self-core-role-split.md` (proposed)
  - `docs/closure/TECH_DEBT_CLOSURE_INDEX.md`

## 0. Why this document exists

The freeze-0 `AUTHORITY_BOUNDARY.md` (2026-05-26) classifies paths as
authority / supplier / derived / legacy observer. It is correct at the
**path** level (which command or which file is on the runtime
perimeter), but it is silent on the **module** level inside
`src/QxFx0/Self/*` and `src/QxFx0/Core/Consciousness/*`. The closure
plan needs a per-module map to make the role split auditable.

This document extends the boundary to the per-module level and
adds a fifth class, `canonical-flag-off`, for modules that are
landed, type-checked, tested, gated by a `QXFX0_*_ENABLED` flag
defaulted to `False`, and therefore do not currently participate in
the runtime decision path even though they are production-quality
code.

## 1. Authority classes

| Class | Definition | Can write to kernel / semantic state? | Can drive runtime output? |
|---|---|---|---|
| **canonical** | Decides or validates runtime, release, governance, replay, or persistence behaviour. | yes (its own slice) | yes |
| **canonical-flag-off** | Production-quality, fully tested, but the only call site is gated by a feature flag defaulted to `False`. Becomes canonical when the flag is flipped; loses canonical status if the flag is removed without promotion. | no (current call site is `Nothing`) | no (currently) |
| **supplier** | Provides raw material, source data, or helper transforms. Reads canonical state but never writes it. | no | no |
| **derived** | Generated from canonical sources (e.g. `Lexicon.Generated`). Must stay in sync with sources; can be regenerated. | no | no (deterministic of sources) |
| **observer** | Reads canonical state, runs heuristics, emits only into trace/diagnostic channels. No production output path. | no | no |
| **legacy** | Exists for compatibility, comparison, or historical evidence. Not on the canonical path. | no | no |

## 2. Canonical runtime authority (per the freeze-0 path)

Inherited unchanged from `AUTHORITY_BOUNDARY.md §1` and `ARCHITECTURE.md`:

- `qxfx0-main --serve-http`
- `app/CLI/Http.hs`, `app/CLI/Http/Runtime.hs`
- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- Replay trace contract in `docs/interop/README.md`

## 3. Self-layer authority map (per module)

The `QxFx0.Self.*` subtree is the **pure self-layer of the dual-mode
runtime** (AGENTS.md, Phases 1–10). Within it, the closure plan
demands per-module status. The table below is the result of reading
every `Self/*.hs` module against ADRs 0007–0012 and the actual call
sites in `Core/TurnPipeline/*`.

| Module | Phase | ADR | Role | Notes |
|---|---|---|---|---|
| `Self.Adjunction` | 3 | 0008 | **canonical** | `Holistic ⊣ Formal` algebra. Consumed by `Deliberation` only. |
| `Self.Blanket` | 1 | (implicit) | **canonical** | `computeSelfBlanket`, `checkInitialBlanket`. Guard for `IdentityRupture`. |
| `Self.Conatus` | 2 | 0007 | **canonical** | `computeConatusEnergy`, `computeConatusGradient`. Hard gate in `Route/Render.buildLocalRecoveryPlan` (see §6). |
| `Self.Deliberation` | 8 | 0011 | **canonical** | `reconcile` morphism. `holisticProposal` / `formalProposal` constructors. Single-output discipline. |
| `Self.Essence` | 9–10 | 0012 | **canonical** | Law-driven Essence commitment (`shouldCommit`/`commit`/`validatePlan`/`EssenceRupture`), unconditionally active since 2026-05-19. The `essenceCommitmentEnabled` flag (ADR-0012 §10.1) was **never implemented**; `rrEssenceActive = True` stamps the regime. Reclassified from `canonical-flag-off` to `canonical` via Policy A (2026-06-17, `ESSENCE-REGIME-RECONCILE.md`). **Scope limit**: structural/runtime law only — not M6-FELT evidence until SLICE-012 + a felt-evidence gate land. |
| `Self.Field` | 4 | 0009 | **canonical** | Five-component `Field`. Read by `Salience.computeSalience`; threaded by M6 single-source-of-truth. |
| `Self.Invariants` | (continuous) | — | **canonical** | Pure property assertions over Self/*. |
| `Self.Perspective` | 4-P4 | (0009 addendum) | **canonical-flag-off** | `PerspectiveOperator` (per AGENTS.md P4); `PerspectiveRegistry` is the canonical versioned lineage, `PerspectiveProjection` is what replay/render may consume. Replays/ renders **must not** read `PerspectiveRegistry` directly. Flag status: see `docs/closure/SELF_LAYER_STATUS.md §4`. |
| `Self.Salience` | 5 | 0010 | **canonical** | `computeSalience`, `salienceVerdict`. Gates narrative in `ConsciousnessLoop.applySalienceToNarrativeFragment`. `chooseBranch` is **dead-API-by-design** until pipeline refactor. |
| `Self.Types` | (continuous) | — | **canonical** | Type definitions and shared newtypes. |

**Rule of thumb:** every `Self/*.hs` module is canonical, canonical-flag-off,
or canonical-observer (`Self.Invariants`). Nothing in `Self/*` is
supplier or legacy.

## 4. Core/Consciousness/* authority map

`QxFx0.Core/Consciousness/*` is the **narrative content supplier** of
the runtime. It owns the kernel that produces text-shaped narrative
fragments. It does not make family or recovery decisions; those
flow through `Self.*`. This is the role split the closure plan pins.

| Module | Role | Notes |
|---|---|---|
| `Core.Consciousness` | **supplier** | `ConsciousnessModel`, `initialConsciousness`. Output is `ConsciousnessNarrative` — text-shaped, gated by `Self.Salience` before reaching the prompt. |
| `Core.ConsciousnessLoop` | **supplier** | `runConsciousnessLoop`, `applySalienceToNarrativeFragment` (the salience gate, in this file). The loop itself is supplier; the gate is canonical. |
| `Core.BackgroundProcess` | **supplier** | `runBackgroundCycle` — emits `SurfacingEvent`. Read by `ConsciousnessLoop`; never writes kernel state. |
| `Core.Consciousness.Kernel` | **supplier** | `kernelPulse`, desires/skills/ontology. Heuristic-keyword narrative generator. The closure plan's Package 2 will reduce this to a thin **semantic-aware** kernel that emits a typed observation, not a text fragment. |
| `Core.Consciousness.Kernel.Init` | **supplier** | Initial kernel state. |
| `Core.Consciousness.Kernel.Pulse` | **supplier** | The keyword-conditional pulse. This is the file where the closure plan's Package 2 starts its rewrite. |
| `Core.Consciousness.Kernel` (other) | **supplier** | (cataloguing per sub-file deferred to `SELF_LAYER_STATUS.md` follow-up). |
| `Core.DreamDynamics` | **observer** | Reads kernel + Field, runs offline dream dynamics. Emits into trace only. |
| `Core.MeaningGraph` | **supplier** | `MeaningGraph` data structure, populated by `TurnPipeline.Effects` from observation. Read by Kernel and Trace. |
| `Core.TurnPipeline*` | **canonical** | The actual turn-pipeline orchestrator. Reads `Self/*` verdicts, calls `Core.Consciousness*` suppliers, persists. This is where the role split is most visible. |
| `Core.Guard*` | **canonical** | Recovery, identity, salience guards. |
| `Core.Legitimacy*` | **canonical** | Legitimacy scoring. |
| `Core.TurnModulation*` | **canonical** | Per-turn modulation. |
| `Core.Observability*` | **canonical** | Trace assembly. |
| `Core.R5Dynamics` | **supplier** | R5 algorithm (deferred decision). |
| `Core.Spectral*` | **supplier** | Spectral analysis. |
| `Core.TopicTransition*` | **supplier** | Topic transition logic. |
| `Core.Proposition*` | **supplier** | Per-proposition admission; reads kernel proposals. |
| `Core.PipelineIO*` | **supplier** | Pipeline IO. |
| `Core.PrincipledCore*` | **supplier** | (out of scope; deferred). |
| `Core.Atom*` | **supplier** | Atom admission. |
| `Core.IdentitySignal*` | **supplier** | Identity signal emission. |
| `Core.FamilyAdmission*` | **supplier** | Family admission. |
| `Core.Ego*` | **canonical** | Ego state management. |

**Per-file classification complete:** the file-by-file split is in
`docs/closure/SELF_LAYER_STATUS.md` §3. The above is the
**per-subsystem** summary.

## 5. Render, Bridge, Runtime, Governance, Semantic — supplier map

| Subsystem | Role | Notes |
|---|---|---|
| `Render/*` | **canonical** | Surface rendering. The only producer of outbound text. |
| `Bridge.StatePersistence` | **canonical** | Persists `SystemState`. |
| `Bridge.ExternalLLM` | **supplier** (feature-gated) | LLM transport. Default off (`QXFX0_LLM_TRANSPORT`). |
| `Bridge.SQLite/*` | **canonical** | SQLite persistence. |
| `Runtime.*` | **canonical** | Runtime orchestrator. |
| `Runtime.Session.Bootstrap` | **canonical** | Session bootstrap. |
| `Governance.*` | **canonical** | Governance state machine. |
| `Semantic.*` | **canonical** | Semantic state, propositions, lexicon, sense extraction. |
| `Semantic.Lexicon.Generated` | **derived** | Generated lexicon (84 970 LOC). Deterministic of TSV sources. |
| `Evaluation.*` | **observer** | Offline evaluation harness. |
| `Learning/*` | **supplier-flag-off** | Calibration signals. Multiple flags. See `SELF_LAYER_STATUS.md §5`. |
| `Policy.*` | **canonical** | Policy modules. |
| `Internal/*` | **supplier** | Internal helpers. |
| `Legal/*` | **canonical** | Legal adapter. |
| `Resources/*` | **derived** | Bundled resources. |
| `Types/*` | **canonical** | Type definitions. |
| `ExceptionPolicy` | **canonical** | Exception hierarchy (including `EssenceRupture` from ADR-0012). |

## 6. Flag-off features (the canonical-flag-off class)

These are landed, fully tested, but not currently active. Each one
is a candidate for promotion (flip default to `True`) **after** the
closure plan's role split.

| Feature | Flag | Default | Source | Promotion criteria |
|---|---|---|---|---|
| Essence commitment | ~~`QXFX0_ESSENCE_COMMITMENT_ENABLED`~~ (never implemented; historical) | n/a | `Self.Essence`, ADR-0012/0036 | **Promoted (Policy A, 2026-06-17)**: law-driven, `rrEssenceActive = True`. The flag/env-var were never built. Structural law only; felt-evidence (G1–G3 corpus, angst calibration) remains the path to any M6-FELT claim. |
| Family divergence | `familyDivergenceEnabled :: Bool` (in `TurnRouting.routeFamily`) | `False` | `Self.Adjunction` / `routeFamily`, ADR-0011 §5.3, Package D | Adjunction caller mapping audit by Package B/C/D. Already landing progressively. |
| External LLM transport | `QXFX0_LLM_TRANSPORT` | off | `Bridge.ExternalLLM` | Provider keys provisioned + rate-limit discipline + cost gates + replay-trace discipline for LLM calls. **Closure plan's Package 2/3 make this more concrete.** |
| Adaptive mutation | `QXFX0_ADAPTIVE_MUTATION` (or similar) | per AGENTS.md "weak acknowledgement phrases are observational and must not trigger strong mutation without a shared `AdaptiveMutationRecord`" | `Core.AdaptiveMutation` (if exists) | The record must be replay-visible; see Package 3. |

The closure plan's Package 10 (`SELF_LAYER_STATUS.md`) commits to:
1. Each flag-off feature carries a **promotion ADR** in `docs/adr/proposed/` before being flipped.
2. Each flag-off feature has a **demotion ADR** if the project decides not to pursue it.
3. Until then, **no marketing claim** that the feature is "core runtime logic".

## 7. Boundary rules

These rules extend `AUTHORITY_BOUNDARY.md §4` (Freeze-0 Rules) for
the per-module level:

1. **Self/* writes are canonical-only.** A new module under `Self/*` is canonical by construction. Adding one requires a phase-ADR or closure-plan reference.
2. **Core/* is supplier or canonical-orchestrator.** A new `Core/*` module must declare its role in its module Haddock. Supplier modules **must not** import `Core.TurnPipeline*` or any other canonical-orchestrator writer.
3. **Render/* is the only outbound text producer.** A new Render/* module may read supplier/canonical state but must not introduce a new outbound text path bypassing `Route/Render.buildTurnArtifacts`.
4. **Bridge.ExternalLLM is the only authority-bearing supplier that is opt-in.** Any other opt-in supplier (e.g. future `Bridge.VectorDB`) must follow the same flag + replay-trace discipline.
5. **canonical-flag-off modules are not in the authority path** until the flag is flipped. Their tests are non-canonical regression locks.
6. **observer modules cannot gain canonical status without a phase-ADR.** A new "dream" or "intuition" feature that wants to drive runtime output must be promoted to canonical, not silently route through the observer back door.
7. **derived modules must remain regenerable.** `Lexicon.Generated.hs` is the largest derived module. Any change to its generation pipeline must keep regeneration deterministic and idempotent.

## 8. Persisted SystemState field authority map

Inherited from `AUTHORITY_BOUNDARY.md §3` and extended. The closure
plan's Package 1 reads each `ss*` field and classifies it. Full table
in `docs/closure/SYSTEM_STATE_AUTHORITY.md` (follow-up). Highlights:

- `ssEssence :: Essence` — **canonical** (law-driven, unconditionally active
  since 2026-05-19; reclassified from `canonical-flag-off` via Policy A
  2026-06-17).
- `ssIdentityClaims`, `ssOrbitalMemory` — **canonical** (they are the carriers of identity).
- `ssSemanticAnchor` — currently persisted for **compatibility/observability**; demoted on non-authoritative restore; not yet restart-authority. Closure plan's Package 2 promotes this to typed semantic commitments.
- `ssLastTurnDecision` — persisted but `whole-field authority is NOT PROVEN` (`AUTHORITY_BOUNDARY.md §3`); under `SLICE-TD-001` review. Closure plan's Package 6 (test audit) lists this as a candidate for `rewrite-required` test class.
- `ssTruthContractStatus` — **canonical** (non-authoritative rebuild gate).
- `ssGovernanceHistory` — **canonical** (governance restoration source).
- `ssShadowVetoState`, `ssGovernanceProjection`, `ssPerspectiveRegistry` — **derived** (rebuilt from canonical history on authoritative load).
- `ssCalibrationLog`, `ssCalibrationSnapshots`, `ssAdaptiveMutationLog` — **canonical-flag-off** (learning/mutation not active by default; see `SELF_LAYER_STATUS.md §5`).

## 9. What this document does **not** claim

- It does **not** say the role split is complete. Several `Core/*`
  modules still write to `SystemState` and may be promoted/demoted
  by future phase-ADRs (the closure plan's Package 6 test audit
  will surface these).
- It does **not** retroactively reclassify any `Self/*` module. The
  Self layer's purity is preserved.
- It does **not** bind any module's runtime behaviour. This is a
  classification document. Behavioural changes go through
  phase-ADRs.

## 10. Open questions for the closure index

1. Should `Core.Consciousness.Kernel.Pulse` be reclassified as
   `observer` instead of `supplier` after Package 2 lands? Yes,
   if Package 2 replaces keyword heuristics with typed semantic
   observation ingestion. **Defer to Package 2 closure.**
2. Should `Self.Perspective` be split into `Self.Perspective.Registry`
   and `Self.Perspective.Operator` per AGENTS.md note? Yes, the
   current `Self.Perspective.hs` already separates them. **No
   action needed; documentation pass only.**
3. Is `Bridge.ExternalLLM` ever a canonical runtime authority? Per
   the closure plan's Package 2, **no**: it remains supplier-flag-off
   until the typed-commitment contract includes "LLM observation
   is a typed event, not a free-form answer".

## 11. Acceptance criteria for Package 1 closure

Package 1 is closed when:

- [x] `docs/closure/AUTHORITY_MAP.md` (this file) exists and is
      consistent with `docs/AUTHORITY_BOUNDARY.md` (2026-05-26).
- [ ] `docs/adr/proposed/0034-self-core-role-split.md` (proposed) exists and
      carries the role split decision with no per-module
      contradiction.
- [ ] `docs/closure/SELF_LAYER_STATUS.md` completes the per-file
      classification in `Core/*`.
- [ ] `docs/closure/SYSTEM_STATE_AUTHORITY.md` completes the
      per-field classification.
- [ ] `scripts/check_architecture.sh` is updated to enforce the
      boundary rules §7 (1–7) at CI time.
- [ ] No new `Core/*` module is added without a module-level
      role declaration in its Haddock.
