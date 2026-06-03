# QxFx0

**Deterministic dialogue runtime with formal foundations**

QxFx0 is a research-grade conversational system that prioritizes reproducibility, traceability, and formal correctness over probabilistic plausibility. Built on three theoretical pillars—consciousness as structured duality, intensive specification, and conatus as primary algorithm—it demonstrates an alternative approach to dialogue infrastructure.

## What Makes QxFx0 Different

Most conversational AI optimizes for fluency and breadth. QxFx0 optimizes for:

- **Deterministic behavior** — Same input + state → same output, every time
- **Traceable decisions** — Every routing choice has auditable evidence
- **Explicit contracts** — Failure modes are typed, not hidden
- **Formal grounding** — GF grammar + typed semantics, not templates
- **Governance-first** — Append-only history, rebuildable projections, versioned policies

If you need dialogue infrastructure where "why did it do that?" has a precise answer, QxFx0 is built for that use case.

## Current Status (2026-06-03)

**Maturity**: Research-grade with production-ready core  
**License**: MIT  
**Languages**: Russian (primary), English (experimental)

### Recent Milestones

- ✅ **Phase 9–10 (Essence Commitment)** — Trajectory tracking with rupture detection
- ✅ **Phase 8 (Deliberation)** — Reconciliation framework with tone divergence
- ✅ **Phase 6 (M6.1)** — Single-source-of-truth Conatus refactor
- ✅ **P5 Governance** — Canonical append-only history with typed payloads
- ✅ **Security hardening** — LLM endpoint allowlist, typed JSON decoders, explicit degradation
- ✅ **Bilingual support** — Russian + English GF linearization paths

### What's Implemented

**Core Runtime**:
- 8-layer architecture with enforced dependency invariants
- 4-phase turn pipeline (Prepare → Route → Render → Finalize)
- Typed semantic routing via `CanonicalMoveFamily` and `IllocutionaryForce`
- GF-based surface generation with morphology resolver fallback
- SQLite persistence with schema contracts
- HTTP sidecar with session continuity

**Self Layer** (unique to QxFx0):
- `SelfBlanket` — Formal invariants for self-preservation
- `Conatus` — Energy-based continuation drive
- `Holistic ⊣ Formal` — Categorical adjunction between modes
- `Field` — 5-component right-hemispheric observation
- `Salience` — Controller for holistic/formal bias
- `Deliberation` — Reconciliation with tone divergence
- `Essence` — Trajectory commitment with rupture detection

**Governance**:
- P5 spine with append-only history
- Typed governed payloads
- Rebuildable projections
- Machine-readable epistemic status
- 19+ Architecture Decision Records (ADRs)

**Quality Infrastructure**:
- 45 test suites (unit/property/integration/slow/fast)
- Golden corpus with 400+ examples
- Architecture invariant checks
- GF quality gates
- Replay verification

## Theoretical Foundation

QxFx0 is grounded in three theses (see `docs/THEORY.md`):

1. **Consciousness as structured duality** — Not metaphor, but formal model
2. **Intensive specification** — Every decision has mathematical justification
3. **Conatus as primary algorithm** — Energy-based self-preservation

This isn't "inspired by" cognitive science—it's a direct implementation of formal models from active inference (Friston), autopoiesis (Maturana & Varela), and hemispheric duality (McGilchrist).

## Quick Start

### Prerequisites

```bash
# Haskell toolchain
ghc >= 9.6.6
cabal >= 3.10

# Python (for build scripts)
python3 >= 3.9
pip install -r requirements.txt

# Optional: Nix (for reproducible builds)
nix >= 2.18
```

### Build and Test

```bash
# Build
cabal build all

# Fast test suite (< 30s)
cabal test qxfx0-test-fast

# Architecture invariants
bash scripts/check_architecture.sh

# GF quality gate
bash scripts/gf_quality_gate.sh
```

### Run a Dialogue Session

```bash
cabal run -v0 qxfx0-main -- --session demo
```

Example interaction:
```
> привет
контакт: Я здесь.

> что такое логика?
определение: Логика — это структура, которая делает рассуждение воспроизводимым.

> :state
[System state summary...]

> :quit
```

### HTTP Sidecar

```bash
cabal run qxfx0-main -- --serve-http 9170
```

Endpoints:
- `GET /sidecar-health` — Health check
- `GET /runtime-ready` — Readiness probe
- `POST /turn` — Process dialogue turn

Example request:
```bash
curl -X POST http://localhost:9170/turn \
  -H "Content-Type: application/json" \
  -d '{"session_id":"demo","input":"что такое свобода?"}'
```

## Architecture Highlights

### 8-Layer Structure

