# Known pre-existing test failures (fast suite)

**Captured:** 2026-06-04 · **Suite:** `qxfx0-test-fast` (1015 cases) · **Status:** 17 failures, all pre-existing or environmental.

## Context

The `main` branch was already red before the cognitive-roadmap work began:
`865e375` (last commit before this session) failed **12** of the fast suite.
The in-tree WIP refactoring (Proposition split + SelfState consolidation)
temporarily raised this to 26; root-cause fixes for the refactor
(detection-chain restoration, SystemState JSON schema, sandbox test premise)
brought it to **17**. None of the remaining 17 are caused by the roadmap work or
the refactor — they are pre-existing port redness or environmental.

These are documented here so the roadmap (Track I/II) proceeds against a known
baseline rather than chasing failures it did not introduce. Each TZ work package
must not *increase* this count.

## Environmental (cannot be fixed in source; need artifacts/services) — 5

| Suite:line | Test | Cause |
|---|---|---|
| CoreBehavior.hs:745 | explicit remote backend failure | no remote embedding service in sandbox |
| CoreBehavior.hs:759 | blocked remote embedding host | no remote embedding service in sandbox |
| CoreBehavior.hs:772 | missing remote embedding URL | no remote embedding service in sandbox |
| M6Witness.hs:131 | GF grammar has MoveActOnTopic | `spec/gf/QxFx0Syntax.gf` not regenerated (no `MoveActOnTopic`) |
| M6Witness.hs:201 | EVIDENCE_INDEX.md exists | `reports/m6_evidence/EVIDENCE_INDEX.md` absent on disk |

## Pre-existing port bugs (failing at 865e375) — 12

| Suite:line | Test |
|---|---|
| LearningLoop.hs:695 | telemetry must report executed tool, not planned tool |
| LearningLoop.hs:718 | transport error before executed identity must not mutate reliability |
| LearningLoop.hs:738 | fallback path must keep telemetry actor-clean |
| LearningLoop.hs:753 | no-result path must keep telemetry actor-clean |
| LearningLoop.hs:1190 | old SystemState JSON must decode |
| LearningLoop.hs:1631 | stored predictive delta must not preserve remote 999.0 authority claim |
| LearningLoop.hs:1648 | inflated remote predictive claims must not cause later promotion from quarantine |
| Guardrails.hs:95 | quarantine prunes stale entries |
| ReliabilityHardening.hs:182 | llm-blocked-host-dev-override |
| ReliabilityHardening.hs:189 | llm-blocked-host-double-confirm |
| TurnPipelineProtocol.hs:3366 | structured turn should preserve expected family (CMGround vs CMReflect) |
| TurnPipelineProtocol.hs:4367 | top-level mutation log must include P4 mutation |

## Fixed during WIP stabilization (no longer failing)

- Proposition detection chain (5 taxonomy failures) — `Proposition/Detectors.hs` migration.
- SystemState JSON round-trip (3 failures) — `requiredTopLevelFields` matches `ssSelfState` ToJSON.
- SandboxBoundary below-floor test (1) — test premise corrected to drive the derived conatus delta via a weak definition.

## Note

`LearningLoop.hs:1190` ("old SystemState JSON must decode") is a *backward-compat*
decode of a legacy fixture; it may be related to the SelfState schema change and
is a candidate for a follow-up fix, but it predates this session's scope
(failing at 865e375) and is left as-is per the agreed "fix only WIP-new" scope.
