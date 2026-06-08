# Track I Closure: Remaining Work (P1 → P8 → P0 → P6' → P4)

**Goal**: Eliminate systemic gaps between philosophical/mathematical rhetoric and
implementation. Every component that claims influence on behaviour must actually
influence behaviour, and every influence must be observable.

**Constraints** (I1–I5 unchanged):
- I1: Determinism — no wallclock/random on turn path.
- I2: Fail-closed — all behaviour behind default-off flags; replay-gate green.
- I3: Append-only governance — state changes via typed payload + schema migration.
- I5: Anti-rot — every wired consumer has a test that fails if disconnected.

---

## P1 — Conatus Gate [HIGHEST PRIORITY]

**What**: `ConatusEnergy` is computed, traced (`trcConatusEnergy`), has
`conatusGateFired` — but **does not influence family selection**. The gate flag
exists in trace but is never read by `runFamilyCascade` or `routeFamily`.
Rhetoric promises "self-preservation"; implementation computes a number and
ignores it.

**Requirements**:
1. `runFamilyCascade` (`Cascade.hs:52-106`) must read `salienceDriver` and/or
   `conatusGateFired` from `Salience` to restrict high-risk families when
   energy is low:
   - `conatusGateFired == True` OR `ceScalar < lowEnergyThreshold` →
     prohibit `CMConfront`, `CMHypothesis`, `CMDistinguish`.
   - Low energy → allow only `CMContact`, `CMAnchor`, `CMRepair` (restorative).
2. Add `lowEnergyThreshold` to `Conatus` module (calibrated default, e.g. 3.0).
3. Wire check into `applyGuardGating` or as a new stage in the cascade,
   before `familyAfterDoubt`. Existing `salienceDriver == DrivenByConatusGate`
   in `applyPrincipledFamilyModulated` is a start — extend to cover all
   cascade entries.
4. **Anti-rot test**: property test that when `ceScalar < threshold`,
   output family is always restorative; when `ceScalar >= threshold`,
   no restriction.

**Files**:
- `src/QxFx0/Core/TurnRouting/Cascade.hs:52-106` — cascade stages
- `src/QxFx0/Core/TurnRouting.hs:125-147` — `routeFamilyWithSelfVerdict`
- `src/QxFx0/Self/Conatus.hs` — add `lowEnergyThreshold`
- `src/QxFx0/Self/Salience.hs` — `DrivenByConatusGate` already exists (L163)
- `test/Test/Suite/` — new anti-rot suite

**Counterfactual**: `conatusGateFired = True` but family unchanged = gap closed.

---

## P8 — Audit Trail Visibility

**What**: Internal signals are computed but invisible in trace. An operator
watching a turn sees input → output with no explanation of *why* a decision
was made. `trcCognitiveSignals` (WP-S) is a good start; extend to cover all
active WP signals.

**Requirements**:

Add to `TurnReplayTrace` (`Types/TurnProjection.hs:54`):

| Field | Type | Source | Notes |
|---|---|---|---|
| `trcDoubtScore` | `Double` | `tiDoubtScore` | Already computed, not traced |
| `trcEpisodicCount` | `Int` | `length tiRetrievedEpisodes` | How many episodes were retrieved (or 0 if flag off) |
| `trcContentSaliencyClusters` | `Int` | spectral cluster count | Number of clusters found (or -1 if inactive) |
| `trcAffectAtmosphere` | `(Double, Double)` | `fieldAtmosphere` | (valence, arousal) |
| `trcAffectDecoupled` | `Bool` | `affectDecoupledActive` | Whether decoupled mode was active |
| `trcMood` | `Double` | `ssMood` from SystemState | Persistent mood signal |
| `trcDerivedInferenceCount` | `Int` | `length (deriveAtoms ...)` | How many derived atoms were added (or -1) |
| `trcUserModelTopIntent` | `Text` | `dominantIntent` | Rendered name of max-belief intent |
| `trcUserModelTopProb` | `Double` | `maxBelief` | Posterior probability of max intent |
| `trcFamilyDivergenceKind` | `Text` | `"holistic" | "formal" | "tied"` | Which branch won |
| `trcDeliberationRule` | `Maybe Text` | already exists | Ensure populated in all paths |

