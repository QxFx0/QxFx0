# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `RELEASE-READINESS — bootstrap-safety landing + publication decision`
- `current_state`: Bootstrap-safety fallback is landed (`203ffbf`, `b98a833`, `c201a80`); `main` is **51 commits ahead of `origin/main`**, nothing pushed. Unit/fast/property/integration are green on the code tree (1818/1918/244/47); main/core and slow 190 were not run as single processes for this pin. Architecture check is green in the working tree after the two hygiene fixes (commit pending).
- `last_updated`: `2026-10-24`
- `evidence_or_result_ref`: `docs/closure/CALIBRATION_REPORT.md` (Bootstrap-safety landing); `/tmp/opencode/qxfx0-bootstrap-rerun/` logs; gate snapshot below.

### Second live front — promotion V4 (human review)

- `front_id`: `PROMOTION-V4 — governed promotion chain + response plan`
- `current_state`: Promotion/response-plan subsystem is **tracked** in the current tree (no untracked source files); draft overlay remains inactive.
- `blocker`: **`human_review_required`** — automated runtime gate passes, activation eligible `false`. Repo-owner decision, not a code gap.
- `evidence_or_result_ref`: `reports/promotion-v4-release-cycle-20260719.md` (+ 7 sibling `reports/promotion-*-20260719.md`, `reports/*selector-preflight*-20260719.md`)

## Immediate next action

1. **Commit the architecture hygiene fix.** The working tree totalizes the ownership-journal partials in `Core/TurnPipeline/Effects.hs` and syncs the stale anti-rot registry label for `emConatusStructuralFloor`; `scripts/check_architecture.sh` is green in the working tree. Commit, then re-run the check on the committed tree.
2. **Run the remaining release gates on the exact tree.** `qxfx0-test` via `QXFX0_AGGREGATE_GROUP=core|runtime|http` and `qxfx0-test-slow` via `QXFX0_SLOW_GROUP=runtime|state|http|lifecycle`, sequentially with the documented `-M` caps; record counts in `CALIBRATION_REPORT.md`.
3. **Decide the fate of the working tree.** `main` is **51 commits ahead of `origin/main`** (0 behind — clean fast-forward; working tree will be clean after the pending architecture commit) with nothing published since `436d6a8` (2026-06-24). Publish/withhold remains a repo-owner decision; until it happens no gate claim is externally reproducible.
   - Use `git diff --ignore-all-space` when sizing this: raw `--stat` reads ~96k lines because of CRLF churn, not content.
4. **Resolve Promotion-V4 `human_review_required`** — either attest the review and activate the draft overlay (`overlay-42c1335b…`), or record a documented refusal. Draft has been inactive since 2026-07-19.
5. **Widen the bounded canary before treating it as evidence.** 1 turn is not a corpus; run the release corpus (`spec/gf/release_corpus_prompts.txt`) and record turns/fallback distribution/p95 over a real window.

### Gate status snapshot (2026-10-24)

All six suites were last fully re-verified sequentially on the 2026-09-19 HEAD: unit 1595, test 1306, fast 1812, property 227, integration 46, slow 172. **Current bootstrap-safety tree**: unit 1818, fast 1918, property 244, integration 47 (an earlier chained attempt hit a transient ENOSPC, not an assertion; the rerun was green); slow 190 is the last P3 result and was not re-run for this pin; main/core are registered at 1339/1219 and were rebuilt but not run as single processes this cycle. Architecture check is green in the working tree after the hygiene fix (full run, including rule [10]). Do not cite gates against any other tree without re-running.

## Open decisions / blockers

| item | kind | owner | note |
|---|---|---|---|
| Publish 51 unpushed commits to `origin/main` | release decision | repo owner | ff-clean; public/private boundary applies (`docs/tz/` stays internal) |
| ~~Uncommitted promotion/response-plan subsystem~~ | hygiene | repo owner | **RESOLVED in the current tree**: `git status` has no untracked source files. Any future untracked subsystem must be committed or documented before it is cited as evidence. |
| Promotion-V4 draft activation | human review | repo owner | `human_review_required`; snapshot `promotion-snapshot-aa7e60d4…`, 17700 edges, 9 candidates → 1 gate-eligible |
| Architecture check | hygiene | repo owner | **GREEN in the working tree** after totalizing `Core/TurnPipeline/Effects.hs` and syncing the anti-rot registry label for `emConatusStructuralFloor`; commit pending. |
| Release verification gap | release evidence | repo owner | main/core and slow 190 were not run as single processes on the bootstrap-safety tree; run via `QXFX0_AGGREGATE_GROUP` / `QXFX0_SLOW_GROUP` and record counts. |
| M6-FELT | research | — | **MECHANICAL PROVEN (bounded 12-turn benchmark); HUMAN PARTIAL; formal claim withheld** — see `M6_FELT_GATE.md`, B2 EXEC-002/003 |
| M7 production evidence | research/ops | repo owner | **OPEN** (regenerative evidence/ops regime); no closure evidence in the current tree. Do not claim M7 closed. |

## Recently landed (2026-06-18 → 2026-10-24)

Summaries only — details live in the ADRs and in `docs/front_archive.md`.

