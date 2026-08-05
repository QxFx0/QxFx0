# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `GF-RELEASE-AUDIT — bounded canary + release-corpus audit harness`
- `current_state`: New audit tooling is in place and running locally but **entirely uncommitted**: `scripts/gf_release_audit.py`, `scripts/run-bounded-v3-canary.sh`, `scripts/autonomous-canary-monitor.sh`, fixtures `spec/gf/{release_corpus_golden.tsv,release_corpus_prompts.txt,curated_predicate_slots.tsv,argued_leaf_slots.tsv}`, output in `reports/gf-release/`. Latest run `20260726T170210Z` = **PASS**, but only **1 turn** (canonical rate 1.0000, recovery 0.0000, fallbacks `{"none": 1}`, 0 quality issues, 0 semantic substitutions, warm p95 6782 ms). A 1-turn PASS is a smoke signal, **not** release-grade canary evidence.
- `last_updated`: `2026-07-26`
- `evidence_or_result_ref`: `reports/gf-release/audit-20260726T170210Z.{md,json}`, `reports/gf-release/canary-20260726T170210Z.jsonl`

### Second live front (same tree, uncommitted)

- `front_id`: `PROMOTION-V4 — governed promotion chain + response plan`
- `current_state`: Whole promotion subsystem exists **untracked**: `src/QxFx0/Learning/{Promotion,PromotionRuntime,PromotionReview,JobQueue,CorroborationQueue,Rollback,Quality}.hs`, `src/QxFx0/Semantic/ResponsePlan*`, `src/QxFx0/Runtime/{ManagedWorker,AutonomousSmoke,StateDefaults}.hs`, `src/QxFx0/Types/{Learning,Memory,Policy}/`, plus 4 new migrations (`learning_005_canary_state`, `learning_006_session_jobs`, `promotion_scope_001_session_evidence`, `runtime_projection_002_session_scope`).
- `blocker`: **`human_review_required`** — automated runtime gate passes, activation eligible `false`. Repo-owner decision, not a code gap.
- `evidence_or_result_ref`: `reports/promotion-v4-release-cycle-20260719.md` (+ 7 sibling `reports/promotion-*-20260719.md`, `reports/*selector-preflight*-20260719.md`)

## Immediate next action

1. **Decide the fate of the working tree.** `main` is **338 commits ahead of `origin/main`** (0 behind — clean fast-forward) with nothing published since `436d6a8` (2026-06-24), *plus* ~174 tracked files with real content changes and ~225 untracked paths on top of the last commit (`49440f8`, 2026-07-17). Two separate decisions: (a) publish/withhold the 338; (b) commit or reduce the uncommitted delta. Until (b) happens there is no reproducible state for any gate claim.
   - Use `git diff --ignore-all-space` when sizing this: raw `--stat` reads ~96k lines because of CRLF churn, not content.
2. **Widen the bounded canary before treating it as evidence.** 1 turn is not a corpus; run the release corpus (`spec/gf/release_corpus_prompts.txt`) and record turns/fallback distribution/p95 over a real window.
3. **Resolve Promotion-V4 `human_review_required`** — either attest the review and activate the draft overlay (`overlay-42c1335b…`), or record a documented refusal. Draft has been inactive since 2026-07-19.
4. **Gate status is UNKNOWN as of this update.** No test suite was run when this board was refreshed on 2026-07-26. Do not cite any gate as green until re-run against the current tree.

## Open decisions / blockers

| item | kind | owner | note |
|---|---|---|---|
| Publish 338 unpushed commits to `origin/main` | release decision | repo owner | ff-clean; public/private boundary applies (`docs/tz/` stays internal) |
| Uncommitted promotion/response-plan subsystem | hygiene | repo owner | untracked source files carry no history and no CI coverage |
| Promotion-V4 draft activation | human review | repo owner | `human_review_required`; snapshot `promotion-snapshot-aa7e60d4…`, 17700 edges, 9 candidates → 1 gate-eligible |
| M6-FELT | research | — | **NOT PROVEN**; see `ROADMAP.md` North Star and the B1–B4 split |

