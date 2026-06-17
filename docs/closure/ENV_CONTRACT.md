# Environment Contract (SLICE-012)

- **Status**: Active
- **Date**: 2026-06-17
- **Related**: `docs/closure/SLICE-012_PLAN.md`, `audit-objective-2026-06-17.md §3`

## Policy

> Guard Unavailable is allowed runtime degradation, but forbidden proof
> substrate.

## Two environment classes

### Governed-evidence environment

Required for any run whose trace will be cited as M6 evidence ("governed",
"checked"):

| Requirement | Env var / condition | Purpose |
|---|---|---|
| Nix guard installed | `nix-instantiate` on PATH (or `QXFX0_NIX_INSTANTIATE_BIN`) | Constitutional guard can run |
| Concepts path | `QXFX0_CONCEPTS_PATH` set, or `semantics/concepts.nix` resolvable from `QXFX0_ROOT` | Guard can find concept definitions |
| Governed-evidence mode | `QXFX0_GOVERNED_EVIDENCE=1` | Fail-closed on Unavailable guard; trace marked `EvidenceInadmissible` |
| Morphology resources | `forms_by_surface.json` regenerated (`python3 scripts/export_lexicon.py`) | Runtime can bootstrap (SLICE-010B) |
| GF runtime | `QXFX0_GF_RUNTIME=1` + GF C runtime built | Surface generation path active |

In this environment:
- Guard `Allowed`/`Blocked` → `EvidenceGoverned` (trace admissible)
- Guard `Unavailable` → `EvidenceInadmissibleFailure` thrown (fail-closed; no trace committed)

### Degraded-dev environment (local, non-governed)

| Condition | Effect |
|---|---|
| Nix not installed or concepts path unset | Guard `Unavailable`; trace marked `EvidenceDegradedGuardUnavailable` |
| `QXFX0_GOVERNED_EVIDENCE` not set | Normal mode: `Unavailable` is fail-open degraded; turn proceeds |
| Morphology not regenerated | Bootstrap fail-closed (`RcMorphology NotReady`) — separate issue (SLICE-010B) |

In this environment:
- Runtime may produce output (degraded behavior is a separate axis)
- Trace carries `EvidenceDegradedGuardUnavailable` for observability
- **Trace is NOT admissible as M6 evidence**

## CI mapping

| CI job | Nix? | `QXFX0_GOVERNED_EVIDENCE` | Evidence admissible? |
|---|---|---|---|
| Core Contract (`ci.yml` core-contract) | ❌ not installed | not set | ❌ not governed |
| Extended Contract (`ci.yml` extended-contract) | ✅ installed | `=1` | ✅ governed (if guard `Available`) |
| CI Fast (`ci-fast.yml`) | ❌ | not set | ❌ not governed (lint/format only) |

## Orthogonality

`QXFX0_GOVERNED_EVIDENCE` is **orthogonal** to `QXFX0_RUNTIME_MODE`
(strict/degraded):
- `QXFX0_RUNTIME_MODE` governs **runtime safety** (how the pipeline handles
  degraded conditions).
- `QXFX0_GOVERNED_EVIDENCE` governs **evidence admissibility** (whether the
  trace can be cited as proof).

A run can be strict + governed, strict + non-governed, degraded + governed,
or degraded + non-governed. The four combinations are all valid; only
`governed + guard Available` produces admissible evidence.

## `EvidenceAdmissibility` trace field

Every `TurnReplayTrace` now carries `trcEvidenceAdmissibility`:
- `EvidenceGoverned` — guard was present and checked.
- `EvidenceDegradedGuardUnavailable` — guard was absent (normal mode).
- `EvidenceInadmissible` — guard was absent under governed-evidence mode
  (fail-closed; trace not committed).

See `src/QxFx0/Types/Evidence.hs`, `src/QxFx0/Core/EvidenceAdmissibility.hs`.
