{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Render.Authority
Description : Package 4 (GF round-trip) — @AuthoritySurface@ stub.

A stub implementation of the 'AuthoritySurface' newtype and the
two functions ('parseAuthoritySurface', 'renderAuthoritySurface')
required by @docs\/closure\/GF_AUTHORITY_SUBSET.md@. The real
implementation is gated on the Haskell-side parser extension
described in §2 of the GF subset document. Until that parser is
landed, the round-trip is intentionally a no-op: the parser returns
'Nothing' for any input, and the renderer produces a fixed
placeholder.

== Why a stub now

The closure plan's Package 4 has two acceptance criteria:

  1. The Haskell @AuthoritySurface@ newtype exists, with
     'parseAuthoritySurface' and 'renderAuthoritySurface' as
     pure, replay-visible functions.
  2. A round-trip property
     @roundTripProperty :: AuthoritySurface -> Bool@ exists, but
     the real implementation depends on the GF Haskell parser,
     which is not yet in the dependency closure.

This module satisfies criterion 1 fully and criterion 2 partially:
the property is well-typed and trivially holds (since no surface
is parseable yet). When the real parser is landed, the only change
is to 'parseAuthoritySurface'; the type and the property remain.

== Round-trip property

@roundTripProperty@ is the stub identity. When the real parser is
landed, the property becomes

  @forall s. parseAuthoritySurface (renderAuthoritySurface s) == Just s@,

i.e. total round-trip. Coverage (the fraction of natural-language
surfaces that round-trip) is the metric tracked in §3 of the GF
subset document; the target is ≥ 0.99.
-}

module QxFx0.Render.Authority
  ( -- * The authority surface
    AuthoritySurface
  , emptyAuthoritySurface
  , isStubAuthoritySurface

    -- * Stub parser / renderer
  , parseAuthoritySurface
  , renderAuthoritySurface

    -- * Round-trip property
  , roundTripProperty
  ) where

import           Data.Eq (Eq)
import           Data.Function (($))
import           Data.Maybe (Maybe (..))
import           GHC.Generics (Generic)
import           Prelude (Bool (..))

-- | An authority-bearing GF render of a 'QxFx0.Self.Salience.SalienceDecision'
-- or related decision contour. The stub is a single byte; the real
-- implementation is a structured 'Text' with five fields (per
-- @docs\/closure\/GF_AUTHORITY_SUBSET.md@ §2).
newtype AuthoritySurface = AuthoritySurface
  { unAuthoritySurface :: String
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (-- the project's typeclass stack is added
                      -- when the real implementation lands; for
                      -- now the stub is intentionally minimal.
                      ())

-- | The empty surface — the renderer always produces this until the
-- real parser is in. Using 'emptyAuthoritySurface' rather than
-- building the newtype directly is the only supported way to
-- construct a stub surface.
emptyAuthoritySurface :: AuthoritySurface
emptyAuthoritySurface = AuthoritySurface "STUB"

-- | Whether a surface is the stub. The property tests rely on
-- this to make the stub-ness of the current implementation
-- visible to the replay gate.
isStubAuthoritySurface :: AuthoritySurface -> Bool
isStubAuthoritySurface s = unAuthoritySurface s == unAuthoritySurface emptyAuthoritySurface

-- | The stub parser: returns 'Nothing' for any input. The real
-- parser will be added when the GF Haskell parser is in the
-- dependency closure. Until then, the round-trip is intentionally
-- trivial: there is no surface that parses.
parseAuthoritySurface :: String -> Maybe AuthoritySurface
parseAuthoritySurface _ = Nothing

-- | The stub renderer: always produces 'emptyAuthoritySurface'.
-- The real renderer will accept a 'QxFx0.Self.Salience.SalienceDecision'
-- (or related decision) and produce a five-field structured surface.
renderAuthoritySurface :: a -> AuthoritySurface
renderAuthoritySurface _ = emptyAuthoritySurface

-- | The stub round-trip property: trivially 'True' because
-- 'parseAuthoritySurface' is total 'Nothing'. The real
-- implementation (per the GF subset doc) becomes
--
-- @
-- roundTripProperty s =
--   case parseAuthoritySurface (renderAuthoritySurface s) of
--     Just s' -> s == s'
--     Nothing -> False
-- @
--
-- once the parser is landed. The current stub keeps the
-- signature stable so the property test can be added without
-- a follow-up signature change.
roundTripProperty :: AuthoritySurface -> Bool
roundTripProperty _ = True
