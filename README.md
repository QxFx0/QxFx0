# QxFx0

Deterministic, spec-first dialogue runtime for Russian reasoning workflows.

QxFx0 is an open-source alternative to purely probabilistic chat stacks: routing is typed and explicit, output is grammar-constrained, and release decisions are gate-driven with auditable evidence.

Current shape: the runtime now includes a canonical P5 governance spine, explicit epistemic-status classification (`authoritative` / `advisory` / `degraded` / `fallback` / `observational-only` / `non-driving`), a sense-continuation bridge inside the planning path, and hardened SQL→GF→datalog truth seams.

## Why This Project Exists

Most conversational systems optimize for plausibility. QxFx0 optimizes for:
- reproducible behavior under explicit contracts
- traceable decisions (family/force/state transitions)
- safe degraded behavior without hidden retries
- verifiable release gates instead of “it seems to work”

If you need deterministic dialogue infrastructure with strict operational semantics, QxFx0 is built for that.

## What Is Implemented

- Typed semantic routing (`CanonicalMoveFamily`, `IllocutionaryForce`) via `Semantic.Logic`
  and a guarded cascade (parser lock, meaning-graph strategy hints, principled pressure,
  threshold intuition flashes, identity/guard gating)
- Multi-layer runtime: Haskell core + SQLite persistence + GF surface generation
- Experimental scientific modules (`Core.GameTheory`, `Core.Spectral`, `Core.Bayesian`)
  compile as `other-modules` for the extended contour; they are not part of the PROD
  turn pipeline
- Constitutional readiness contour (Nix policy checks)
- CLI runtime and HTTP sidecar with live-session continuity contract
- Gate contract for release decisions (`scripts/ci_gate_contract.sh`)
- Lexicon pipeline with collision/quality controls and generated artifacts sync
- Dialogue development emits bounded shared adaptive mutation records via `SystemState.ssAdaptiveMutationLog`; legacy dialogue JSON field names are still decoded for compatibility.
- P4 `PerspectiveOperator` builds governed, versioned perspective lineage in `SystemState.ssPerspectiveRegistry` and exposes only safe `PerspectiveProjection` in replay traces.
- P5 governance spine provides canonical append-only history, typed governed payloads, rebuildable projections, policy/version surface, and machine-readable epistemic status classification.
- Sense bridge (`QxFx0.Semantic.Sense`) converts utterance-level meaning into bounded adjacent response planning, feeding `ResponseMeaningPlan` and `ResponseContentPlan` without creating a parallel semantic stack.
- SQL/GF/datalog truth chain is checked by generation and drift gates, with explicit fallback semantics for unresolved lexemes and advisory shadow contours.

## Current Maturity

- Core release contour: `PASS_BY_INDIVIDUAL_GATES` (low-RAM verified)
- Scientific closure: `PASS_BY_INDIVIDUAL_GATES` with Agda/Nix reproducibility checks passing
- Extended/high-memory contour: deferred to high-memory runners
- Canonical evidence: `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
- CI/release profile: `docs/CI_PRODUCTION_PROFILE.md`
- Current operational rule: fallback/degraded/advisory states are now surfaced explicitly rather than silently masquerading as success
- Current architectural rule: R5 core remains static; dynamicity is policy-envelope-only and governed through P5

## Status Snapshot (2026-05-22)

Security/reliability hardening (WP1–WP3) landed and verified:

- **GF Map silent degradation eliminated** — `GfMapLoadStatus` is now exported;
  missing/corrupt resource returns explicit `GfMapLoadFailed` reason rather than
  silent empty map. `unsafePerformIO` invariant documented.
- **LLM endpoint allowlist enforced** — only `api.mistral.ai` and `api.fireworks.ai`
  are allowed by default; custom hosts require explicit
  `QXFX0_LLM_ALLOW_UNTRUSTED_HOST=1` opt-in. Non-https and untrusted hosts
  fail-closed to mock transport with structured telemetry.
- **Typed JSON decoder for chat-completion envelope** — replaced brittle
  `extractStructured` string search with Aeson-typed
  `ChatCompletionResponse/Choice/Message` parser. Invalid envelopes pass through
  raw body for downstream handling.
- Fast suite: green in the local gate; the exact case count is reported by
  `cabal test qxfx0-test-fast`.
- P4 OpinionCore/PerspectiveOperator: implemented as a pure self-layer operator
  plus canonical `PerspectiveRegistry`; finalize/precommit emits typed
  `MutPerspective` records, and replay exposes only `PerspectiveProjection`.

## Status Snapshot (2026-05-20)

Phase A/B/C formal closure is complete:

- EN rendering contour expanded and validated (`check_en_render_path.sh` PASS with
  `intent_fit=1.0000`, `fallback=0.0000`, `ru_leakage=0.0000`).
- Post-commitment adaptation infrastructure is wired with bounded updates and
  guardrails (signal calibration remains a later phase).
- Deterministic time injection is integrated in Prepare stage for reproducible tests.
- Agda formalization pass completed (`nix run .#typecheck-agda` PASS).
- Nix reproducibility checks completed (`nix flake check` PASS, with known non-blocking
  pre-existing `pgf2` warning).

