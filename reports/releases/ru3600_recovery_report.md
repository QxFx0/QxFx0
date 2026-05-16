# RU3600 Recovery Report

## Executive Summary
* **RU3600_RECOVERY:** PASS
* **CORE_CONTRACT:** PROD_GO

## Root Cause & Fix
* **Issue:** The `spec/sql/lexicon/seed_ru_curated.sql` file had syntax errors (isolated commas) and the TSV/SQL files contained duplicate surface forms (e.g., `антенна`, `астра`), which caused `check_lexicon.sh` and the generated artifact checks to fail. This blocked the core contract.
* **Fix:** 
  1. Manually removed the syntax errors and duplicate entries from the SQL and TSV files.
  2. Modified `scripts/expand_ru_lexicon.py` to ensure it skips generating any candidate lemma whose surface forms collide with existing ones, or contains invalid characters, ensuring deterministic and safe expansion.
  3. Regenerated the GF, Agda, and Haskell artifacts.

## Metrics
* **RU unique lemmas:** 3587 -> 3608
* **EN unique lemmas:** 139 -> 139
* **Score:** 10.00 -> 10.00
* **Dangerous collisions:** 8 -> 0

## Core Gates (RUN_ID: `ci-20260516-042551`)
* `cabal build all`: PASS
* `cabal test qxfx0-test-fast`: PASS
* `QXFX0_CONTRACT_PROFILE=core bash scripts/ci_gate_contract.sh`: PROD_GO