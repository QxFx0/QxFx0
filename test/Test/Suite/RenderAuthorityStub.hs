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
module Test.Suite.RenderAuthorityStub (tests) where

import           Prelude
import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.HUnit (testCase, (@?=), assertBool)

import qualified QxFx0.Render.Authority as Auth

tests :: TestTree
tests = testGroup "Render.Authority (stub, Package 4)"
  [ testCase "empty surface is stub" $
      Auth.isStubAuthoritySurface Auth.emptyAuthoritySurface
        @?= True

  , testCase "parser returns Nothing for empty input" $
      Auth.parseAuthoritySurface ""
        @?= Nothing

  , testCase "parser returns Nothing for non-empty input" $
      Auth.parseAuthoritySurface "some gf surface"
        @?= Nothing

  , testCase "renderer always produces stub surface" $ do
      let s1 = Auth.renderAuthoritySurface ()
          s2 = Auth.renderAuthoritySurface ("any", "value")
      Auth.isStubAuthoritySurface s1 @?= True
      Auth.isStubAuthoritySurface s2 @?= True
      s1 @?= s2

  , testCase "round-trip property is trivially True" $ do
      assertBool "empty"    (Auth.roundTripProperty Auth.emptyAuthoritySurface)
      assertBool "stub"     (Auth.roundTripProperty (Auth.renderAuthoritySurface ()))

  , testCase "stub surfaces are equal" $ do
      Auth.emptyAuthoritySurface
        @?= Auth.renderAuthoritySurface ()
  ]
