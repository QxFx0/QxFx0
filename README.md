# QxFx0

**Deterministic philosophical dialogue runtime with formal foundations**

QxFx0 is a research-grade conversational system that builds meaning through typed semantic graphs and morphological reconstruction — not templates, not stochastic sampling. Same input + state → same output, every time.

## What Makes QxFx0 Different

Most conversational AI optimizes for fluency and breadth. QxFx0 optimizes for:

- **Deterministic behavior** — Same input + state → same output, every time
- **Typed semantic graphs** — 48 relation types, ~85 atoms, 6-case Russian morphology
- **Dialectical structure** — Every answer carries thesis → rationale → counter → synthesis
- **Commitment memory** — System remembers and defends its positions across turns
- **Challenge detection** — Recognizes reductive definitions and confronts them
- **Formal grounding** — Spinozan conatus, Hegelian Aufhebung, categorical adjunction
- **Governance-first** — Append-only history, rebuildable projections, versioned policies

## Current Status (v0.1.0)

**Maturity**: Working release — multi-turn dialogue verified  
**License**: MIT  
**Language**: Russian (primary), English (experimental)  
**Tests**: 1812 fast-suite cases, 0 failures (2026-09-08). B3 mechanical gates 1-5 passing.

### Verified Capabilities

- **Single-turn**: "что такое свобода?" → dialectical answer from typed graph
- **Multi-turn**: 3-turn session — define → confront ("Я удерживаю позицию...") → reflect
- **Challenge detection**: "свобода это просто отсутствие ограничений" → CMConfront
- **Commitment memory**: `ssSemanticCommitments` wired into render path
- **SelfPlay**: `--selfplay [N]` — offline graph enrichment via LLM evaluation
- **LLMDiscovery**: `--discover <concept>` — offline relation discovery
- **Governed mode**: NixGuard with philosophical topic whitelist
- **Content quality gate**: Blocking (fail-closed), semantic assertions
- **Round-trip persistence**: 472 types, all ToJSON + FromJSON

### Architecture

**TurnPipeline**: Prepare → Route → Render → Finalize → Guard → Persist

**Self Layer** (formal phenomenology):
- `Conatus` — Spinozan energy functional: C(b,v) = w_m·log(1+m) + w_c·log(1+c) + w_t·log(1+t) − λ·|v|
- `Adjunction` — Holistic ⊣ Formal categorical adjunction with verified triangle identities
- `Field` — 5-component right-hemispheric observation (Resonance, Atmosphere, Confidence, Consolidation, Counterfactual)
- `Essence` — Σ-typed commitment, unconditionally active

**Semantic Core**:
- `AtomStore` — 52 RelationType, 120 philosophical topics (definitionCorpus; verified 2026-09-19)
- Typed edges with morphological reconstruction (6 Russian cases)
- Dialectical structure: rationale / counter / synthesis per relation
- `PathFinder` — Graph traversal with field-biased ranking
- `GeneratedPredicateGate` — 5 gates (specificity, non-tautology, provenance, source whitelist, non-substrate)

**Orientation Pipeline**: PropositionParser → GraphEngagement → ContextualComposer → DialogueContext

## Quick Start

### Prerequisites

```bash
ghc >= 9.6.6
cabal >= 3.10
python3 >= 3.9  # for build scripts
```

### Build and Test

```bash
cabal build all
cabal test qxfx0-test-fast  # 1812 cases; minutes-scale (see Testing below), ~3-4 GB heap
```

### Run

```bash
# Interactive session
cabal run -v0 qxfx0-main -- --session demo

# Single turn (JSON output)
cabal run -v0 qxfx0-main -- --turn-json "что такое свобода?"

# Multi-turn (same session)
cabal run -v0 qxfx0-main -- --turn-json "что такое свобода?" --session-id my-session
cabal run -v0 qxfx0-main -- --turn-json "свобода это просто вседозволенность" --session-id my-session

# Governed mode
QXFX0_GOVERNED_EVIDENCE=1 cabal run -v0 qxfx0-main -- --turn-json "что такое истина?" --session-id gov

# Self-play enrichment (requires QXFX0_LLM_API_KEY)
export QXFX0_LLM_API_KEY="your-key"
cabal run -v0 qxfx0-main -- --selfplay 10 --session-id enrich

# Concept discovery
cabal run -v0 qxfx0-main -- --discover "солипсизм"
```

