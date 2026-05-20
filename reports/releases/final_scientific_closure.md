# Final Scientific Closure Report

- **Branch:** `main`
- **Closure SHA:** `d4563391aadd9e7cc206e7e29750cdda4549b831`
- **Date:** 2026-05-20
- **Scope:** Agda formalization + Nix reproducibility + canonical gate verification

---

## 1. Executive Verdict

- **AGDA_FORMAL_STATUS:** **PASS**
- **NIX_REPRO_STATUS:** **PASS**
- **SCIENTIFIC_CLOSURE:** **PASS_BY_INDIVIDUAL_GATES**
- **CONFIDENCE:** **HIGH** — all individual gates pass, Agda typechecks, Nix reproduces

---

## 2. Formal Proofs Summary (Agda)

| Lemma | Status | File | Description |
|-------|--------|------|-------------|
| `stickyCommitment` | **PASS** | `spec/EssenceFormalization.agda:55` | Once `Committed`, never reverts to `Uncommitted` (exhaustive pattern match on `Committed m t` → `()`) |
| `refusedCommitmentImpossible` | **PASS** | `spec/EssenceFormalization.agda:64` | If trigger present but state stays `Uncommitted` → contradiction (only `NoTrigger` preserves `Uncommitted`) |
| `uncommittedAdaptIdentity` | **PASS** | `spec/EssenceFormalization.agda:82` | Adaptation on `Uncommitted` is strict identity (`refl`) |
| `committedAdaptNonTrivial` | **PASS** | `spec/EssenceFormalization.agda:88` | Adaptation on `Committed` applies `adaptParam` (`refl`) |
| `prepareTimeDeterministic` | **PASS** | `spec/EssenceFormalization.agda:107` | Fixed injected time → fixed `startTime` in prepare result (`refl`) |

**Typecheck result:** `nix run .#typecheck-agda` — all 6 modules PASS:
`R5Core.agda`, `Sovereignty.agda`, `Legitimacy.agda`, `LexiconData.agda`, `LexiconProof.agda`, `EssenceFormalization.agda`.

---

## 3. Nix Reproducibility

| Command | Exit | Verdict | Notes |
|---------|------|---------|-------|
| `nix run .#typecheck-agda` | 0 | **PASS** | Clean compile, all 6 modules |
| `nix flake check` | 0 | **PASS** | Pre-existing `pgf2` broken warning (non-blocking; known upstream issue) |

---

## 4. Core Gate Table

| # | Command | Exit | Verdict | Key Metrics |
|---|---------|------|---------|-------------|
| 1 | `cabal build all` | 0 | **PASS** | Clean build |
| 2 | `cabal test qxfx0-test-fast` | 0 | **PASS** | 469/469 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` | 0 | **PASS** | 596/596 cases, 0 errors, 0 failures |
| 4 | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings |
| 6 | `bash scripts/check_gf_render_path.sh` | 0 | **PASS** | 30 turns, fallback=0.0000 |
| 7 | `bash scripts/check_en_render_path.sh` | 0 | **PASS** | 30 turns, intent_fit=1.0000, fallback=0.0000 |
| 8 | `bash scripts/check_generated_artifacts.sh` | 0 | **PASS** | PGF present |
| 9 | `bash scripts/check_lexicon.sh` | 0 | **PASS** | score=10.00, lemmas=3756 |

---

## 5. Deferred / INFRA Checks

| Check | Reason | Mitigation |
|-------|--------|------------|
| `ci_gate_contract.sh` (aggregate) | Timeout >300s on low-RAM runner | All constituent individual gates pass; deferred to CI with >=32 GB RAM |
| `release-smoke.sh` | Extended corpus replay >120s | Fast/meta suites cover core paths; deferred to high-mem runner |

---

## 6. Residual Risks (Actual)

1. **Phase B adaptation identity-only.** Signal=0.0 — no empirical tuning. Bounded infrastructure validated; calibration deferred to Phase 7.
2. **GF compiler unavailable.** EN linearization is Haskell-native. New EN families require manual handler addition.
3. **Agda formalization is constructive specification, not machine-checked equivalence to runtime.** It formalizes the *laws* (sticky commitment, adaptation gating, time determinism) as independent type-level lemmas. Full extraction / equivalence proof to Haskell runtime is future work.
4. **Nix `pgf2` broken warning.** Non-blocking; known upstream. Does not affect build or Agda compilation.
5. **Low-RAM build profile (`-O1`, single job).** Performance characteristics on high-mem runner may differ.

---

## 7. Files Changed in This Closure

- `spec/EssenceFormalization.agda` — new Agda formalization module
- `flake.nix` — added `EssenceFormalization.agda` to `compile-agda` target
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` — updated SHA, added Agda/Nix gates
- `reports/releases/final_scientific_closure.md` — this report

---

## 8. Acceptance Criteria

- [x] Agda lemmas typecheck via `nix run .#typecheck-agda`
- [x] Nix reproducibility confirmed (`nix flake check` exit 0)
- [x] All 9 core individual gates PASS
- [x] Docs/evidence consistent with actual command outputs
- [x] No claims at FULL_SCIENTIFIC_GO level beyond verified scope
- [x] Git status clean

---

## 9. Commit SHAs (This Closure Round)

```
d456339 spec(agda): formalize commitment law, adaptation gating, and prepare-time determinism
```

---

*Report maintained by release/reliability engineer.*