```
┌─────────────────────────────────────┐
│ App/CLI         (user interface)    │
├─────────────────────────────────────┤
│ Runtime         (session, wiring)   │
├─────────────────────────────────────┤
│ Core            (pipeline, routing) │
├─────────────────────────────────────┤
│ Self            (conatus, field)    │ ← Unique to QxFx0
├─────────────────────────────────────┤
│ Bridge          (SQL, GF, Datalog)  │
├─────────────────────────────────────┤
│ Semantic+Render (meaning, surface)  │
├─────────────────────────────────────┤
│ Lexicon+Policy  (resources, rules)  │
├─────────────────────────────────────┤
│ Types           (domain model)      │
└─────────────────────────────────────┘
```

### Turn Pipeline

```
Input → Prepare → Route → Render → Finalize → Output
         ↓         ↓       ↓         ↓
      [Conatus] [Family] [GF]   [Governance]
      [Field]   [Force]  [Morph] [Trace]
```

### Text Generation (3 levels)

1. **GF (Grammatical Framework)** — Formal grammar via PGF (priority)
2. **Haskell linearization** — Native fallback with morphology resolver
3. **JSON dictionaries** — Preloaded paradigms (genitive, accusative, etc.)

No Python in the runtime path. No LLM for generation. Pure determinism.

## What QxFx0 Is Not

- ❌ Not a web-scale knowledge engine
- ❌ Not a drop-in ChatGPT replacement
- ❌ Not legal/medical advice software
- ❌ Not a black-box stochastic sampler
- ❌ Not optimized for casual conversation

## Known Limitations (Honest)

- **Memory**: Full test suite needs ~10–11 GB RAM
- **Infrastructure**: Some gates require high-memory CI runners
- **Coverage**: Russian lexicon is more complete than English
- **Scope**: Designed for reasoning workflows, not chitchat
- **Determinism**: Not bit-for-bit (time/UUID/process scheduling vary)

## English Language Status

**Experimental** with the following characteristics:

✅ GF-based linearization via `QxFx0SyntaxEng`  
✅ 3000+ EN lemmas in bilingual lexicon  
✅ Language routing (pure Latin → English path)  
✅ EN-localized recovery surfaces  

⚠️ Smaller lexicon than Russian  
⚠️ Fewer GF patterns than Russian  
⚠️ Parser tuning optimized for Russian morphology  

Quality targets: intent_fit ≥ 0.90, gf_output ≥ 0.85, fallback ≤ 0.15

## Why This Matters

QxFx0 demonstrates a different axis of AI system design:

- **Explicit contracts** over implicit behavior
- **Auditable gates** over narrative confidence
- **Deterministic recovery** over opaque fallback chains
- **Formal grounding** over statistical plausibility

This is useful for domains where explainability, control, and reproducibility matter more than generative breadth—think critical infrastructure, research tools, or regulated environments.

## Documentation

- **Theory**: `docs/THEORY.md` — Foundational theses
- **Architecture**: `docs/ARCHITECTURE.md` — 8-layer structure
- **ADRs**: `docs/adr/` — 19+ architecture decisions
- **Contracts**: `docs/runtime_deployment_contract.md`
- **CI Profile**: `docs/CI_PRODUCTION_PROFILE.md`
- **Roadmap**: `ROADMAP.md` — M0–M6 strategic plan

## Governance

- **Contributing**: `CONTRIBUTING.md`
- **Code of Conduct**: `CODE_OF_CONDUCT.md`
- **Security**: `SECURITY.md`
- **Governance**: `GOVERNANCE.md`
- **Changelog**: `CHANGELOG.md`
- **Citation**: `CITATION.cff`

## 2026 Focus

1. Reduce fallback-heavy paths, keep degraded states explicit
2. Expand GF-native Russian/English parity
3. Keep sense-continuation bridge bounded and observable
4. Keep all self-modification contours bounded, recorded, and fail-closed

## For Researchers

If you're working on:
- Formal models of dialogue
- Deterministic AI systems
- Active inference implementations
- Cognitive architecture
- Explainable AI

QxFx0 provides a working reference implementation with:
- Full source code (MIT license)
- Documented theoretical foundations
- Reproducible build (Nix)
- Comprehensive test suite
- Auditable decision traces

## For Engineers

If you need:
- Predictable dialogue behavior
- Traceable decision paths
- Explicit failure modes
- Schema-validated persistence
- Governance-first design

QxFx0 demonstrates production patterns for:
- Typed semantic routing
- Append-only state history
- Replay verification
- Contract-driven testing
- Formal grammar integration

## Citation

```bibtex
@software{qxfx0,
  title = {QxFx0: Deterministic Dialogue Runtime with Formal Foundations},
  author = {[See CITATION.cff]},
  year = {2026},
  url = {https://github.com/[your-org]/QxFx0},
  license = {MIT}
}
```

## License

MIT — See `LICENSE` for details.

---

**Status**: Research-grade with production-ready core  
**Maintenance**: Active development  
**Community**: Contributions welcome (see `CONTRIBUTING.md`)