## Recently landed (2026-06-18 → 2026-07-17)

Summaries only — details live in the ADRs and in `docs/front_archive.md`.

- **ADR-0050** compose-from-activation surface text (`SurfaceAccumulator`, wired into `generateFromFrame`, golden tests + feature flag).
- **ADR-0051** typed dispatch across all gates (a–h): `SemanticFrameTarget`, `DreamCandidateKind`, `ConflictPolicy`, `TransportMode`, `RuntimeMode`/`HealthStatus`, `ParserStatus`, `PipelineEffectLabel`, parameterized `PropositionAdmissionConfig`.
- **ADR-0052** relation-graph external knowledge: 666 curated relations exported to JSONL, `ontology.jsonl` + `Ontology` module, provenance-aware network merge, field-modulated spreading activation, `ingest` CLI, ontology-driven category classification.
- **ADR-0053** runtime-LLM discovery bridge to the semantic network.
- **ADR-0054 M1–M4** autonomous semantic expansion: M1 infrastructure → M2 content-density gate → M3 end-to-end loop-closure test + `spawnAutonomousLearningHandles` in Bootstrap → M4 runtime-ready safety (`Learning/Quarantine.hs`, `Learning/CircuitBreaker.hs`, `Test/Suite/AutonomousSafety.hs`, all first landed in `c02549a`, 2026-07-16). Plans: `docs/superpowers/plans/2026-07-11-ADR-0054-M{3,4}-runtime-ready.md`.
- **Closure Round** (`docs/plan/closure-round-tz.md`, 2026-07-09) — diagnosed pattern **write-without-read ×3**: atom-graph seed default-on, feedback read-side + relation-weight overlay, selfplay admission gate, cross-turn coherence via emitted-predicate buffer, ontology depth weighting + sibling borrowing.
- **P1 curation COMPLETE** (`bd0fdd1`, 2026-07-14): `docs/GAPS.md` reports 100% coverage — all 281 gap concepts curated; `resources/knowledge/curated_predicates.jsonl` at 6239 lines (batches through 6224). The bulk of the 338 unpushed commits are these batches.

## Current state of the M6 gate

Scope note: the table below is **M6-STRUCTURAL** only. Structural closure is *necessary, not sufficient* for the North Star; **M6-FELT remains NOT PROVEN** and no row here upgrades it.

| Gate | Status |
|------|--------|
| H1 (SLICE-NA-001) | ✅ closed |
| H2 (deferred arch queue) | ✅ SR-03/04/05 classified |
| H3 (M5 governed regime) | ✅ `Test.Suite.M5Regime` |
| C1 (continuity + 6 contours P4) | ✅ |
| C2 (restart integrity + regime markers) | ✅ |
| C3 (commitment accountability) | ✅ CTS-42 admission + CTS-43 quarantine + CTS-44 promotion |
| C4 (bidirectional semantic) | ✅ GF-E1b + CTS-40 + ADR-0019 |

Public declaration scope lives in `docs/closure/M6_DECLARATION.md` (bounded/partial). Every ✅ must be re-verified at claim time, not inherited from this snapshot.

## Active architecture queue

1. Keep the CTS layer stable — no new proposition consumers without an admission module.
2. When math constants change → follow `MATH_CHANGE_PROTOCOL.md`.
3. Legacy decode windows (SR-05) — monitor for retirement triggers.
4. New: untracked source under `src/` is an architecture risk — the arch gate (`scripts/check_architecture.sh`) and CI see none of the promotion/response-plan modules.

## Notes

- This file is the execution coordinator, and is **internal-only** — never public release evidence.
- Historical summaries belong in `docs/front_archive.md`.
- Program doctrine belongs in `ROADMAP.md`.
- Deferred architecture follow-ups stay in `ROADMAP.md` until a new bounded front is explicitly activated.
- Run slow/runtime suites **sequentially** — concurrent instances are port/subprocess-heavy and corrupt results.