Low-RAM core verification is green (build + fast suite + full meta suite + architecture + GF paths +
artifacts + lexicon). Aggregate/high-memory scientific runs remain infrastructure-dependent and are
tracked as deferred, not treated as PASS.

## Status Snapshot (2026-05-17)

Historical post-M2d landing snapshot (Phase 2.5 dual-mode Conatus +
Phase 5.5d/e Field broadening + Phase 6 effect-system refactor). This
snapshot is superseded by the 2026-05-20/2026-05-22 gate records above.

What landed:

- Runtime Conatus integrated into recovery as the primary,
  priority-overriding driver. Conatus gate fires before all other
  recovery guards (shadow / parser / legitimacy / runtime-mode);
  see ADR-0010 addendum (2026-05-17).
- Dedicated `RecoveryConatusGate` cause in the trace and JSON
  schema, distinct from `RecoveryRuntimeDegraded`; see ADR-0005
  addendum.
- Salience controller verdict emitted in `TurnReplayTrace`
  (`trcSalienceDriver`, `trcSalienceHolisticBias`,
  `trcSalienceConfidence`); audit consumers can reconstruct *why*
  the controller dispatched, not just *what*.
- Canonical pre-turn `Field` populated with four runtime-sourced
  components (Resonance, Atmosphere, Consolidation,
  Counterfactual); see ADR-0009 addendum.
- Single-source-of-truth Conatus refactor: three duplicate
  computation sites collapsed; Prepare stage is canonical.
- New unit suite `Test.Suite.PhaseM2d` (8 tests) + a pipeline-
  level integration test (`testConatusGateFiresRecoveryConatusGate`).

See `CHANGELOG.md` for the full record.

## Status Snapshot (2026-05-13, prior baseline)

- Canonical core run: `ci-20260513-195724`
- Core verdict: `CONTRACT_VERDICT: PROD_GO`
- Core contour: build, tests, architecture, GF quality, GF render path, artifacts, lexicon, degraded-local smoke
- Extended contour: intentionally separated (requires high-memory runner for full scientific profile)

For auditors/reviewers, see:
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
- `reports/baseline_v2/final_gates/_gate_results_ci-20260513-195724_core.md`

## Architecture Snapshot

- `src/QxFx0/**`: runtime core, routing, render pipeline, state, observability

### Legal knowledge adapter (narrow, live stub)

`QxFx0.Legal.Adapter` is **not** dead code: the render phase calls `retrieveLegalFact` when the
knowledge topic matches a small in-memory legal corpus (WP3). Hits enrich the response with a
traceable fragment plus a mandatory disclaimer (`legalDisclaimer`). Non-legal topics are unchanged.
This is a **bounded stub**, not legal advice software — see `test/Test/Suite/LegalAdapter.hs`.

### Datalog shadow (live shadow contour)

Soufflé-backed shadow verification runs in the **route** phase (`TurnReqShadow` via
`QxFx0.Bridge.Datalog`). When the executable is missing, the pipeline records `ShadowUnavailable`
and continues (no hidden retry). Divergence severity feeds legitimacy scoring and typed local
recovery (`Recovery*` causes in the turn trace). Shadow is a **parallel check**, not the primary
family selector — cascade + thresholds remain authoritative for PROD routing.

### Recovery decision and the Conatus gate (Phase 2.5 / M2d)