All fields must be populated even when the corresponding WP is flag-off
(default values: 0.0, 0, -1, False, ""). This makes counterfactual behaviour
visible.

**Anti-rot test**: One property per field — when flag is on, field is non-default;
when flag is off, field is default. Fails if wire is disconnected.

**Files**:
- `src/QxFx0/Types/TurnProjection.hs` — add fields
- `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs` — populate

---

## P0 — Staged Flag Promotion

**What**: 9 WP features are behind default-off flags. They compile, have tests,
but produce zero behavioural change. Each must be promoted individually with
manual output diff review.

**Staging order** (lowest risk first):

| Stage | Flag | Risk | Diff review |
|---|---|---|---|
| 1 | `episodicRecallActive` | Zero — only affects routing when doubt ≥ 0.75, and doubt is default-off. Still: verify no family changes on clean turns | 50 input/output pairs |
| 2 | `doubtLoopActive` | Low — overrides to CMClarify only when doubt ≥ 0.75 AND no recent system decision. Verify suppression works | 30 turns with seeded doubt |
| 3 | `contentSalienceActive` | Medium — threshold=0.1 uncalibrated, may cut topics. Manual review of cluster assignments | 100 turns, check topic coverage |
| 4 | `affectDecoupledActive` | Medium — `moodWindowTurns=12` may give inertial affect. Verify mood drifts appropriately | 50-turn window, check mood trend |
| 5 | `familyDivergenceEnabled` | Medium — changes family when holistic bias > floor. Verify divergence is semantically meaningful | 100 turns with holistic bias |
| 6 | `derivedInferenceActive` | Low — only active when atom counts match rule conditions. Verify no false positives | 100 turns |
| 7 | `essenceCommitmentEnabled` | Medium — changes state machine. Verify no spurious ruptures | 500-turn replay |
| 8 | `externalLLMActive` | Blocked (needs corpus F-09/F-10) | — |
| 9 | `episodicRecallActive` + `doubtLoopActive` combo | Medium — both on: doubt→CMClarify suppressed by recent system decision | 100 turns |

**Per-stage deliverables**:
- Flip flag default to `True`
- Run full test suite + replay gate
- Manual diff of N input/output pairs
- Update ADR proposing the promotion
- Update `docs/anti_rot_registry.tsv`

**Files**: one `Bool` definition per WP module, e.g.:
- `Memory/Episodic.hs:61` — `episodicRecallActive`
- `ConsciousnessLoop.hs:148` — `doubtLoopActive`
- `Spectral.hs` — `contentSalienceActive`
- `Self/Field.hs` — `affectDecoupledActive`
- `Core/TurnRouting.hs:140` — `familyDivergenceEnabled`
- `Semantic/Logic.hs:83` — `derivedInferenceActive`

---

## P6' — Field-Aware Rendering

**What**: Field (5 components) is computed, traced, but **does not influence
surface realisation**. Rhetoric promises Field-driven modulation of tone,
confidence markers, lexical choice. Implementation: 5 floats → JSON → /dev/null.

**Requirements**:

1. `TurnRender.Strategy` (`TurnRender/Strategy.hs`) accepts `Field` snapshot:
   - `fieldConfidence` → epistemic hedges ("maybe", "I think", bare assertion
     vs hedged). Low confidence inserts `Hedge` modifier before verb phrase.
   - `fieldAtmosphere` → lexical valence/arousal. Negative valence → softer
     modals ("could", "might"); high arousal → shorter sentences.
   - `fieldConsolidation` → discourse connectors. High consolidation → more
     "also", "furthermore", "as previously discussed"; low → fresh-start
     markers.
   - `fieldCounterfactual` → alternative markers. High → "alternatively",
     "another way", "however".

