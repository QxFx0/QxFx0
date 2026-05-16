{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.SelfBlanket
Description : Unit tests for the Phase-1 Self-layer (SelfBlanket invariants).

Tests are pure: they exercise 'computeSelfBlanket',
'checkInitialBlanket', and 'checkBlanketTransition' over manually
constructed 'SelfBlanket' values and a minimally-populated
'SystemState'. No IO, no fixtures.

See @docs\/THEORY.md@ §4.1.
-}
module Test.Suite.SelfBlanket
  ( selfBlanketTests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Test.HUnit (Test (..), (@?=), assertBool)

import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants
  ( checkBlanketTransition
  , checkInitialBlanket
  , renderBlanketViolations
  )
import QxFx0.Self.Types
  ( BlanketViolation (..)
  , SelfBlanket (..)
  )
import QxFx0.Types
  ( MorphologyData (..)
  , SystemState (..)
  )
import QxFx0.Types.State (emptySystemState)

-- | A minimally valid baseline blanket for transition tests.
validBlanket :: SelfBlanket
validBlanket = SelfBlanket
  { sbSessionId           = "demo"
  , sbMorphologyTotalSize = 100
  , sbIdentityClaimsCount = 0
  , sbTurnCount           = 0
  }

-- | Populate the empty system state with the minimum needed for a
-- valid self-blanket: a session id and a non-empty morphology.
viableSystemState :: SystemState
viableSystemState =
  let base = emptySystemState
      morph = MorphologyData
        (Map.singleton "о" "preposition")  -- one prepositional form
        Map.empty
        Map.empty
        Map.empty
   in base
        { ssSessionId  = "demo"
        , ssMorphology = morph
        }

selfBlanketTests :: [Test]
selfBlanketTests =
  [ TestLabel "computeSelfBlanket projects expected fields from SystemState" $
      TestCase $ do
        let sb = computeSelfBlanket viableSystemState
        sbSessionId sb           @?= "demo"
        sbMorphologyTotalSize sb @?= 1
        sbIdentityClaimsCount sb @?= 0
        sbTurnCount sb           @?= 0

  , TestLabel "checkInitialBlanket accepts a valid blanket" $
      TestCase $
        checkInitialBlanket validBlanket @?= []

  , TestLabel "checkInitialBlanket rejects an empty session id" $
      TestCase $ do
        let sb = validBlanket { sbSessionId = "" }
        checkInitialBlanket sb @?= [BlanketEmptySession]

  , TestLabel "checkInitialBlanket rejects empty morphology" $
      TestCase $ do
        let sb = validBlanket { sbMorphologyTotalSize = 0 }
        checkInitialBlanket sb @?= [BlanketEmptyMorphology]

  , TestLabel "checkInitialBlanket reports both violations when both fail" $
      TestCase $ do
        let sb = validBlanket
              { sbSessionId           = ""
              , sbMorphologyTotalSize = 0
              }
        checkInitialBlanket sb
          @?= [BlanketEmptySession, BlanketEmptyMorphology]

  , TestLabel "checkBlanketTransition accepts a benign turn increment" $
      TestCase $ do
        let prev = validBlanket
            cur  = validBlanket { sbTurnCount = 1 }
        checkBlanketTransition prev cur @?= []

  , TestLabel "checkBlanketTransition accepts identity-claim growth" $
      TestCase $ do
        let prev = validBlanket
            cur  = validBlanket { sbIdentityClaimsCount = 3, sbTurnCount = 1 }
        checkBlanketTransition prev cur @?= []

  , TestLabel "checkBlanketTransition rejects a session-id change" $
      TestCase $ do
        let prev = validBlanket
            cur  = validBlanket { sbSessionId = "other" }
        checkBlanketTransition prev cur
          @?= [BlanketSessionChanged "demo" "other"]

  , TestLabel "checkBlanketTransition rejects a turn-count regression" $
      TestCase $ do
        let prev = validBlanket { sbTurnCount = 5 }
            cur  = validBlanket { sbTurnCount = 3 }
        checkBlanketTransition prev cur
          @?= [BlanketTurnRegressed 5 3]

  , TestLabel "checkBlanketTransition rejects identity-claim erasure" $
      TestCase $ do
        let prev = validBlanket { sbIdentityClaimsCount = 4 }
            cur  = validBlanket { sbIdentityClaimsCount = 2 }
        checkBlanketTransition prev cur
          @?= [BlanketIdentityErased 4 2]

  , TestLabel "checkBlanketTransition reports compound violations together" $
      TestCase $ do
        let prev = validBlanket
              { sbTurnCount           = 5
              , sbIdentityClaimsCount = 4
              }
            cur  = SelfBlanket
              { sbSessionId           = "other"
              , sbMorphologyTotalSize = 0
              , sbIdentityClaimsCount = 2
              , sbTurnCount           = 3
              }
        let violations = checkBlanketTransition prev cur
        -- Order: initial-blanket checks first, then transition checks.
        violations @?=
          [ BlanketEmptyMorphology
          , BlanketSessionChanged "demo" "other"
          , BlanketTurnRegressed 5 3
          , BlanketIdentityErased 4 2
          ]

  , TestLabel "renderBlanketViolations produces a non-empty diagnostic" $
      TestCase $ do
        let rendered =
              renderBlanketViolations
                [ BlanketEmptySession
                , BlanketTurnRegressed 2 1
                ]
        assertBool "rendering is non-empty"     (not (T.null rendered))
        assertBool "rendering mentions session" ("session" `T.isInfixOf` rendered)
        assertBool "rendering mentions turn"    ("turn"    `T.isInfixOf` rendered)
  ]