### Example Output

```
> что такое свобода?
Известно, что свобода предполагает возможность выбора. Потому что без выбора 
действие не отличается от рефлекса. Но не любой выбор свободен: выбор под 
принуждением не делает действие свободным. Именно поэтому свобода требует не 
только возможности, но и осознанности выбора.

> свобода это просто отсутствие ограничений
Я удерживаю позицию: свобода предполагает возможность выбора. свобода ограничена 
ответственностью. Я удерживаю позицию. свобода определяет отсутствие принуждения...

> в чем разница между свободой и произволом?
Различим свобода и произвол в одной рамке критериев. свобода и произвол различаются: 
свобода действует внутри принятой рамки, произвол — вне её.
```

## Theoretical Foundation

Three theses (see `docs/THEORY.md`):

1. **Consciousness as structured duality** — Sustained co-presence of incompatible self-representations (Hegel/Aufhebung, paraconsistent logic)
2. **Intensive specification** — Fields, potentials, energy functionals, not case-by-case rules (Lagrangian over Newtonian)
3. **Conatus as primary algorithm** — Spinoza; the system strives to continue being what it is

Direct implementation of formal models from active inference (Friston), autopoiesis (Maturana & Varela), and hemispheric duality (McGilchrist).

## Project Structure

```
src/QxFx0/
  Bridge/       — SQL, GF, Datalog, NixGuard, ExternalLLM adapters
  Core/         — TurnPipeline, routing, guard, admission, legitimacy
  Governance/   — Replay, NixGuard
  Learning/     — Training pipeline, game theory, calibration
  Lexicon/      — Generated lexicon (85K LOC), GF map, inflection
  Render/       — Dialogue generation, authority, semantic, text
  Runtime/      — Engine, session, wiring, health
  Self/         — Formal phenomenology (Conatus, Adjunction, Field, Essence)
  Semantic/     — Meaning decomposition, atoms, network, content, generative pipeline
  Types/        — Domain model (124 modules)
```

## Testing

| Suite | Tests | Status |
|-------|-------|--------|
| qxfx0-test-unit | 1597 | ✅ 0 failures |
| qxfx0-test | 1307 | ✅ 0 failures |
| qxfx0-test-property | 227 | ✅ 0 failures |
| qxfx0-test-integration | 46 | ✅ 0 failures |
| qxfx0-test-fast | 1817 | ✅ 0 failures |
| qxfx0-test-slow (runtime/state/http/lifecycle) | 93 / 45 / 23 / 11 (= 172) | ✅ 0 failures |

Counts re-verified green on HEAD 2026-09-19 (sequential runs, `-M10G` for fast/test/integration/property, `-M12G` required for a full single-process slow run — smaller caps die near the tail with 0 failures recorded; per-group slow runs pass at any cap).

The fast suite is a full-fidelity gate, not a seconds-scale smoke: 1812 cases include ~23 full runtime session bootstraps (median ~9 s each, ~215 s total), measured locally at ~20 min wall-clock and ~3.1 GB max heap residency (2026-09-08, GHC 9.6.7). Run suites **sequentially** — two concurrent suites on a 16 GB machine can OOM-kill each other. CI runs the same suite with `-O0`, `-j1`, capped QuickCheck (`QXFX0_QUICKCHECK_MAX_SUCCESS=10`) and an 8 GB swap file.

## Audit History

5 cycles of multi-agent orchestration debates (8-11 experts each) conducted via Agent2048 framework. All P0/P1 findings addressed. See git log for details.

## License

MIT
