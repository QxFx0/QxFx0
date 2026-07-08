{-# LANGUAGE OverloadedStrings #-}

{-| Runtime authority surface parser — pure pattern-matching fallback.

    Lives in a separate module to avoid the circular dependency
    Render/Authority ↔ Runtime/PGF.
-}
module QxFx0.Runtime.AuthorityParse
  ( parseAuthoritySurfaceRuntime
  , parseAuthoritySurfaceIO
  , roundTripProperty
  ) where

import qualified Data.Text as T

import QxFx0.Runtime.PGF (parseClaimAstGf)
import QxFx0.Render.Authority
  ( AuthoritySurface(..)
  , claimAstToFactualClaim
  , parseAuthoritySurfacePattern
  , renderAuthoritySurface
  )
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..))

-- | Pure pattern-only authority surface parser.
--
-- This function performs only the pattern-matching fallback on the four
-- canonical forms ('parseAuthoritySurfacePattern'). It does not require IO
-- and does not invoke the GF-backed parser. For GF-backed parsing, use
-- 'parseAuthoritySurfaceIO' instead.
parseAuthoritySurfaceRuntime :: AuthoritySurface -> Maybe FactualClaimPayload
parseAuthoritySurfaceRuntime s@(AuthoritySurface txt)
  | T.null (T.strip txt) = Nothing
  | otherwise            = parseAuthoritySurfacePattern s

-- | IO variant for contexts where IO is available.
-- Stage 1: attempt GF-backed parsing via 'parseClaimAstGf'.
-- Stage 2: fall back to pattern-matching on the four canonical forms.
parseAuthoritySurfaceIO :: AuthoritySurface -> IO (Maybe FactualClaimPayload)
parseAuthoritySurfaceIO (AuthoritySurface txt)
  | T.null (T.strip txt) = pure Nothing
  | otherwise = do
      result <- parseClaimAstGf Nothing txt
      case result of
        Right ast -> pure (Just (claimAstToFactualClaim txt ast))
        Left _    -> pure (parseAuthoritySurfacePattern (AuthoritySurface txt))

-- | Round-trip property: parse ∘ render == id on the canonical subset.
--
-- This now tests the pattern-only parser 'parseAuthoritySurfaceRuntime'.
-- GF-backed round-tripping is exercised via 'parseAuthoritySurfaceIO' in
-- contexts where IO is available.
roundTripProperty :: FactualClaimPayload -> Bool
roundTripProperty p =
  case parseAuthoritySurfaceRuntime (renderAuthoritySurface p) of
    Just p' -> fcpStatement p == fcpStatement p' && fcpOrigin p == fcpOrigin p'
    Nothing -> False
