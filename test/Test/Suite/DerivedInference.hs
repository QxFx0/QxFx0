{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.DerivedInference
Description : WP-G anti-rot guard for the derived-atom inference consumer.

Per ADR-0042, the consumer must stay connected. 'deriveAtoms' is the living
consumer of the multi-step inference path — it produces additional atoms from
A-and-B patterns that feed the 'ruleTable'. Gated by the default-off
'derivedInferenceActive' flag (ADR-0047).
-}
module Test.Suite.DerivedInference
  ( derivedInferenceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Semantic.Logic
  ( deriveAtoms
  , derivedInferenceActive
  )
import QxFx0.Types (MeaningAtom(..), AtomTag(..))
import qualified Data.Vector as V

derivedInferenceTests :: [Test]
derivedInferenceTests =
  [ -- No-rule inputs produce empty derived set
    TestLabel "WP-G: empty atoms -> no derived atoms" $
      TestCase $
        assertEqual "empty in -> empty out" [] (deriveAtoms [])

    -- A known combination produces at least one derived atom
  , TestLabel "WP-G: NeedContact + Exhaustion -> derived atom" $
      TestCase $ do
        let atoms = [ mk (NeedContact "urgent"), mk (Exhaustion "tired") ]
            derived = deriveAtoms atoms
        assertBool "derived atoms produced" (not (null derived))
        assertBool "derived atom has NeedContact tag"
          (any (\a -> case maTag a of NeedContact _ -> True; _ -> False) derived)

    -- The flag is now on (promoted 2026-06-04)
  , TestLabel "WP-G: derived inference is promoted to default-on" $
      TestCase $
        assertEqual "promoted to default-on (2026-06-04)" True derivedInferenceActive
  ]
  where
    mk t = MeaningAtom { maText = "test", maTag = t, maEmbedding = V.empty }