The local-recovery decision in `buildLocalRecoveryPlan` is
priority-ordered. The **Conatus gate** is the highest-priority
guard: when the runtime `ConatusEnergy` drops below
`conatusGateThreshold` (see `QxFx0.Self.Salience`), the system
is in structural risk and `StrategySafeRecovery` is forced
regardless of shadow, parser, legitimacy, or runtime-mode
signals. The cause is tagged with the dedicated
`RecoveryConatusGate` variant of `LocalRecoveryCause` (snake_case
JSON tag `"conatus_gate"`), distinct from the environmental
`RecoveryRuntimeDegraded`. See ADR-0010 addendum (2026-05-17)
and ADR-0005 addendum (2026-05-17) for the full specification.

The pre-turn `ConatusEnergy` and `Field` are computed once per
turn in `buildPrepareEffectPlan` and threaded through
`PrepareStatic` → `TurnInput` as the single source of truth
(Phase 6 refactor); routing salience and the recovery decision
are read-only consumers of these values.

### Intuition and experimental Bayesian nudge

Production flashes use `QxFx0.Core.Intuition` (threshold posteriors). A light **experimental**
belief nudge from `Core.Bayesian` (`other-modules`) is folded into `checkIntuitionWithInput` via
`bayesianBeliefNudge` — it slightly adjusts resonance/tension before the standard posterior update,
without exposing Bayesian as a separate PROD API.

- `app/**`: CLI surfaces
- `scripts/**`: gates, checks, release orchestration, artifact generators
- `spec/sql/**`: schema + lexicon seeds + contract tables
- `spec/gf/**`: GF grammar and bilingual lexicon artifacts
- `spec/*.agda`: proof/spec layer + generated lexicon artifacts
- `docs/**`: runtime invariants, CI profile, runbooks

## Theoretical Foundation

QxFx0 commits to a documented theoretical position. Architectural and code
changes are expected to honor it.

- `docs/THEORY.md` — three foundational theses (consciousness as structured
  duality, intensive specification, conatus as primary algorithm) and their
  unified synthesis as the implementation contract.
- `docs/ARCHITECTURE.md` — layered architecture (8 horizontal layers),
  enforced dependency invariants, turn pipeline structure, and the landed
  dual-mode (`Holistic ⊣ Formal`) runtime contour.
- `docs/adr/0007-dual-mode-conatus.md` — the architecture decision record
  operationalizing THEORY.md as a phased modernization (P0–P8) toward a
  self-preserving dual-mode runtime with formal `SelfBlanket` invariants
  and a `Conatus` functional.
- `docs/adr/0009-right-hemisphere-field.md` — the algebraic shape of the
  right-hemispheric observation summary (`Field`: Resonance, Atmosphere,
  Consolidation, Counterfactual, FieldConfidence) and the 2026-05-17
  addendum recording each component's runtime source.
- `docs/adr/0010-salience-controller.md` — the Phase-5 Salience
  controller that turns `(ConatusEnergy, Field)` into a
  `(holisticBias, confidence, driver)` verdict; the 2026-05-17
  addendum records the integration into routing salience, the
  Conatus-gate priority override, and the trace-side audit fields.

External readers familiar with active inference (Friston), autopoiesis
(Maturana & Varela), hemispheric duality (McGilchrist), or paraconsistent
logic (Priest, da Costa) will recognize the intellectual lineage; readers
without that background should treat `docs/THEORY.md` as the binding
contract that subsequent code answers to.

## Core Design Principles

1. Route first, render second.
2. Keep failure semantics explicit (`unknown outcome` instead of hidden retries).
3. Keep readiness side-effect free.
4. Keep generated artifacts synchronized from canonical sources.
5. Keep release decisions evidence-backed.

## Quick Start

```bash
python3 -m pip install -r requirements.txt
cabal build all                 # PASS (library + executable)
cabal test qxfx0-test-fast      # PASS — exact case count reported by Cabal
bash scripts/check_architecture.sh  # PASS — 12 invariants OK
bash scripts/gf_quality_gate.sh     # PASS — 0 errors, 0 warnings
```

The following gates are **INFRA-DEFERRED** on low-RAM runners (~10–11 GB):
- `cabal test qxfx0-test` (full meta suite) — passes on high-mem runners
- `bash scripts/check_generated_artifacts.sh` — exceeds 60 s wall-clock
- `bash scripts/check_lexicon.sh` — exceeds 30 s wall-clock
- `QXFX0_CONTRACT_PROFILE=core bash scripts/ci_gate_contract.sh` — aggregate orchestration exceeds RAM/time envelope

Core contour verdict: `CONTRACT_VERDICT: PROD_GO` (verified by individual gates).

