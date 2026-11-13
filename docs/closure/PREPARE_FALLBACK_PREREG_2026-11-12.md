# Pre-registration — a missing nix-guard request must not masquerade as governed evidence (2026-11-12)

- **Status**: PRE-REGISTERED; implementation and verification recorded below.
- **Trigger**: the last P3 tech-debt item from the audit 2026-10-16 —
  `Prepare/Resolve.hs:75` "fallback `Blocked` трактуется как
  available/governed". The operator note of 2026-10-23 ("В техдолге
  остаются tmp-fsync и `Prepare/Resolve` fallback") is the remaining
  half; `tmp-fsync` closed 2026-11-11.
- **Scope**: one fallback value, one new test suite, one pre-registration.
  No new trace field, no corpus, no GF, no prompt file, no threshold.
- **Owner decision**: 2026-11-12, item (1) of the follow-up list.

## Problem

`resolvePrepareEffects` resolves the five prepare-stage effects and then
reconstructs each result with `fromMaybe <fallback>`. For the nix guard the
fallback is:

```haskell
nixStatus = fromMaybe (Blocked "nix_guard_missing_request") $ do
  TurnResNixGuard value <- lookup PelNix (filter (isNixResult . snd) results)
  Just value
```

Downstream, `Blocked _` means *the guard was consulted and refused the
concept*. Two consumers rely on that reading:

| consumer | reading of `Blocked` |
|---|---|
| `classifyEvidence` (`Core/EvidenceAdmissibility.hs:58`) | `EvidenceGoverned` — the guard was present and checked |
| `Prepare/Build.hs` (`nixAvailable`) | `True` — guard available, only the concept is refused |

So if the interpreter ever returns an unexpected constructor for
`TurnReqNixGuard` (a contract violation, not a normal path), the turn is
stamped as *governed evidence* even though the guard was never consulted,
and it keeps the guard-available stance. That is a truth-contract lie: the
one thing the classification layer exists to prevent.

Today the fallback is **not reachable on the live path**:
`prepareRequestToTurnEffect` returns `Just` for all five
`PrepareEffectRequest` constructors, so `lookup PelNix` only fails when the
interpreter breaks its own contract. The defect is latent, and the fix must
not change the live path.

## Change

1. A pure value `missingGuardRequestStatus :: NixGuardStatus` =
   `Unavailable "nix_guard_missing_request"` is added to the **exposed**
   `QxFx0.Core.EvidenceAdmissibility` (the classification layer it serves)
   and used by the `Prepare/Resolve.hs` fallback instead of the inline
   `Blocked "nix_guard_missing_request"`. The reason string is unchanged, so
   log/trace text stays greppable. The value lives in the exposed module
   because `QxFx0.Core.TurnPipeline.Prepare.Resolve` is a hidden module and
   the test suites may import only exposed modules.
2. No other fallback changes. The other four are already honest:
   `fallbackEmbeddingResult` carries `EmbeddingLocalImplicit`,
   `apiHealthy` falls back to `False` (degraded), and consciousness/intuition
   fall back to their documented defaults.
3. New `Test.Suite.EvidenceAdmissibility` pins the classification table and
   the fallback value.

### What the change does on the (unreachable) fallback path

| | before | after |
|---|---|---|
| `classifyEvidence` normal mode | `EvidenceGoverned` | `EvidenceDegradedGuardUnavailable` |
| `classifyEvidence` governed mode | `EvidenceGoverned` | `EvidenceInadmissible` → precommit fail-closes |
| `nixAvailable` | `True` | `False` → `ExplicitFallbackSurface`, `feralDegradation` |
| trace text | `nix_guard_missing_request` | unchanged |

## Bars

