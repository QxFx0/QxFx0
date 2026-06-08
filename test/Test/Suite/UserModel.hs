{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.UserModel
Description : WP-A anti-rot guard for the Bayesian user-model consumer.

Per ADR-0042, every wired cognitive consumer carries a test that fails if the
consumer is disconnected. 'updateUserModel' is the living consumer of
'bayesianUpdateFromText' on the turn path (ssUserModel), and 'dominantIntent'
is the reader that feeds dtIntentHypothesis. Gated by the default-off
'userModelActive' flag (ADR-0044).
-}
module Test.Suite.UserModel
  ( userModelTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import qualified Data.Map.Strict as M

import QxFx0.Core.Bayesian
  ( bayesianUpdateFromText
  , updateUserModel
  , userModelActive
  , dominantIntent
  )
import QxFx0.Types.Bayesian (HiddenBelief(..), initialBeliefs)
import QxFx0.Types.SemanticConfig (defaultSemanticConfig)

userModelTests :: [Test]
userModelTests =
  [ -- WP-A anti-rot (consumer): updateUserModel must delegate to
    -- bayesianUpdateFromText when the flag is on, and be identity when off.
    -- Deleting the bayesianUpdateFromText call breaks this test.
    TestLabel "WP-A: updateUserModel is a living consumer of bayesianUpdateFromText" $
      TestCase $ do
        let raw = "что такое свобода"
            viaConsumer = updateUserModel defaultSemanticConfig initialBeliefs raw
            viaDirect   = bayesianUpdateFromText defaultSemanticConfig initialBeliefs raw
        if userModelActive
          then assertEqual "consumer must match direct update when flag on"
                 viaDirect viaConsumer
          else assertEqual "consumer must be identity (prior) when flag off"
                 initialBeliefs viaConsumer

    -- dominantIntent reader: uniform prior yields no dominant intent
    -- (so baseline dtIntentHypothesis is preserved when flag off).
  , TestLabel "WP-A: dominantIntent is Nothing on the uniform prior" $
      TestCase $
        assertEqual "uniform prior has no peaked intent"
          Nothing (dominantIntent initialBeliefs)

    -- dominantIntent reader: a peaked posterior surfaces the argmax intent.
  , TestLabel "WP-A: dominantIntent surfaces the peaked posterior intent" $
      TestCase $ do
        let peaked = M.insert UserWantsDefine 0.9
                   $ M.map (const 0.02) initialBeliefs
        assertEqual "peaked posterior surfaces its argmax"
          (Just UserWantsDefine) (dominantIntent peaked)
  ]
