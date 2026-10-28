# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `POST-RELEASE — B2/M6-FELT/M7 evidence`
- `current_state`: `main` is published through `6788c9f` (docs-only M6/M7 record on top of the 55-commit fast-forward `045f37a..f70607d`); `origin/main...main` is `0/0`. The mapped-predicate fallback is **implemented in the working tree but not committed**: response-plan selection + `DeriveGfMappedFallback` + tests + post-fix M7 docs. The post-fix 30-prompt packet (run `m7-gf-fallback-20261026`) is **PASS on the canonical-mapping gate**: `AuthorityCanonical` 30/30, `AuthorityShim` 0/30, `unmapped_curated_predicate` 0/30, `trcLinearizationOk=true` 30/30; exact golden **5/30**, so **M7 remains OPEN**. One fallback-selected surface exposed a pre-existing GF case defect (`ObjectAktObrashcheniya`, instrumental vs nominative). Unit suite on the new code is 1820/1820 green; fast 1918/1918, property 244/244, integration 47/47, and the main core slice 1254/1254 were re-verified on the same tree on 2026-10-28 (all exit 0; main runtime/http and slow not re-run). Remaining release caveats: 500-prompt gate BLOCKED (no labeled Russian set); B2/M6-FELT human leg partial; M7 content acceptance unresolved.
- `last_updated`: `2026-10-28`
- `evidence_or_result_ref`: `docs/closure/CALIBRATION_REPORT.md` (release verification follow-up 2026-10-25/26); CI runs `40343025029` / `40343024720`; gate snapshot below.

### Second live front — promotion V4 (human review)

- `front_id`: `PROMOTION-V4 — governed promotion chain + response plan`
- `current_state`: Promotion/response-plan subsystem is **tracked** in the current tree (no untracked source files); draft overlay remains inactive.
- `blocker`: **`human_review_required`** — automated runtime gate passes, activation eligible `false`. Repo-owner decision, not a code gap.
- `evidence_or_result_ref`: `reports/promotion-v4-release-cycle-20260719.md` (+ 7 sibling `reports/promotion-*-20260719.md`, `reports/*selector-preflight*-20260719.md`)

## Immediate next action

1. **Resolve the 500-prompt gate blocker.** The labeled 500-prompt Russian set is absent; the current script falls back to the ~60-prompt English baseline. Build/label the set before claiming the gate ran. The 30-prompt GF packet is not a substitute.
2. **B2/M6-FELT:** M6-FELT is informational, not a release gate (operator decision 2026-10-26). Keep the formal claim withheld; revisit only if a second independent rater and a pre-registered threshold are commissioned.
3. **M7:** the mapped-predicate fallback closed the hard mapping failure on the 30-prompt packet (`AuthorityCanonical` 30/30, `AuthorityShim` 0/30, exact golden 5/30). Keep M7 **OPEN**: decide the golden acceptance rule for the 25 non-exact canonical turns, then fix the pre-existing `ObjectAktObrashcheniya` GF case defect under a separate pre-registration and re-run. Evidence: `docs/closure/M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`.
4. **Resolve Promotion-V4 `human_review_required`** — either attest the review and activate the draft overlay (`overlay-42c1335b…`), or record a documented refusal. Draft has been inactive since 2026-07-19.
5. **Do not widen the canary yet.** The 30-prompt packet is canonical 30/30 but exact golden 5/30; 1 turn is still not a corpus. Keep the canary narrow until the content-acceptance rule and the 500-prompt set exist.

### Gate status snapshot (2026-10-28)

Pre-fallback tree (published through `6788c9f`, docs-only after code HEAD `e7f749b`): unit 1818, fast 1918, property 244, integration 47 (2026-10-26); main 1383 by group (core 1254 + runtime 106 + http 23) and slow 190 by group (runtime 106 + state 50 + http 23 + lifecycle 11) (2026-10-25) — all exit 0. CI Core Contract `40343025029` green (`2h35m37s`), CI Fast `40343024720` green (`25m35s`). **Fallback tree (working tree, uncommitted)**: unit 1820/1820, fast 1918/1918, property 244/244, integration 47/47, main core 1254/1254 — all exit 0 (2026-10-28); `Test.Suite.ResponsePlan` 38/38; main runtime/http and slow not re-run on this tree. `git diff --check` and full `check_architecture.sh` are green before any commit request. Full single-process main remains unsupported on 15 GB with substrate. Do not cite gates against any other tree without re-running.

## Open decisions / blockers

