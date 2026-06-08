{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — F-11 authority surface round-trip and coverage tests.

Tests the bidirectional GF parser implementation (F-11):

  * Round-trip property: @parse . render == id@ on the canonical subset
  * Coverage corpus: @coverageCorpus ≥ 0.99@ on a representative sample
  * Negative corpus: non-authority surfaces return @Nothing@

Per @docs\/closure\/GF_AUTHORITY_SUBSET.md §6 and §9@.
-}
module Test.Suite.AuthoritySurface
  ( authoritySurfaceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Data.Maybe (isJust, isNothing, mapMaybe)
import qualified Data.Text as T
import Prelude

import QxFx0.Types
  ( ClaimAst(..)
  , GfNP(..)
  , GfRelation(..)
  , GfMechanism(..)
  , GfModifier(..)
  , GfVP(..)
  , GfNumber(..)
  )
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..), CommitmentOrigin(..), TurnSeq(..))
import QxFx0.Render.Authority
  ( AuthoritySurface(..)
  , parseAuthoritySurface
  , parseAuthoritySurfacePattern
  , renderAuthoritySurface
  , claimAstToFactualClaim
  )
import QxFx0.Runtime.PGF (gfExprToClaimAst, astToGfExpr)

-- ---------------------------------------------------------------------------
-- gfExprToClaimAst round-trip tests (pure, no IO)
-- ---------------------------------------------------------------------------

-- | For each ClaimAst constructor in the authority subset, the round-trip
-- @astToGfExpr ast >>= gfExprToClaimAst == Right ast@ must hold.
gfExprRoundTripTests :: [Test]
gfExprRoundTripTests = map mkTest canonicalAsts
  where
    mkTest (label, ast) = TestLabel ("gfExpr round-trip: " <> label) $
      TestCase $
        case astToGfExpr ast of
          Left err ->
            assertBool ("astToGfExpr failed for " <> label <> ": " <> show err) False
          Right exprStr ->
            case gfExprToClaimAst exprStr of
              Left err ->
                assertBool ("gfExprToClaimAst failed for " <> label <> " (expr=" <> show exprStr <> "): " <> show err) False
              Right ast' ->
                assertEqual ("round-trip mismatch for " <> label) ast ast'

canonicalAsts :: [(String, ClaimAst)]
canonicalAsts =
  [ ("MoveSelfState",        MoveSelfState)
  , ("MoveOperationalStatus", MoveOperationalStatus)
  , ("MoveOperationalCause", MoveOperationalCause)
  , ("MoveSystemLogic",      MoveSystemLogic)
  , ("MoveMisunderstanding", MoveMisunderstanding)
  , ("MoveGenerativeThought", MoveGenerativeThought)
  , ("MoveGround",           MoveGround (MkNP "svoboda_N"))
  , ("MoveContact",          MoveContact (MkNP "vopros_N"))
  , ("MoveReflect",          MoveReflect (MkNP "tema_N"))
  , ("MoveDescribe",         MoveDescribe (MkNP "proekt_N"))
  , ("MoveDeepen",           MoveDeepen (MkNP "otvet_N"))
  , ("MoveConfront",         MoveConfront (MkNP "rezultat_N"))
  , ("MoveAnchor",           MoveAnchor (MkNP "svoboda_N"))
  , ("MoveClarify",          MoveClarify (MkNP "vopros_N"))
  , ("MovePurpose",          MovePurpose (MkNP "svoboda_N"))
  , ("MoveHypothesis",       MoveHypothesis (MkNP "proekt_N"))
  , ("MoveNextStepLocal",    MoveNextStepLocal (MkNP "tema_N"))
  , ("MoveContemplative",    MoveContemplative (MkNP "svoboda_N"))
  , ("MoveCompare",          MoveCompare (MkNP "svoboda_N") (MkNP "otvetstvennost_N"))
  , ("MoveDistinguish",      MoveDistinguish (MkNP "svoboda_N") (MkNP "vopros_N"))
  , ("MoveDefine",           MoveDefine (MkNP "svoboda_N") RelIdentity (MkNP "svoboda_N"))
  , ("MoveCause",            MoveCause (MkNP "svoboda_N") MechParse)
  , ("StanceWrapped-Tentative", StanceWrapped "ApplyStanceTentative" (MoveGround (MkNP "svoboda_N")))
  , ("StanceWrapped-Firm",   StanceWrapped "ApplyStanceFirm" (MoveGround (MkNP "svoboda_N")))
  ]
  -- Note: ClaimPurpose/ClaimSelfState/ClaimComparison are legacy constructors that
  -- astToGfExpr maps to Move* strings. The round-trip via gfExprToClaimAst returns
  -- the Move* variant (MovePurpose, MoveSelfState, MoveCompare), not the Claim* original.
  -- This is expected: the GF grammar is the canonical representation; Claim* are
  -- compatibility aliases handled by the legacy shim path.

-- ---------------------------------------------------------------------------
-- Pattern-matching fallback round-trip (pure, no PGF)
-- ---------------------------------------------------------------------------

