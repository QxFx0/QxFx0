# Verification Report: PGF explicit-cache compile fix

## Root Cause

The previous Builder agent completed an explicit PGF-cache refactor in `src/QxFx0/Runtime/PGF.hs` (introducing `newPgfCache` / `cachedReadPGF` and threading the cache through `RuntimeContext` via `rtcPgf`). During that refactor `defaultPgfPath` was dropped from the module export list, but `src/QxFx0/Runtime/Session/Bootstrap.hs` still imports and uses it:

```haskell
import QxFx0.Runtime.PGF (cachedReadPGF, defaultPgfPath)
...
_ <- cachedReadPGF (rtcPgf (rcCaches runtime)) defaultPgfPath
```

This produced the compile error:

```
src/QxFx0/Runtime/Session/Bootstrap.hs:63:42: error:
    Module 'QxFx0.Runtime.PGF' does not export 'defaultPgfPath'
```

## Fix Applied

File changed: `/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Runtime/PGF.hs`

Added `defaultPgfPath` back to the module export list under the "PGF cache" section:

```haskell
module QxFx0.Runtime.PGF
  ( -- * PGF cache
    newPgfCache
  , cachedReadPGF
  , defaultPgfPath
  ...
```

No other source changes were required. The explicit-cache refactor was already complete and wired correctly:

- `QxFx0.Runtime.PGF` provides `newPgfCache`, `cachedReadPGF`, and cache-aware variants of the linearization / parse / preload functions.
- `QxFx0.Runtime.Wiring.Context` creates a single `IORef (Map FilePath PGF.PGF)` cache and stores it in `RuntimeCaches` as `rtcPgf`.
- `QxFx0.Runtime.Session.Bootstrap` eagerly warms that cache during session bootstrap with `cachedReadPGF (rtcPgf (rcCaches runtime)) defaultPgfPath`.
- `QxFx0.Runtime.AuthorityParse` accepts the same cache `IORef` and uses `parseClaimAstGfWithCache`.

Approach chosen: **completed the explicit-cache refactor** (did not fall back to the simpler `initPgfCache` + global `unsafePerformIO` IORef alternative) because the explicit-cache work was already fully wired and only missing the export.

## Build Output

```
cd /home/liskil/my-haskell-project/QxFx0 && cabal build qxfx0 --ghc-options="-Wall -Werror"
Build profile: -w ghc-9.6.6 -O1
Building library for qxfx0-0.1.0.0...
[326 of 416] Compiling QxFx0.Runtime.PGF
[327 of 416] Compiling QxFx0.Runtime.AuthorityParse
[384 of 416] Compiling QxFx0.Runtime.Wiring.Context
[386 of 416] Compiling QxFx0.Runtime.Wiring.Handlers
[398 of 416] Compiling QxFx0.Runtime.Session.Bootstrap
[399 of 416] Compiling QxFx0.Runtime.Session
[414 of 416] Compiling QxFx0.Runtime.Engine
[415 of 416] Compiling QxFx0.Runtime
```

Build completed successfully with the project's `-Wall -Werror` options.

## Test Output

```
cd /home/liskil/my-haskell-project/QxFx0 && cabal test qxfx0-test-fast
Cases: 1326  Tried: 1326  Errors: 0  Failures: 0
Test suite qxfx0-test-fast: PASS
1 of 1 test suites (1 of 1 test cases) passed.
```

## Lint Output

- `hlint` is not installed in this environment; could not run.
- GHC produced no warnings/errors during the successful `-Wall -Werror` build.

## Verdict

ALL_PASS