2. Modifiers operate on `ResponseMeaningPlan` or `RenderPlan` — the
   what-to-say layer is unchanged; only how-to-say (surface realisation) is
   modified.

3. Default-off flag `fieldAwareRenderingActive :: Bool` in `Self/Field.hs`.

4. When flag is off, behaviour is identical to current (no hedges, no
   atmosphere-driven lexical choice).

**Anti-rot test**: For each Field component, a property test: when component
is at min vs max, the output text contains expected markers (hedge absent vs
present, soft vs strong modals).

**Files**:
- `src/QxFx0/Render/Text.hs` — hedge modifier
- `src/QxFx0/Core/TurnRender/Strategy.hs` — accept Field
- `src/QxFx0/Core/TurnRender.hs` — thread Field from routing
- `src/QxFx0/Self/Field.hs` — flag

---

## P4 — Holistic/Formal Context Split

**What**: `routeFamilyWithSelfVerdict` (`TurnRouting.hs:125-147`) builds both
`holisticPlan` and `formalPlan` with **identical context** — both see the same
`preparedField`, `salienceStyle`, `routingSalience`. The adjunction is
empirically `λx. x`. Rhetoric promises two modes with different epistemic
access; implementation has one mode called twice.

**Requirements**:

1. Holistic proposal gets access to **episodic memory** + full **Field** +
   **semantic scene** (broad context).
2. Formal proposal sees only **commitment ledger** + **truth contract status**
   (narrow, verifiable context). No episodic, no atmosphere, no salience bias.
3. The two proposals will genuinely differ because they have different
   information — not because of different functions called on identical input.
4. `reconcile` then selects which proposal's family/style/force to use.
5. Default-on flag `holisticFormalContextSplitActive` in `Self/Adjunction.hs` (activated 2026-06-05).

**This enables generate-verify without stochastic generation**: Holistic
produces a proposal from full context; Formal verifies it against commitment
constraints. When they disagree, deliberation chooses.

**Anti-rot test**: Feed same `SystemState` with and without flag; verify that
flag-off gives identical plans (current behaviour) and flag-on gives different
plans when episodic memory contains relevant commitments.

**Files**:
- `src/QxFx0/Core/TurnRouting.hs:173-186` — plan construction
- `src/QxFx0/Self/Adjunction.hs` — flag + context split
- `src/QxFx0/Self/Deliberation.hs` — `reconcile` signature

---

## P7 — GF Controlled Variation (deferred to M3)

**What**: GF `lin` produces one surface form per tree. For Holistic/Formal
context split to produce genuinely different outputs, we need variation.
Beam search over GF alternatives selected deterministically by hash of context.

**Blocker**: Requires corpus F-09/F-10 for meaningful calibration.

**Requirements** (for when blocker lifts):
1. `QxFx0.Runtime.GF.Map` — expose GF alternative count per tree.
2. Deterministic select: `hash(context) mod n` picks alternative.
3. I1 preserved: same context → same hash → same alternative.
4. Anti-rot test: alternative selection is deterministic given context.

---

## Transition Diagram

```
P1 (Conatus gate)
  │  ─── closes main rhetoric gap: self-preservation becomes observable
  ▼
P8 (Audit trail)
  │  ─── makes P1 + all future WP behaviour visible in trace
  ▼
P0 staged (flags on)
  │  ─── dormant functionality becomes live, calibrated per flag
  ▼
P6' (Field→Render)
  │  ─── Field stops being decorative, starts shaping output
  ▼
P4 (Holistic/Formal split)
  │  ─── dual-mode becomes real: different context → different proposal
  ▼
P7 (GF alternatives)
     ─── variation for generate-verify (deferred to M3)
```

Each step is independently verifiable: no step depends on later steps.
P4 and P7 are blocked on corpus; P1, P8, P0, P6' are not.
