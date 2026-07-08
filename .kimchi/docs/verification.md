# Verification Report

## Root Cause

In `src/QxFx0/Render/Dialogue.hs`, the `DefinitionFrame`, `ReflectFrame`, and `ChallengeFrame` branches of `generateFromFrame` took an unconditional "contextual orientation" path whenever `composeContextual` produced non-empty text. That path did not gate on `selectorHasTopic`, so even an `emptyContentSelector` triggered corpus-derived predicate generation (via `lookupDefinitionContent` / generic definition content) and replaced the fallback template entirely. The fallback template + supplement path existed but was only reached when the generated text was empty, and the supplement itself was built from ungated corpus lookups.

## Exact Fix

Modified `src/QxFx0/Render/Dialogue.hs` only:

- `DefinitionFrame`: removed the `if not (T.null genText) ...` early-return branch and the ungated `lookupDefinitionContent` fallback. Now always builds the fallback template and appends a supplement only when the topic is non-blank/whitespace and `selectorHasTopic cs topic` is `True`.
- `ReflectFrame`: removed the `if not (T.null genText) ...` early-return branch. Now always returns the fallback template, appending a supplement only when the topic is non-blank/whitespace and `selectorHasTopic cs topic` is `True`.
- `ChallengeFrame`: removed the `if not (T.null genArgText) ...` early-return branch. Now always returns the soft/firm fallback template, appending a supplement only when `rawObj` is non-blank/whitespace and `selectorHasTopic cs rawObj` is `True`.

All three branches now use `appendSupplement base supplement`, which preserves the base template and appends predicate text only when a non-empty supplement is available.

No test file changes were required; `test/Test/Suite/DialogueSemanticSelection.hs` already asserts that enriched output contains both the base template text and the selected predicate text.

## Test Output

```
cabal test qxfx0-test-fast
Cases: 1293  Tried: 1293  Errors: 0  Failures: 0
Test suite qxfx0-test-fast: PASS
1 of 1 test suites (1 of 1 test cases) passed.
```

The 8 previously failing semantic-selection tests now pass, and no regressions were introduced in the full fast suite.

## Lint Output

```
hlint src/QxFx0/Render/Dialogue.hs
No hints
```

## Verdict

ALL_PASS
