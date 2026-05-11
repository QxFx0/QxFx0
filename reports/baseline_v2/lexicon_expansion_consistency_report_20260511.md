# Lexicon Expansion Consistency Report (2026-05-11)

## 1. Executive verdict
- **Original claim block is inconsistent with repository evidence.**
- Corrected baseline for commit `7241cab`: **1148 lemmas** (not 2148).
- Current state at commit `d410e49`: **2000 lemmas**, score 10.00, dangerous collisions 0.

## 2. Verified before/after metrics

| Metric | Before (`7241cab`) | After (`d410e49`) |
|---|---:|---:|
| lemmas | 1148 | 2000 |
| score | 10.00 | 10.00 |
| dangerous collisions | 0 | 0 |
| harmless collisions | 0 | 0 |

## 3. Evidence paths

### 3.1 Commit-derived quality metrics
- `git show 7241cab:resources/morphology/lexicon_quality.json` → `lemma_count=1148`
- `git show d410e49:resources/morphology/lexicon_quality.json` → `lemma_count=2000`

### 3.2 Gate logs
- `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260511-175548_core.log` confirms: `lemmas=1148`
- `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260511-203424_core.log` confirms: `lemmas=2000`

### 3.3 Core contract run reference
- `reports/baseline_v2/final_gates/_gate_results_ci-20260511-203424_core.md` exists and shows gates 1–10 PASS in the available content.
- Important: this file in current workspace snapshot is truncated (no final `CONTRACT_VERDICT` line in-file), so explicit `PROD_GO` text claim is **not confirmed from this file alone**.

## 4. Corrected checkpoint status
- Phase 1 (>=1500): **PASS** (reached in later state, see current 2000).
- Phase 2 (>=2000): **PASS** (commit `d410e49`).

## 5. Corrected commit references
- Historical expansion commit: `7241cabcd476053563d20299dee03d2432ec9334` (actual lemma_count=1148)
- Current consolidated state: `d410e49f1247` (lemma_count=2000)

## 6. Conclusion
The earlier “1016 -> 2148” report is not reproducible from current repository evidence. The reproducible, verified transition is **1148 -> 2000**, with lexical quality preserved at 10.00 and zero dangerous collisions.
