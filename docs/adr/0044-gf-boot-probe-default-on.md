# ADR-0044: GF Boot-Probe and Default-On Policy

- **Status**: Accepted (2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `docs/specs/cognitive-wiring-TZ.md` (WP-H2)
  - ADR-0033 (parser variant B)
  - `audit-comprehensive-2026-06-03.md` (#6 GF off by default)

## 1. Context

The 2026-06 cognitive audit found that GF (Grammatical Framework) runtime was
**off by default** despite being the primary generative path. The fallback
(template-based rendering) was logged as normal operation, not degraded mode.
This inverted the design intent: GF should be the default, templates the
fallback.

Root cause: No **boot-time validation** of PGF (Portable Grammar Format) file.
The system couldn't distinguish "GF disabled by policy" from "GF unavailable due
to missing/corrupt PGF". Result: silent degradation to templates.

WP-H2 requirements:
- **R-H2.1**: Boot-probe PGF health, integrate into `SystemHealth`
- **R-H2.2**: Check PGF status in render path, enable GF default-on when valid
- **R-H2.3**: Telemetry/logging (deferred to Phase II)

## 2. Decision

### 2.1 PGF Health Probe (R-H2.1)

**Added**: `QxFx0.Runtime.Health` integration

```haskell
data PgfHealth = PgfHealth
  { phOk     :: !Bool
  , phStatus :: !Text  -- "ok" | "file_not_found" | "io_error" | "no_languages"
  , phIssue  :: !(Maybe Text)
  } deriving (Show, Eq, Generic, ToJSON, FromJSON)

probePgfHealth :: IO PgfHealth
probePgfHealth = do
  let pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  if not exists
    then pure $ PgfHealth False "file_not_found" (Just $ "missing:" <> T.pack pgfPath)
    else do
      result <- try @IOException $ PGF.readPGF pgfPath
      case result of
        Left e -> pure $ PgfHealth False "io_error" (Just $ T.pack $ show e)
        Right pgf ->
          let langCount = length (PGF.languages pgf)
          in if langCount > 0
               then pure $ PgfHealth True "ok" Nothing
               else pure $ PgfHealth False "no_languages" (Just "pgf_no_languages")
```

**Integrated** into `SystemHealth`:

```haskell
data SystemHealth = SystemHealth
  { shPgfOk     :: !Bool
  , shPgfStatus :: !Text
  , shPgfIssue  :: !(Maybe Text)
  , ...
  }
```

Health endpoint (`/health`) now exposes PGF status.

### 2.2 Runtime Status Module (R-H2.2)

**Problem**: Circular dependency. `Runtime.Health` → `Runtime.Wiring` →
`Render.Dialogue` → needs PGF status.

**Solution**: Created `QxFx0.Runtime.PGFStatus` — minimal-dependency module
importable by `Render.Dialogue`:

```haskell
module QxFx0.Runtime.PGFStatus
  ( pgfRuntimeActive
  , pgfFallbackReason
  ) where

pgfLoadResult :: (Maybe PGF.PGF, Maybe Text)
pgfLoadResult = unsafePerformIO loadPgfOnce
{-# NOINLINE pgfLoadResult #-}

loadPgfOnce :: IO (Maybe PGF.PGF, Maybe Text)
loadPgfOnce = do
  let pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Nothing, Just ("pgf_file_not_found:" <> T.pack pgfPath))
    else do
      result <- try @IOException $ PGF.readPGF pgfPath
      case result of
        Left e -> pure (Nothing, Just ("pgf_io_error:" <> T.pack (show e)))
        Right pgf ->
          let langCount = length (PGF.languages pgf)
          in if langCount > 0
               then pure (Just pgf, Nothing)
               else pure (Nothing, Just "pgf_no_languages")

pgfRuntimeActive :: Bool
pgfRuntimeActive = case fst pgfLoadResult of
  Just _  -> True
  Nothing -> False

pgfFallbackReason :: Maybe Text
pgfFallbackReason = snd pgfLoadResult
```

**Pattern**: Same `unsafePerformIO` + `NOINLINE` pattern as `gfMapLoadStatus`
(existing singleton). Lazy initialization, evaluated once per process.

### 2.3 Render Path Integration

**Modified**: `linearizeOrFallbackTagged` and `linearizeOrFallbackTaggedEn` now
check **both** `gfMapFallbackReason` (GF map load status) **and**
`pgfFallbackReason` (PGF load status):

```haskell
linearizeOrFallbackTagged :: Text -> ClaimAst -> RenderStyle -> MorphologyData -> Text -> ClaimLinearization
linearizeOrFallbackTagged reasonTag ast renderStyle morph fallbackText =
  case (gfMapFallbackReason gfMapLoadStatus, pgfFallbackReason) of
    (Just reason, _) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (_, Just reason) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (Nothing, Nothing) ->
      case linearizeClaimAstRus ast renderStyle morph of
        Just txt ->
          ClaimLinearization
            { clText = txt
            , clOk = True
            , clFallbackReason = Nothing
            }
        Nothing ->
          ClaimLinearization
            { clText = fallbackText
            , clOk = False
            , clFallbackReason = Just ("gf_linearization_failed:" <> reasonTag)
            }
```

**Effect**: GF now **default-on** when both GF map and PGF are valid. Fallback
logged with explicit reason (`clFallbackReason`), not as normal operation.

### 2.4 Deferred (R-H2.3)

**Telemetry/logging**: Structured logging of fallback events (count, reason
distribution) deferred to Phase II (requires observability infrastructure from
calibration pipeline).

## 3. Consequences

### 3.1 Positive

- GF now default-on when PGF valid (design intent restored)
- Boot-time health check catches missing/corrupt PGF before first request
- Fallback explicitly logged as degraded mode (`clFallbackReason`)
- Circular dependency resolved via minimal `PGFStatus` module
- Zero behavioral change when PGF invalid (still falls back to templates)

### 3.2 Negative

- Two singleton load mechanisms (`gfMapLoadStatus`, `pgfLoadResult`) — potential
  for consolidation
- `unsafePerformIO` pattern (acceptable for read-only global resources, but
  requires discipline)

### 3.3 Neutral

- Health endpoint now exposes PGF status (useful for ops, no security concern)
- Telemetry deferred to Phase II (not blocking)

## 4. Compliance

- ✅ Build passes (`cabal build --ghc-options="-Werror"`)
- ✅ Determinism preserved (PGF load is deterministic given file)
- ✅ Fail-closed: Invalid PGF → fallback (safe degradation)
- ✅ Governance: No state migration (pure runtime change)

## 5. Testing

- Boot-probe tested via health endpoint (`/health` returns `shPgfOk`)
- Render path tested via existing `Test.Suite.RenderDialogueCoverage`
- Missing PGF scenario: manually tested by renaming PGF file (fallback triggered
  with `clFallbackReason = "pgf_file_not_found:..."`)

## 6. Future Work

- Consolidate `gfMapLoadStatus` and `pgfLoadResult` into unified resource loader
- Phase II: Structured telemetry for fallback events (count, reason histogram)
- Consider boot-time validation of GF map consistency (map references PGF
  languages)