| item | kind | owner | note |
|---|---|---|---|
| ~~Publish 55 unpushed commits to `origin/main`~~ | release decision | repo owner | **DONE 2026-10-26**: fast-forward `045f37a..f70607d`; CI green. |
| ~~Uncommitted promotion/response-plan subsystem~~ | hygiene | repo owner | **RESOLVED for the pre-publication subsystem**: no untracked source files remain from it. The 2026-10-26 mapped-predicate fallback is intentionally uncommitted pending explicit approval (see `current_state`). |
| Promotion-V4 draft activation | human review | repo owner | `human_review_required`; snapshot `promotion-snapshot-aa7e60d4…`, 17700 edges, 9 candidates → 1 gate-eligible |
| Architecture check | hygiene | repo owner | **GREEN on HEAD** (`49d8faa`): ownership-journal partials totalized, anti-rot registry label synced; full run includes rule [10]. |
| Release verification | release evidence | repo owner | **CLOSED for the pre-fallback tree (2026-10-26)**: unit 1818, fast 1918, property 244, integration 47, main 1383, slow 190 — all exit 0; architecture check green. Fallback tree (2026-10-28): unit 1820, fast 1918, property 244, integration 47, main core 1254 — all exit 0; main runtime/http and slow not re-run. |
| CI on published HEAD | release evidence | repo owner | **GREEN (2026-10-26)**: Core Contract `40343025029` (`2h35m37s`), CI Fast `40343024720` (`25m35s`). |
| 500-prompt dialogue eval | release evidence | repo owner | **BLOCKED**: no labeled 500-prompt Russian set; script falls back to ~60 English prompts. |
| M6-FELT | research | — | **MECHANICAL PROVEN (bounded 12-turn benchmark); HUMAN PARTIAL; formal claim withheld; informational, NOT a release gate (operator decision 2026-10-26)** — see `M6_FELT_GATE.md`, B2 EXEC-002/003 |
| M7 production evidence | research/ops | repo owner | **OPEN**; post-fix 30-prompt packet is canonical **30/30** with 0 shims, but exact golden is **5/30** and one GF case defect is exposed. Decide golden acceptance + fix `ObjectAktObrashcheniya`; do not claim M7 closed. |

## Recently landed (2026-06-18 → 2026-10-28)

Summaries only — details live in the ADRs and in `docs/front_archive.md`.

- **Publication** (`f70607d`, 2026-10-26): `main` fast-forward `045f37a..f70607d` (55 commits); CI Core Contract `40343025029` and CI Fast `40343024720` green.
- **M7 bounded packet** (`M7_BOUNDED_PACKET_2026-10-26.md`, 2026-10-26): 30-prompt GF release corpus; routing `CMDefine` 30/30; trace `AuthorityCanonical` 16/30; 14/30 `unmapped_curated_predicate` → `AuthorityShim`; exact golden 4/30. **FAILED (pre-fix)**; retained as trigger evidence.
- **M7 mapped-predicate fallback** (`M7_GF_MAPPING_FALLBACK_PREREG_2026-10-26.md` + `M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`, working tree 2026-10-26/28): response-plan selection now filters to GF-mapped predicates per topic, emits `DeriveGfMappedFallback` with the rejected original, and retains the old shim path when no mapping exists. Post-fix packet: `AuthorityCanonical` 30/30, `AuthorityShim` 0/30, `unmapped_curated_predicate` 0/30, exact golden 5/30. M7 remains OPEN on content acceptance; one pre-existing GF case defect exposed.
- **Bootstrap-safety fallback** (`203ffbf`, `b98a833`, `c201a80`, 2026-10-24): `--turn-json` and `--worker-stdio` now serve the real Protocol B resource pack when strict bootstrap fails on an acute crisis marker; non-crisis bootstrap failures still fail closed. Healthy runtime path unchanged. Pin: `Test.Suite.CrisisGuard` 20 cases; all six suites exact-tree green (2026-10-25/26).
- **ADR-0050** compose-from-activation surface text (`SurfaceAccumulator`, wired into `generateFromFrame`, golden tests + feature flag).
- **ADR-0051** typed dispatch across all gates (a–h): `SemanticFrameTarget`, `DreamCandidateKind`, `ConflictPolicy`, `TransportMode`, `RuntimeMode`/`HealthStatus`, `ParserStatus`, `PipelineEffectLabel`, parameterized `PropositionAdmissionConfig`.
- **ADR-0052** relation-graph external knowledge: 666 curated relations exported to JSONL, `ontology.jsonl` + `Ontology` module, provenance-aware network merge, field-modulated spreading activation, `ingest` CLI, ontology-driven category classification.
- **ADR-0053** runtime-LLM discovery bridge to the semantic network.
- **ADR-0054 M1–M4** autonomous semantic expansion: M1 infrastructure → M2 content-density gate → M3 end-to-end loop-closure test + `spawnAutonomousLearningHandles` in Bootstrap → M4 runtime-ready safety (`Learning/Quarantine.hs`, `Learning/CircuitBreaker.hs`, `Test/Suite/AutonomousSafety.hs`, all first landed in `c02549a`, 2026-07-16). Plans: `docs/superpowers/plans/2026-07-11-ADR-0054-M{3,4}-runtime-ready.md`.
- **Closure Round** (`docs/plan/closure-round-tz.md`, 2026-07-09) — diagnosed pattern **write-without-read ×3**: atom-graph seed default-on, feedback read-side + relation-weight overlay, selfplay admission gate, cross-turn coherence via emitted-predicate buffer, ontology depth weighting + sibling borrowing.
- **P1 curation COMPLETE** (`bd0fdd1`, 2026-07-14): `docs/GAPS.md` reports 100% coverage — all 281 gap concepts curated; `resources/knowledge/curated_predicates.jsonl` at 6,238 lines / 4,045 unique topic keys (2026-10-23 count; the historical 6,239-line note was the 2026-07 snapshot). The bulk of the published 55 commits are these batches.

## Current state of the M6 gate

Scope note: the table below is **M6-STRUCTURAL** only. Structural closure is *necessary, not sufficient* for the North Star. **M6-FELT mechanical is proven only on the bounded 12-turn benchmark; the human leg is partial and the formal claim stays withheld; M6-FELT is informational, not a release gate (2026-10-26)**; no structural row upgrades it.

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
