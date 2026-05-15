# Dual Lexicon Expansion Cycle 1 Report

**Date:** 2026-05-15
**Status:** PARTIAL SUCCESS (EN Complete, RU Deferred)

## Executive Summary

This cycle successfully expanded the English lexicon to meet the target of >=3400 unique lemmas. The Russian lexicon expansion was deferred due to validation issues in existing seed data that require cleanup before proceeding.

## Targets

| Language | Target | Achieved | Status |
|----------|--------|----------|--------|
| EN unique lemmas | >=3400 | 3438 | ✅ MET |
| RU production lemmas | >=3600 | 3155 | ⏸️ DEFERRED |
| Dangerous collisions | 0 | 0 | ✅ MET |
| Lexicon score | >=10.0 | 10.0 | ✅ MET |

## English Expansion

### Details
- **Before:** 3026 unique lemmas
- **After:** 3438 unique lemmas
- **Added:** 412 new lemmas
- **Method:** `scripts/expand_en_lexicon.py` (groups G20-G23)
- **Thematic groups added:**
  - G20: Common nouns (everyday objects, food, nature)
  - G21: Verbs for communication and interaction
  - G22: Adverbs (manner, time, place)
  - G23: Additional everyday nouns

### Validation Results
- **Lexicon check:** PASS (score=10.00, lemmas=3155)
- **EN render path:** PASS (intent_fit=1.0000, gf_output=1.0000, ru_leakage=0.0000)
- **Auto-source quality:** All metrics PASSED
- **Dangerous collisions:** 0

### Artifacts Regenerated
- GF grammar files: `spec/gf/QxFx0Lexicon*.gf`, `spec/gf/QxFx0Syntax*.gf`
- Haskell lexicon source: `src/QxFx0/Lexicon/Generated.hs`
- Morphology JSONs: `resources/morphology/*.json`
- Lexicon snapshot: `spec/lexicon_snapshot.tsv`
- GF funmap: `spec/gf/lexicon_funmap.tsv`
- Agda proofs: `spec/LexiconData.agda`, `spec/LexiconProof.agda`

## Russian Expansion (Deferred)

### Current State
- **RU lemmas:** 3155
- **Target:** >=3600
- **Gap:** 445 lemmas needed

### Issues Encountered

1. **Invalid numbered lemmas in existing seed data:**
   - Found entries like `вид2`, `задача2`, `команда2`, `правило2`, etc. in `seed_ru_curated.sql`
   - These fail validation because the Cyrillic form regex `^[а-яё -]+$` does not allow digits
   - Validation error: `прием2: invalid lemma='прием2'`

2. **SQL UNIQUE constraint violations:**
   - Attempted to add entries that collided with existing (lemma, pos) pairs
   - Required deduplication against both TSV and SQL seeds

3. **Complex deduplication requirements:**
   - Need to check for uniqueness at both lemma level and (lemma, pos) pair level
   - Existing seed data has inconsistencies that need cleanup

### Required Cleanup Before Proceeding

1. Remove or fix invalid numbered lemmas in `seed_ru_curated.sql`:
   - `вид2`, `задача2`, `задача3`, `команда2`, `модель2`, `мотив2`
   - `образ2`, `план2`, `правило2`, `пример2`, `прием2`, `руководство5`
   - `тип2`, `форма2`, `цель2`, `вопрос3`

2. Ensure all lemmas match the Cyrillic form regex `^[а-яё -]+$`

3. Verify no (lemma, pos) duplicate pairs exist across SQL seeds

4. Update `expand_ru_lexicon.py` to:
   - Check against both TSV and SQL seeds for deduplication
   - Skip entries with fun_id collisions instead of generating numbered variants
   - Validate all lemmas against Cyrillic form regex before adding

## Commit Information

- **Commit:** `e420500`
- **Message:** "Expand EN lexicon to 3438 lemmas (target >=3400)"
- **Files changed:** 2 files, 702 insertions

## Next Steps

1. **RU Seed Cleanup (Priority):**
   - Identify and remove all invalid numbered lemmas from SQL seeds
   - Validate existing seed data against quality checks
   - Ensure consistency between TSV and SQL sources

2. **RU Expansion (Cycle 2):**
   - Add 445+ unique Russian lemmas to reach >=3600 target
   - Use improved deduplication logic
   - Validate all entries before adding to SQL seeds

3. **Full Validation:**
   - Run all gates after RU expansion
   - Verify both EN and RU targets met
   - Confirm zero dangerous collisions
   - Achieve PROD_GO verdict on core contract

## Conclusion

Cycle 1 achieved the English lexicon expansion target successfully. The Russian expansion requires seed data cleanup before it can proceed. The technical foundation is in place, and the next cycle can focus on completing the RU expansion once the seed data issues are resolved.
