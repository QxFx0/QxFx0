{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CognitiveSignals
Description : WP-S anti-rot guard for the compute-once signal seam.

Per ADR-0042, the seam must have a living consumer. WP-S surfaces
'CognitiveSignals' on the turn projection trace (@trcCognitiveSignals@), and
WP-D / WP-E will read it. This suite pins the record's empty-value convention
and structural shape so the seam cannot silently regress to an unused type.
-}
module Test.Suite.CognitiveSignals
  ( cognitiveSignalsTests
  ) where

import Test.HUnit (Test (..), assertEqual, assertBool)

import QxFx0.Types.CognitiveSignals (CognitiveSignals(..), emptyCognitiveSignals)

cognitiveSignalsTests :: [Test]
cognitiveSignalsTests =
  [ -- WP-S: the empty seam value follows the "uninformed = confident, not
    -- unconfident" convention (mirrors emptyField). Pins the contract that
    -- downstream readers (WP-D/E) rely on.
    TestLabel "WP-S: emptyCognitiveSignals has the documented zero shape" $
      TestCase $ do
        assertEqual "no ambiguity at zero" 0.0
          (csCounterfactualEntropy emptyCognitiveSignals)
        assertEqual "max confidence at zero" 1.0
          (csFieldConfidence emptyCognitiveSignals)
        assertEqual "no shadow disagreement at zero" False
          (csShadowDisagreement emptyCognitiveSignals)
        assertEqual "flat posterior at zero" 0.0
          (csMaxPosterior emptyCognitiveSignals)

    -- WP-S: the record carries four independently-addressable signals; a
    -- consumer can read any one without recomputing the others.
  , TestLabel "WP-S: signals are independently addressable" $
      TestCase $ do
        let cs = CognitiveSignals
              { csCounterfactualEntropy = 0.7
              , csFieldConfidence       = 0.3
              , csShadowDisagreement    = True
              , csMaxPosterior          = 0.85
              , csContentSaliency       = 0.0
              }
        assertBool "entropy distinct from confidence"
          (csCounterfactualEntropy cs /= csFieldConfidence cs)
        assertEqual "shadow flag readable" True (csShadowDisagreement cs)
        assertEqual "posterior readable" 0.85 (csMaxPosterior cs)
  ]
