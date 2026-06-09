{-# LANGUAGE OverloadedStrings #-}

{-| Runtime authority surface parser — GF-backed + pattern fallback.

    Lives in a separate module to avoid the circular dependency
    Render/Authority ↔ Runtime/PGF.
-}
module QxFx0.Runtime.AuthorityParse
  ( parseAuthoritySurfaceRuntime
  , parseAuthoritySurfaceIO
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import System.IO.Unsafe (unsafePerformIO)

import QxFx0.Runtime.PGF (parseClaimAstGf)
import QxFx0.Render.Authority
  ( AuthoritySurface(..)
  , claimAstToFactualClaim
  , parseAuthoritySurfacePattern
  )
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..))

-- | Runtime GF-backed authority surface parser (pure wrapper).
-- Stage 1: attempt GF-backed parsing via 'parseClaimAstGf'.
-- Stage 2: fall back to pattern-matching on the four canonical forms.
{-# NOINLINE parseAuthoritySurfaceRuntime #-}
parseAuthoritySurfaceRuntime :: AuthoritySurface -> Maybe FactualClaimPayload
parseAuthoritySurfaceRuntime s@(AuthoritySurface txt)
  | T.null (T.strip txt) = Nothing
  | otherwise =
      let gfResult = unsafePerformIO (parseClaimAstGf Nothing txt)
      in case gfResult of
           Right ast -> Just (claimAstToFactualClaim txt ast)
           Left _    -> parseAuthoritySurfacePattern s

-- | IO variant for contexts where IO is available.
parseAuthoritySurfaceIO :: AuthoritySurface -> IO (Maybe FactualClaimPayload)
parseAuthoritySurfaceIO (AuthoritySurface txt)
  | T.null (T.strip txt) = pure Nothing
  | otherwise = do
      result <- parseClaimAstGf Nothing txt
      case result of
        Right ast -> pure (Just (claimAstToFactualClaim txt ast))
        Left _    -> pure (parseAuthoritySurfacePattern (AuthoritySurface txt))
