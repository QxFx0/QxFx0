# EN Lexicon Parity Release

**Date**: 2026-05-15
**Run ID**: ci-20260515-175819
**Status**: PASS

## Summary

Expanded English lexicon from 2205 to 3026 unique lemmas, achieving parity target (>=3000) while maintaining zero dangerous collisions and perfect EN render path quality.

## Before/After Metrics

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| EN rows | 2242 | 3203 | +961 |
| EN unique lemmas | 2205 | 3026 | +821 |
| EN unique fun_ids | 2240 | 3065 | +825 |
| RU rows | 2242 | 2242 | 0 (unchanged) |
| RU unique lemmas | 2236 | 2236 | 0 (unchanged) |
| RU unique fun_ids | 2238 | 2238 | 0 (unchanged) |

## EN Gate Metrics

| Metric | Before | After | Target | Status |
|--------|--------|-------|--------|--------|
| intent_fit_rate | 1.0000 | 1.0000 | >= 0.90 | PASS |
| gf_output_rate | 1.0000 | 1.0000 | >= 0.85 | PASS |
| fallback_rate | 0.0000 | 0.0000 | <= 0.15 | PASS |
| ru_leakage_rate | 0.0000 | 0.0000 | <= 0.05 | PASS |
| critical_mismatch_count | 0 | 0 | == 0 | PASS |

## Lexicon Quality Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| score | 10.00 | >= 10.00 | PASS |
| dangerous_collisions | 0 | == 0 | PASS |
| harmless_collisions | 0 | - | PASS |
| invalid_rows | 0 | == 0 | PASS |

## Thematic Groups Added

Added 20 thematic groups (G1-G20) with 961 new EN entries:

- **G1**: Epistemics/Cognition (50 entries)
- **G2**: Causality/Explanation (40 entries)
- **G3**: Dialogue/Speech Acts (60 entries)
- **G4**: Social/Moral/Affective (50 entries)
- **G5**: Everyday Entities (50 entries)
- **G6**: Nature/Matter/Physical (50 entries)
- **G7**: Space/Time/Motion/Relations (50 entries)
- **G8**: Everyday/Social-Practical (50 entries)
- **G9**: Institutions/Authority (50 entries)
- **G10**: Professional/Technical Neutral (50 entries)
- **G11**: Additional Reasoning/Logic (60 entries)
- **G12**: Additional Communication (60 entries)
- **G13**: Additional Everyday Vocabulary (65 entries)
- **G14**: Additional Social/Institutional (63 entries)
- **G15**: Additional Abstract Concepts (68 entries)
- **G16**: Common Everyday Vocabulary (114 entries)
- **G17**: Additional Common Verbs (103 entries)
- **G18**: Additional Abstract/Conceptual Vocabulary (90 entries)
- **G19**: Additional Descriptive Adjectives (94 entries)
- **G20**: Additional Common Nouns (130 entries)

## Generation Script Fixes

Fixed sorting in `scripts/export_lexicon.py` to ensure deterministic ordering of `generatedLexemeEntries` by (lemma, pos, case_tag).

## Core Contract Status

**CONTRACT_VERDICT: PROD_GO**
- Run ID: ci-20260515-175819
- Profile: core
- All gates: PASS

## Files Changed

- `spec/gf/lexicon_bilingual.tsv` - Added 961 EN entries
- `scripts/expand_en_lexicon.py` - New EN expansion script
- `scripts/export_lexicon.py` - Fixed deterministic sorting
- `spec/gf/QxFx0Lexicon.gf` - Regenerated
- `spec/gf/QxFx0LexiconEng.gf` - Regenerated
- `spec/gf/QxFx0Syntax.gf` - Regenerated
- `spec/gf/QxFx0SyntaxEng.gf` - Regenerated
- `spec/gf/lexicon_funmap.tsv` - Regenerated
- `spec/lexicon_snapshot.tsv` - Regenerated
- `src/QxFx0/Lexicon/Generated.hs` - Regenerated
- `spec/LexiconData.agda` - Regenerated
- `spec/LexiconProof.agda` - Regenerated
- `resources/morphology/nominative.json` - Regenerated
- `resources/morphology/genitive.json` - Regenerated
- `resources/morphology/prepositional.json` - Regenerated
- `resources/morphology/lexicon_quality.json` - Regenerated

## Risks

None identified. All gates pass with zero regressions.
