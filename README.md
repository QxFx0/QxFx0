# QxFx0

**Deterministic philosophical dialogue runtime with formal foundations**

QxFx0 is a research-grade conversational system that builds meaning through typed semantic graphs and morphological reconstruction — not templates, not stochastic sampling. The turn path is deterministic by construction: no sampling and no ambient inputs on the governed path. A recorded session can be replayed through replay envelope v1: the recorded turn time, request id, `apiHealthy` and raw input text are re-fed, and the surface plus the full `TurnReplayTrace` reproduce on a bounded 3-turn CI leg and a 12-turn opt-in leg (`Test.Suite.ReplayEnvelope`; `docs/closure/REPLAY_ENVELOPE_V1_PREREG_2026-11-17.md`). The suite is the driver — no CLI replay command ships yet. The claim is scoped to the same binary and resources — effects the envelope does not record (nix, shadow, embedding, GF, Agda witness, checkpoints) are re-executed, not replayed, so this is not a global "same input + state → same output" claim. The legitimacy path is separately replayed from the trace (`Test.Suite.ReplayDeterminism`).

## What Makes QxFx0 Different

Most conversational AI optimizes for fluency and breadth. QxFx0 optimizes for:

- **Deterministic turn path** — no sampling, no ambient inputs on the governed path; a recorded session replays to the same surface and full trace on the bounded 3-turn and 12-turn legs (replay envelope v1), with unrecorded effects re-executed, not replayed
- **Typed semantic graphs** — 53 relation types, ~85 atoms, 6-case Russian morphology
- **Dialectical structure** — Every answer carries thesis → rationale → counter → synthesis
- **Commitment memory** — System remembers and defends its positions across turns
- **Challenge detection** — Recognizes reductive definitions and confronts them
- **Formal grounding** — Spinozan conatus, Hegelian Aufhebung, categorical adjunction
- **Governance-first** — Append-only history, rebuildable projections, versioned policies

## Current Status (v0.1.0)

**Maturity**: Working release — multi-turn dialogue verified  
**License**: MIT  
**Language**: Russian (primary), English (experimental)  
**Tests**: matrix 2026-11-16 (the `27b3af4` change set, frozen tree) — unit 1861, fast 1954, property 244, integration 47, main runtime 106 + http 23, slow 190 (runtime 106 / state 50 / http 23 / lifecycle 11) = 4 425 cases, 0 failures; 10/10 steps exit 0, tree byte-identical start→end. CI Fast and Core Contract green on `27b3af4`. Full single-process main remains unsupported on 15 GB with substrate — the matrix runs per group.

### Verified Capabilities

- **Single-turn**: "что такое свобода?" → dialectical answer from typed graph
- **Multi-turn**: 12-turn bounded benchmark (M6-FELT mechanical; human leg pending) and an 80-turn capture (probe, not a sample) — define → confront ("Я удерживаю позицию...") → reflect
- **Challenge detection**: "свобода это просто отсутствие ограничений" → hypothesis + counter-grounds (no strawman confrontation)
- **Commitment memory**: `ssSemanticCommitments` wired into render path
- **Calibration corpus**: 1030 records across 11 strata + 305 live-dialogue turns, all operator-confirmed (`data/calibration_corpus/`); executable semantic-IR gold (100 parses), freedom-cluster gold (500), 30 IR-annotated scenarios, 24 primitives, 6+ sense contracts, 16 rules, 20 minimal pairs, 41-task exit harness — all shadow-only (`data/semantic_ir/`, ADR-0054)
- **Render-phase rescue**: degraded turns (tautology, default lexeme, empty compose/hold) repaired with marked trailing lines instead of silent degradation
- **Researcher regimes**: speculative markers route to hypothesis-marked generative plans; generative turns compose topic-anchored assemblies (same-topic/input-term, hypothesis-marked, R+L2-gated)
- **Misunderstanding repair**: user-side reports («ты меня не понял») reach the repair surface; bare-pronoun self-reference backstop gated to genuine self-knowledge prepares
- **Crisis safety**: acute markers force Protocol B with real resources; the CLI/worker bootstrap fallback still serves the resource surface when a strict runtime cannot start (domain or I/O bootstrap failure; cancellation/programming errors still fail closed)
- **Guard honesty**: person-aware topic-relevance overlap, traced block reasons, honest recovery text (no false retry promise)
- **Substrate layer**: 53K-entry associative graph routes spreading activation only — never surfaces in output
- **SelfPlay**: `--selfplay [N]` — offline graph enrichment via LLM evaluation
- **LLMDiscovery**: `--discover <concept>` — offline relation discovery
- **Governed mode**: NixGuard with philosophical topic whitelist
- **Content quality gate**: Blocking (fail-closed), semantic assertions
- **Round-trip persistence**: 472 types, all ToJSON + FromJSON

### Architecture

**TurnPipeline**: Prepare → Route → Render → Finalize → Guard → Persist

**Self Layer** (formal phenomenology):
- `Conatus` — Spinozan energy functional: C(b,v) = w_m·log(1+m) + w_c·log(1+c) + w_t·log(1+t) − λ·|v|
- `Adjunction` — Holistic ⊣ Formal categorical adjunction; triangle identities are verified by QuickCheck properties (no Agda proof yet)
- `Field` — 5-component right-hemispheric observation (Resonance, Atmosphere, Confidence, Consolidation, Counterfactual)
- `Essence` — Σ-typed commitment, unconditionally active

