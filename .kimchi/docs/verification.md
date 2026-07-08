# Verification Report: SemanticFrameTarget Refactor Fix

## Root Causes

### Failures 1 & 2 — structured turn fragments missing

- **Location**: `test/Test/Suite/TurnPipelineProtocol.hs` (`testSelfKnowledgeAboutSelfRendersStructuredDescription` and `testSelfKnowledgeWhatYouAreRendersStructuredDescription`).
- **Cause**: Generic self-knowledge inputs (e.g. `"что ты знаешь о себе?"`, `"чем ты являешься?"`) infer the semantic target string `"self"`. `semanticFrameTargetFromText` maps `"self"` to the known constructor `SftSelfReflection`. In `src/QxFx0/Render/Dialogue.hs`, `selfKnowledgeSurfaceByTarget` had a dedicated `SftSelfReflection` branch that produced reflection-specific text and did **not** contain the expected generic phrases `"свою роль"` and `"типизированный разбор"`. Previously, when `ipfSemanticTarget` was plain `Text`, `"self"` fell into the catch-all rendering path that did include those phrases.

### Failure 3 — legacy arbitrary string round-trip

- **Location**: `test/Test/Suite/RoundTrip.hs` (`legacy string arbitrary`).
- **Cause**: The test used a `BSL.ByteString` string literal containing Cyrillic characters: `A.decode "\"логичность\""`. `ByteString`'s `IsString` instance truncates each `Char` to its low 8 bits, so the UTF-8 Cyrillic string was corrupted into `";>38g=>abl"`. The decoder then produced `SftOther ";>38g=>abl"` instead of `SftOther "логичность"`.

## Fixes Applied

### 1. `src/QxFx0/Render/Dialogue.hs`

Removed the dedicated `SftSelfReflection` branches in both `selfKnowledgeSurfaceByTarget` and `selfKnowledgeSurfaceByTargetEn` so that `SftSelfReflection` falls through to the catch-all path. This restores the generic self-description surface (containing `"свою роль"` / `"типизированный разбор"`) for `"self"` inputs while preserving the typed `SemanticFrameTarget` refactor.

### 2. `test/Test/Suite/RoundTrip.hs`

Changed the corrupted `ByteString` literal to a properly UTF-8-encoded JSON value:

```haskell
A.decode (A.encode (T.pack "логичность"))
```

This preserves the test intent (decode a legacy arbitrary string as `SftOther`) while correctly handling non-ASCII text. No new dependencies were added.

## Build Output

```
cd /home/liskil/my-haskell-project/QxFx0 && cabal build qxfx0 --ghc-options="-Wall -Werror"
Build profile: -w ghc-9.6.6 -O1
...
Up to date
```

Build completed successfully with no warnings or errors.

## Test Output

```
cd /home/liskil/my-haskell-project/QxFx0 && cabal test qxfx0-test-fast --test-show-details=always
...
Cases: 1366  Tried: 1366  Errors: 0  Failures: 0

Test suite qxfx0-test-fast: PASS
Test suite logged to:
/home/liskil/my-haskell-project/QxFx0/./dist-newstyle/build/x86_64-linux/ghc-9.6.6/qxfx0-0.1.0.0/t/qxfx0-test-fast/test/qxfx0-0.1.0.0-qxfx0-test-fast.log
1 of 1 test suites (1 of 1 test cases) passed.
```

## Lint Output

- `hlint` is not installed in this environment; could not run.
- GHC produced no warnings/errors during the successful `-Wall -Werror` build.

## Verdict

ALL_PASS