- **Bootstrap-safety fallback** (`203ffbf`, `b98a833`, `c201a80`, 2026-10-24): `--turn-json` and `--worker-stdio` now serve the real Protocol B resource pack when strict bootstrap fails on an acute crisis marker; non-crisis bootstrap failures still fail closed. Healthy runtime path unchanged. Pin: `Test.Suite.CrisisGuard` 20 cases; unit/fast/property/integration green on the code tree.
- **ADR-0050** compose-from-activation surface text (`SurfaceAccumulator`, wired into `generateFromFrame`, golden tests + feature flag).
- **ADR-0051** typed dispatch across all gates (a–h): `SemanticFrameTarget`, `DreamCandidateKind`, `ConflictPolicy`, `TransportMode`, `RuntimeMode`/`HealthStatus`, `ParserStatus`, `PipelineEffectLabel`, parameterized `PropositionAdmissionConfig`.
- **ADR-0052** relation-graph external knowledge: 666 curated relations exported to JSONL, `ontology.jsonl` + `Ontology` module, provenance-aware network merge, field-modulated spreading activation, `ingest` CLI, ontology-driven category classification.
- **ADR-0053** runtime-LLM discovery bridge to the semantic network.
- **ADR-0054 M1–M4** autonomous semantic expansion: M1 infrastructure → M2 content-density gate → M3 end-to-end loop-closure test + `spawnAutonomousLearningHandles` in Bootstrap → M4 runtime-ready safety (`Learning/Quarantine.hs`, `Learning/CircuitBreaker.hs`, `Test/Suite/AutonomousSafety.hs`, all first landed in `c02549a`, 2026-07-16). Plans: `docs/superpowers/plans/2026-07-11-ADR-0054-M{3,4}-runtime-ready.md`.
- **Closure Round** (`docs/plan/closure-round-tz.md`, 2026-07-09) — diagnosed pattern **write-without-read ×3**: atom-graph seed default-on, feedback read-side + relation-weight overlay, selfplay admission gate, cross-turn coherence via emitted-predicate buffer, ontology depth weighting + sibling borrowing.
- **P1 curation COMPLETE** (`bd0fdd1`, 2026-07-14): `docs/GAPS.md` reports 100% coverage — all 281 gap concepts curated; `resources/knowledge/curated_predicates.jsonl` at 6,238 lines / 4,045 unique topic keys (2026-10-23 count; the historical 6,239-line note was the 2026-07 snapshot). The bulk of the 51 unpushed commits are these batches.

## Current state of the M6 gate

Scope note: the table below is **M6-STRUCTURAL** only. Structural closure is *necessary, not sufficient* for the North Star. **M6-FELT mechanical is proven only on the bounded 12-turn benchmark; the human leg is partial and the formal claim stays withheld**; no structural row upgrades it.

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
4. Promotion/response-plan modules are tracked in the current tree; keep them covered by the architecture gate and CI. No untracked source is currently present.
5. Gate 3 regression fixed 2026-09-08 (HEAD failed `check_architecture.sh` with 6 violations while ci-fast.yml keeps Gate 3 commented out): 5 bare `head`/`last` sites in Semantic/Core made total by construction (ContentSelector, Retrieve, ResponsePlan, Ontology/Dynamic, M6FeltGate — behavior-preserving, `qxfx0-test-fast` 1812/1812 green after), plus rule [11] now whitelists `QxFx0.Core.M6FeltGate` as a test/CI-consumed evidence gate (same boundary rationale as the `*Admission` whitelist). Consider re-enabling Gate 3 in ci-fast or a scheduled job so drift is caught at push time, not at verify.sh time.
6. Measured boot cost (2026-09-08): `qxfx0-test-fast` spends ~215s in 23 `bootstrapSession` calls (median 8.9s each; breakdown: self-blanket ~6s + health probes ~2.7s + state build ~2.5s), which is why the "< 60s" README claim only holds with warm caches and no concurrent load; heap headroom is thin too (3.1GB max residency, OOM-killed under a second concurrent suite). Candidates: memoize `checkHealth`'s nix/souffle probes per process (morphology/PGF are already memoized), and split per-suite `other-modules` (audit P3-6) before adding more live-session slices to the fast gate.

## Open follow-ups — concept v3 and audit 2026-08-23 (mirror)

Mirrored from AGENTS.md so they live in the execution coordinator, not only in the operator log (audit register P3-9):

1. Corpus-level receiver-conditioned decompression via `fieldAwareRendering` (concept v3 §7 calibration phase).
2. Offline fitting of the R5 encoder / move effect matrix on a labelled 30–50 utterance set (hand-set v1 constants are frozen until then; any replacement bumps `currentMathVersion`).
3. Learning-targets ADR for transition learning (`docs/closure/LEARNING_ALLOWED_TARGETS.md` governance).
4. Absorption of the flag-off `ssUserModel` Bayesian niche.
5. test-common compiles all 149 `Test.Suite` modules into each of the 6 suites — split per-suite `other-modules`, measure build time before/after (audit P3-6).
6. `brain_kb.jsonl` is gitignored/external; restored locally 2026-09-21 (53,146 entries), but fresh clones still need the restore contract in `docs/operations/BRAIN_KB_PROVENANCE.md` (audit P3-8, open ops task).

## Notes

- This file is the execution coordinator, and is **internal-only** — never public release evidence.
- Historical summaries belong in `docs/front_archive.md`.
- Program doctrine belongs in `ROADMAP.md`.
- Deferred architecture follow-ups stay in `ROADMAP.md` until a new bounded front is explicitly activated.
- Run slow/runtime suites **sequentially** — concurrent instances are port/subprocess-heavy and corrupt results.
- Slow suite needs `-M12G` for a full single-process run (verified 2026-09-19: 172/172 green; `-M6G`/`-M10G` die near the tail with 0 failures recorded — cumulative heap growth across groups, not a logic bug; per-group runs pass at any cap).
