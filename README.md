# QxFx0

Deterministic, spec-first dialogue runtime for Russian reasoning workflows.

QxFx0 is an open-source alternative to purely probabilistic chat stacks: routing is typed and explicit, output is grammar-constrained, and release decisions are gate-driven with auditable evidence.

## Why This Project Exists

Most conversational systems optimize for plausibility. QxFx0 optimizes for:
- reproducible behavior under explicit contracts
- traceable decisions (family/force/state transitions)
- safe degraded behavior without hidden retries
- verifiable release gates instead of “it seems to work”

If you need deterministic dialogue infrastructure with strict operational semantics, QxFx0 is built for that.

## What Is Implemented

- Typed semantic routing (`CanonicalMoveFamily`, `IllocutionaryForce`)
- Multi-layer runtime: Haskell core + SQLite persistence + GF surface generation
- Constitutional readiness contour (Nix policy checks)
- CLI runtime and HTTP sidecar with live-session continuity contract
- Gate contract for release decisions (`scripts/ci_gate_contract.sh`)
- Lexicon pipeline with collision/quality controls and generated artifacts sync

## Current Maturity

- Core release contour: `PROD_GO` (core contract profile)
- Extended scientific contour: deferred to high-memory runners
- Canonical evidence: `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
- CI/release profile: `docs/CI_PRODUCTION_PROFILE.md`

## Status Snapshot (2026-05-13)

- Canonical core run: `ci-20260513-195724`
- Core verdict: `CONTRACT_VERDICT: PROD_GO`
- Core contour: build, tests, architecture, GF quality, GF render path, artifacts, lexicon, degraded-local smoke
- Extended contour: intentionally separated (requires high-memory runner for full scientific profile)

For auditors/reviewers, see:
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
- `reports/baseline_v2/final_gates/_gate_results_ci-20260513-195724_core.md`

## Architecture Snapshot

- `src/QxFx0/**`: runtime core, routing, render pipeline, state, observability
- `app/**`: CLI surfaces
- `scripts/**`: gates, checks, release orchestration, artifact generators
- `spec/sql/**`: schema + lexicon seeds + contract tables
- `spec/gf/**`: GF grammar and bilingual lexicon artifacts
- `spec/*.agda`: proof/spec layer + generated lexicon artifacts
- `docs/**`: runtime invariants, CI profile, runbooks

## Core Design Principles

1. Route first, render second.
2. Keep failure semantics explicit (`unknown outcome` instead of hidden retries).
3. Keep readiness side-effect free.
4. Keep generated artifacts synchronized from canonical sources.
5. Keep release decisions evidence-backed.

## Quick Start

```bash
cabal build all
cabal test qxfx0-test
bash scripts/check_architecture.sh
bash scripts/gf_quality_gate.sh
bash scripts/check_generated_artifacts.sh
bash scripts/check_lexicon.sh
QXFX0_CONTRACT_PROFILE=core bash scripts/ci_gate_contract.sh
```

Expected contract result: `CONTRACT_VERDICT: PROD_GO`.

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

## Why This Matters for AI Infrastructure

QxFx0 demonstrates a different axis of AI system design:
- explicit contracts over implicit behavior
- auditable gates over narrative confidence
- deterministic recovery over opaque fallback chains

This is useful for domains where explainability, control, and reproducibility matter more than pure generative breadth.

## 2026 Focus

1. Reduce template fallback paths and expand GF-native Russian generation quality.
2. Improve practical RU/EN dual-language conversational parity.
3. Add traceable domain adapters (for example legal/structured knowledge corpora) without breaking deterministic core contracts.

## Repository References

- Runtime invariants: `docs/runtime_invariants.md`
- CI profile: `docs/CI_PRODUCTION_PROFILE.md`
- Extended runbook: `docs/EXTENDED_CONTRACT_RUNBOOK.md`
- Release smoke: `scripts/release-smoke.sh`
- Canonical gate evidence: `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`

## License

MIT
