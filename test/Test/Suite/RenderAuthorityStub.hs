-- | Test suite for the Package 4 'AuthoritySurface' stub.
--
-- The stub's contract (per @docs\/closure\/GF_AUTHORITY_SUBSET.md@)
-- is small but specific:
--
--   * the parser returns 'Nothing' for any input;
--   * the renderer always produces 'emptyAuthoritySurface';
--   * the round-trip property is trivially 'True';
--   * 'isStubAuthoritySurface' is 'True' for the rendered
--     surface and for 'emptyAuthoritySurface'.
--
-- When the real parser is landed, the only test that must
-- change is @roundTrip is total for the structured surface@;
-- the stub tests stay as a regression lock.
module Test.Suite.RenderAuthorityStub
  ( renderAuthorityStubTests
  ) where

import Prelude
import Test.HUnit (Test(..), assertBool, (@?=))

import qualified QxFx0.Render.Authority as Auth

renderAuthorityStubTests :: [Test]
renderAuthorityStubTests =
  [ TestLabel "RenderAuthorityStub.empty surface is stub" $
      TestCase $
        Auth.isStubAuthoritySurface Auth.emptyAuthoritySurface
          @?= True
  , TestLabel "RenderAuthorityStub.parser returns Nothing for empty input" $
      TestCase $
        Auth.parseAuthoritySurface ""
          @?= Nothing
  , TestLabel "RenderAuthorityStub.parser returns Nothing for non-empty input" $
      TestCase $
        Auth.parseAuthoritySurface "some gf surface"
          @?= Nothing
  , TestLabel "RenderAuthorityStub.renderer always produces stub surface" $
      TestCase $ do
        let s1 = Auth.renderAuthoritySurface ()
            s2 = Auth.renderAuthoritySurface ("any", "value")
        Auth.isStubAuthoritySurface s1 @?= True
        Auth.isStubAuthoritySurface s2 @?= True
        s1 @?= s2
  , TestLabel "RenderAuthorityStub.round-trip property is trivially True" $
      TestCase $ do
        assertBool "empty" (Auth.roundTripProperty Auth.emptyAuthoritySurface)
        assertBool "stub" (Auth.roundTripProperty (Auth.renderAuthoritySurface ()))
  , TestLabel "RenderAuthorityStub.stub surfaces are equal" $
      TestCase $
        Auth.emptyAuthoritySurface
          @?= Auth.renderAuthoritySurface ()
  ]