**Python test coverage**: No Python unit-test suite currently exists.  The CI
runs three verified Python check scripts (`sync_embedded_sql.py`,
`check_schema_consistency.py`, `check_schema_contract.py`) as part of the
gate contract.  A dedicated Python test contour is a documented gap — see
`docs/PYTHON_TEST_GAP.md`.

## Run a Dialogue Session

```bash
cabal run -v0 qxfx0-main -- --session demo
```

Example turns:

```text
привет
что такое логика?
как отличить истину от мнения?
:state
:quit
```

One-shot request:

```bash
cabal run -v0 qxfx0-main -- --turn-json "что такое свобода?"
```

## HTTP Sidecar

Start:

```bash
cabal run qxfx0-main -- --serve-http 9170
```

Endpoints:
- `GET /sidecar-health`
- `GET /runtime-ready`
- `POST /turn` with `{"session_id":"abc","input":"Что такое свобода?"}`

Operational semantics are documented in this repo and enforced by smoke gates.

## Governance and Project Meta

- Contribution guide: `CONTRIBUTING.md`
- Code of conduct: `CODE_OF_CONDUCT.md`
- Security policy: `SECURITY.md`
- Governance model: `GOVERNANCE.md`
- Roadmap: `ROADMAP.md`
- Third-party notices: `THIRD_PARTY_NOTICES.md`
- Changelog: `CHANGELOG.md`
- Citation metadata: `CITATION.cff`

## Lexicon and GF Pipeline

Canonical flow:

`SQL -> morphology JSON -> GF artifacts -> Agda artifacts -> Haskell generated map`

Key files:
- `spec/sql/lexicon/seed_ru_curated.sql`
- `spec/gf/lexicon_bilingual.tsv`
- `src/QxFx0/Lexicon/Generated.hs`
- `resources/morphology/lexicon_quality.json`

Validation:

```bash
bash scripts/check_lexicon.sh
bash scripts/check_generated_artifacts.sh
```

## What QxFx0 Is Not

- Not a web-scale knowledge engine
- Not a drop-in replacement for frontier LLM products
- Not legal/medical advice software
- Not a black-box stochastic sampler

## Known Limits (Honest)

- Full extended profile needs high-memory CI runners
- GF toolchain availability can be infra-dependent
- Some external integrations are intentionally stubbed in local test contour
- Production runtime is not bit-for-bit deterministic (time/UUID/process scheduling)

## EN Language Status

QxFx0 has experimental English support with the following characteristics:

**Capabilities:**
- GF-based English linearization via `QxFx0SyntaxEng`
- Bilingual lexicon with 3000+ EN lemmas in `spec/gf/lexicon_bilingual.tsv`
- Language routing: pure Latin input → English GF path (conservative policy)
- EN-localized recovery surfaces for degraded/confidence scenarios
- EN quality gate: `scripts/check_en_render_path.sh`

**Current Limitations:**
- EN lexicon coverage is smaller than Russian (prioritized RU core)
- EN GF linearization patterns are less varied than Russian
- Parser confidence tuning is optimized for Russian morphology
- Mixed input (RU+EN) defaults to Russian GF path

**Quality Targets (EN Gate):**
- intent_fit_rate >= 0.90
- gf_output_rate >= 0.85
- fallback_rate <= 0.15
- ru_leakage_rate <= 0.05
- critical_mismatch_count = 0

To run EN evaluation:
```bash
bash scripts/run_en_eval.sh
bash scripts/check_en_render_path.sh
```

## Why This Matters for AI Infrastructure

QxFx0 demonstrates a different axis of AI system design:
- explicit contracts over implicit behavior
- auditable gates over narrative confidence
- deterministic recovery over opaque fallback chains

This is useful for domains where explainability, control, and reproducibility matter more than pure generative breadth.

## 2026 Focus

1. Reduce remaining fallback-heavy surface paths and keep degraded states explicit.
2. Expand GF-native Russian/English parity without reintroducing silent lexical drift.
3. Keep the sense-continuation bridge bounded and observable while it grows into richer adjacency rules.
4. Keep all self-modification contours bounded, decision-recorded, replay-visible, and fail-closed.

## Repository References

- Runtime invariants: `docs/runtime_invariants.md`
- CI profile: `docs/CI_PRODUCTION_PROFILE.md`
- Extended runbook: `docs/EXTENDED_CONTRACT_RUNBOOK.md`
- Release smoke: `scripts/release-smoke.sh`
- Canonical gate evidence: `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`

## License

MIT