| # | Bar | Measure |
|---|---|---|
| A1 | The fallback no longer claims governance | `missingGuardRequestStatus == Unavailable "nix_guard_missing_request"`; `classifyEvidence False` on it is `EvidenceDegradedGuardUnavailable`, `classifyEvidence True` is `EvidenceInadmissible` |
| A2 | The classification table is pinned as it is | `Allowed` → `EvidenceGoverned`, `Blocked _` → `EvidenceGoverned`, `Unavailable _` normal → degraded, governed → inadmissible |
| A3 | The fallback stays unreachable on the live path | `prepareRequestToTurnEffect` has no `Nothing` branch — the `case` is exhaustive over all five constructors and the project builds with `-Werror`, so a sixth constructor or a `Nothing` branch breaks the build rather than the runtime. **Enforced by the compiler, not by a value-level pin** (constructing `SemanticInput`/`SalienceWeights`/`SemanticConfig` fixtures for a pin would test the fixture, not the property) |
| A4 | No live-path change | M7 30-prompt packet on the landing tree: gate 30/30, `gf_mapped_fallback` 0/30, **0/30** predicate and **0/30** surface mismatches vs `m7-harness-20261111` |
| A5 | Red check fails on the unfixed path | restoring `Blocked "nix_guard_missing_request"` fails exactly the fallback pin(s) and nothing else |
| A6 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups) |

## Residual risks (accepted, documented)

1. **The pipeline-level effect is argued, not observed.** The fallback is
   reachable only by breaking the interpreter contract, so no test drives the
   real pipeline through it. The pins cover the pure value and the
   classification; the `nixAvailable` consequence follows from the `case`
   in `Prepare/Build.hs`, which A1 does not execute. A test that fakes a
   contract violation would have to construct a `PipelineIO` whose
   interpreter returns the wrong constructor — that is a new fake, and the
   fixture family deliberately keeps the contract total instead.
2. **A genuine `Blocked` is still `EvidenceGoverned`.** That is correct: a
   refusal by a present guard *is* a governed decision. Only the
   never-consulted case changes.
3. **`Unavailable` already has live producers** (the guard can be
   unavailable when the nix store is missing). This change does not alter
   their behaviour; it only stops the fallback from impersonating `Blocked`.

## Result (2026-11-13)

| # | Bar | Verdict | Evidence |
|---|---|---|---|
| A1 | Fallback no longer claims governance | **PASS** | `test/Test/Suite/EvidenceAdmissibility.hs`, 6 cases: the fallback pin asserts `EvidenceDegradedGuardUnavailable` in normal mode and `EvidenceInadmissible` in governed mode |
| A2 | Classification table pinned as is | **PASS** | same suite: `Allowed` → governed, `Blocked _` → governed in both modes, `Unavailable _` → degraded / inadmissible |
| A3 | Fallback unreachable on the live path | **PASS (compiler-enforced)** | `prepareRequestToTurnEffect` has no `Nothing` branch; `-Werror` makes a new constructor or a `Nothing` branch a build failure. No value-level pin — see the residual risk |
| A4 | No live-path change | **PASS** | M7 30-prompt packet `m7-prepare-fallback-20261113` (strict, isolated): gate **30/30**, `gf_mapped_fallback` **0/30**, **0/30** predicate and **0/30** surface mismatches vs `m7-harness-20261111` (`determinism-vs-baseline.txt`), realizability 462/462 |
| A5 | Red check fails on the unfixed path | **PASS** | restoring `Blocked "nix_guard_missing_request"` fails **exactly 2** cases — `Evidence missing nix request does not claim governance` and `Evidence missing nix request keeps its reason string` — and nothing else; the classification-table cases stay green, which is the point |
| A6 | Landing matrix | **PASS** | matrix 2026-11-13 (`reports/eval_runs/_logs/matrix-20261113/`): 10/10 steps exit 0, tree byte-identical start→end — unit 1845, fast 1938, property 244, integration 47, main runtime 106 + http 23, slow 190 (runtime 106 / state 50 / http 23 / lifecycle 11) = **4 393 cases**, 0 errors, 0 failures |

Measured commands:

```
QXFX0_UNIT_SUITE=EvidenceAdmissibility cabal run -v0 qxfx0-test-unit -- +RTS -M6G -RTS
  -> Cases: 6  Tried: 6  Errors: 0  Failures: 0
red check (fallback back to Blocked)
  -> Cases: 6  Tried: 6  Errors: 0  Failures: 2
scripts/run_m7_batch.sh m7-prepare-fallback-20261113
  -> gate 30/30, gf_mapped_fallback 0/30, realizability 462/462
compare-m7.py m7-harness-20261111 m7-prepare-fallback-20261113
  -> rows 30, row set 0, predicate 0/30, surface 0/30, PASS
```

The landing also touched `qxfx0.cabal` (module registration in `test-common`)
and `test/TestMainUnit.hs` / `test/TestMainFast.hs` (suite registration).