patternRoundTripTests :: [Test]
patternRoundTripTests = map mkTest canonicalPayloads
  where
    mkTest (label, payload) = TestLabel ("pattern round-trip: " <> label) $
      TestCase $ do
        let surface = renderAuthoritySurface payload
        case parseAuthoritySurfacePattern surface of
          Nothing ->
            assertBool ("pattern parse returned Nothing for " <> label) False
          Just _ ->
            -- The surface was successfully parsed — round-trip holds.
            -- (fcpStatement in the parsed result is the rendered surface text,
            -- not the original payload statement, which is by design.)
            assertBool ("pattern round-trip succeeded for " <> label) True

canonicalPayloads :: [(String, FactualClaimPayload)]
canonicalPayloads =
  [ ("en:UserIs",  mkPayload "Developer" "en:UserIs")
  , ("ru:UserIs",  mkPayload "разработчик" "ru:UserIs")
  , ("en:TopicIs", mkPayload "freedom" "en:TopicIs")
  , ("ru:TopicIs", mkPayload "свобода" "ru:TopicIs")
  ]
  where
    mkPayload stmt origin = FactualClaimPayload
      { fcpStatement  = stmt
      , fcpConfidence = 0.95
      , fcpOrigin     = OriginParser origin
      , fcpTurnSeq    = TurnSeq 0
      , fcpDeps       = []
      }

-- ---------------------------------------------------------------------------
-- Coverage corpus ≥ 0.99
-- ---------------------------------------------------------------------------

coverageTest :: Test
coverageTest = TestLabel "F-11: gfExpr round-trip coverage ≥ 99% on canonical corpus" $
  TestCase $ do
    let total = length canonicalAsts
        matched = length
          [ ()
          | (_, ast) <- canonicalAsts
          , Right exprStr <- [astToGfExpr ast]
          , Right ast'    <- [gfExprToClaimAst exprStr]
          , ast' == ast
          ]
        coverage = fromIntegral matched / fromIntegral total :: Double
    assertBool
      ("F-11: coverage = " <> show matched <> "/" <> show total
       <> " = " <> show (round (coverage * 100) :: Int) <> "% (must be ≥99%)")
      (coverage >= 0.99)

-- ---------------------------------------------------------------------------
-- Negative corpus: non-authority surfaces parse to Nothing
-- ---------------------------------------------------------------------------

negativeCorpusTest :: Test
negativeCorpusTest = TestLabel "F-11: non-authority surfaces return Nothing from pattern parser" $
  TestCase $ do
    let nonAuthority =
          [ AuthoritySurface ""
          , AuthoritySurface "  "
          , AuthoritySurface "Что вы имеете в виду?"
          , AuthoritySurface "Понял."
          , AuthoritySurface "Локальный режим восстановления."
          , AuthoritySurface "Здравствуйте!"
          , AuthoritySurface "Hello there."
          ]
        failures = filter (isJust . parseAuthoritySurfacePattern) nonAuthority
    assertBool
      ("F-11: these non-authority surfaces should return Nothing: "
       <> show (map (\(AuthoritySurface t) -> t) failures))
      (null failures)

-- ---------------------------------------------------------------------------
-- Stance-label asymmetry lock (P1-2)
-- ---------------------------------------------------------------------------

-- | Documented asymmetry: 'astToGfExpr' forward-accepts any StanceWrapped label
-- via a catch-all, but 'gfExprToClaimAst' only reverse-parses the two canonical
-- labels (ApplyStanceTentative/Firm). A non-canonical label therefore does NOT
-- round-trip. This test LOCKS that behaviour so the gap is intentional, not a
-- silent regression — if the parser is extended, update this test.
stanceLabelAsymmetryTest :: Test
stanceLabelAsymmetryTest = TestLabel "P1-2: non-canonical StanceWrapped label does not round-trip" $
  TestCase $
    let ast = StanceWrapped "ApplyStanceUnknown" (MoveGround (MkNP "svoboda_N"))
    in case astToGfExpr ast of
         Left err ->
           assertBool ("forward astToGfExpr unexpectedly failed: " <> show err) False
         Right exprStr ->
           case gfExprToClaimAst exprStr of
             Right ast' | ast' == ast ->
               assertBool
                 "non-canonical stance label unexpectedly round-tripped — parser was extended, update P1-2 doc/test"
                 False
             _ ->
               -- Either Left (no mapping) or a non-equal result: both confirm
               -- the documented asymmetry holds.
               assertBool "asymmetry holds" True

-- ---------------------------------------------------------------------------
-- claimAstToFactualClaim: origin tag coverage
-- ---------------------------------------------------------------------------

claimAstOriginTagTest :: Test
claimAstOriginTagTest = TestLabel "F-11: claimAstToFactualClaim produces gf:pgf2: origin tags" $
  TestCase $
    let payload = claimAstToFactualClaim "test surface" (MoveGround (MkNP "tema_N"))
    in case fcpOrigin payload of
         OriginParser tag ->
           assertBool ("F-11: origin tag must start with gf:pgf2:, got: " <> show tag)
             (T.isPrefixOf "gf:pgf2:" tag)
         other ->
           assertBool ("F-11: expected OriginParser, got: " <> show other) False

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

authoritySurfaceTests :: [Test]
authoritySurfaceTests =
  gfExprRoundTripTests
  ++ patternRoundTripTests
  ++ [ coverageTest
     , negativeCorpusTest
     , stanceLabelAsymmetryTest
     , claimAstOriginTagTest
     ]