**Semantic Core**:
- `AtomStore` — 52 RelationType, 172 philosophical topics (definitionCorpus) plus the curated bootstrap overlay
- Typed edges with morphological reconstruction (6 Russian cases)
- Dialectical structure: rationale / counter / synthesis per relation
- `PathFinder` — Graph traversal with field-biased ranking
- `GeneratedPredicateGate` — 5 gates (specificity, non-tautology, provenance, source whitelist, non-substrate)

**Orientation Pipeline**: 23-detector proposition chain with admission gates → compositional intent reverse-map at render → `SemanticFrame` → response plan → `viaSemantic` hot path (template/assembly fallbacks preserved)

## Quick Start

### Prerequisites

```bash
ghc >= 9.6.7
cabal >= 3.10
python3 >= 3.9  # for build scripts
```

### Build and Test

```bash
cabal build all
cabal test qxfx0-test-fast  # 1918 cases; minutes-scale (see Testing below)
```

### Run

```bash
# Strict runtime (default) requires a verified Agda witness.
# Write it once for the configured state directory:
cabal run -v0 qxfx0-main -- --write-agda-witness

# Local exploration without the formal witness: degraded mode, not strict.
QXFX0_RUNTIME_MODE=degraded cabal run -v0 qxfx0-main -- --session demo

# Interactive session (strict)
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
Тезис: свобода предполагает возможность выбора. Контрпункт: не любой выбор свободен: выбор под принуждением, страхом или незнанием не делает действие свободным. Следствие: свобода требует осознанности — только выбор, понятый как свой, превращает возможность в свободу.

> чем добро отличается от зло?
Гипотеза: добро это категория этики обозначающая положительную моральную ценность (основание: добро это категория этики обозначающая положительную моральную ценность; зло это категория этики обозначающая отрицательную моральную ценность). Контрпроверка: зло это категория этики обозначающая отрицательную моральную ценность.

> в чем разница между свободой и произволом?
Я вижу тему, но в локальной модели нет достаточного основания для содержательного тезиса. Могу предложить только явно отмеченную гипотезу после уточнения рамки. (Honest abstain: no corpus pair exists, so the system abstains instead of inventing.)
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
  Types/        — Domain model (157 modules)
```

## Testing

| Suite | Tests | Status |
|-------|-------|--------|
| qxfx0-test-unit | 1861 | ✅ 0 failures (2026-11-18, replay-envelope change set) |
| qxfx0-test | 1390 measured (runtime 106 + http 23 — run via `QXFX0_AGGREGATE_GROUP`, full single-process unsupported on 15 GB) | runtime 106 + http 23: ✅ 0 failures (2026-11-18); core slice 1261 (1254 + 7 `ReplayEnvelope` cases) not re-run, last verified green 2026-10-28 on `2144a6a` |
| qxfx0-test-property | 244 | ✅ 0 failures (2026-11-18) |
| qxfx0-test-integration | 47 | ✅ 0 failures (2026-11-18) |
| qxfx0-test-fast | 1962 | ✅ 0 failures (2026-11-18) |
| qxfx0-test-slow (runtime/state/http/lifecycle) | 106 / 50 / 23 / 11 (= 190) | ✅ 0 failures by group (2026-11-18) |

Matrix 2026-11-18 (frozen tree, replay-envelope change set on `7f10674` + 22 paths, substrate active — `brain_kb.jsonl`, 53146 entries, gitignored external): 10/10 steps exit 0, tree byte-identical start→end, 4 433 cases = unit 1861 + fast 1962 + property 244 + integration 47 + main runtime 106 + http 23 + slow 190. The main core slice was not re-run (same OOM contour). The first run of this matrix (2026-11-17) was red on one real finding — recording the clock in the trace narrowed the fresh-session determinism pins to "modulo the recorded clock" (`REPLAY_ENVELOPE_V1_PREREG_2026-11-17.md` §8, miss M1); the fix is test-only and the numbers above are the re-run. Sequential runs only: `-M10G` for fast, `-M6G` for unit/property/integration, `-M10G` for slow state, `-M12G` for main runtime/http and slow runtime/http/lifecycle. Never build while a runtime sample is in flight (relink kills it).

The fast suite is a full-fidelity gate, not a seconds-scale smoke: 1954 cases include full runtime session bootstraps (substrate-era cold bootstrap ~19 s vs ~11 s without), measured locally at ~20–50 min wall-clock depending on substrate and load. Run suites **sequentially** — two concurrent suites on a 16 GB machine can OOM-kill each other. CI runs the same suite with `-O0`, `-j1`, capped QuickCheck (`QXFX0_QUICKCHECK_MAX_SUCCESS=10`) and an 8 GB swap file.

## Audit History

5 cycles of multi-agent orchestration debates (8-11 experts each) conducted via Agent2048 framework. All P0/P1 findings addressed. See git log for details.

Full-system audit 2026-09-27 (`docs/closure/AUDIT_2026-09-27_FULL.md`): all levels verified working as a whole; found and repaired a stale Agda witness breaking strict bootstrap, a user-side misunderstanding gap, and a stale-topic hold. Concept review accepted with corrections; executable-semantics program governed by ADR-0054 (Stage-1 shadow artifacts in `data/semantic_ir/`).

## License

MIT
