{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.VecProperties
  ( vecPropertiesTests
  ) where
import Test.Support.QuickCheckConfig (qcArgs)

import Test.HUnit (Test(..), assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , forAll
  , quickCheckWithResult
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Types.Vec
  ( CoreVec(..)
  , zeroVec
  , vecAdd
  , vecSub
  , vecScale
  , vecNorm
  , clampVecNorm
  )

vecPropertiesTests :: [Test]
vecPropertiesTests =
  [ TestLabel "vec norm is non-negative" $
      quickCheckProperty "vecNorm non-negative" $
        forAll arbitraryCoreVec $ \v ->
          vecNorm v >= 0
  , TestLabel "clampVecNorm respects cap" $
      quickCheckProperty "clampVecNorm bounded" $
        forAll arbitraryCoreVec $ \v ->
          forAll (choose (0.01, 5.0)) $ \cap ->
            let clamped = clampVecNorm cap v
            in vecNorm clamped <= cap + 1e-8
  , TestLabel "vecAdd is commutative" $
      quickCheckProperty "vecAdd commutative" $
        forAll arbitraryCoreVec $ \a ->
          forAll arbitraryCoreVec $ \b ->
            vecAdd a b == vecAdd b a
  , TestLabel "vecSub cancels vecAdd" $
      quickCheckProperty "vecAdd vecSub identity" $
        forAll arbitraryCoreVec $ \v ->
          vecSub (vecAdd v zeroVec) v == zeroVec
  ]

arbitraryCoreVec :: Gen CoreVec
arbitraryCoreVec =
  CoreVec <$> choose (-2, 2)
          <*> choose (-2, 2)
          <*> choose (-2, 2)
          <*> choose (-2, 2)
          <*> choose (-2, 2)

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop =
  TestCase $ do
    args <- qcArgs
    result <- quickCheckWithResult args prop
    unless (isSuccess result) $
      assertFailure (label <> ": QuickCheck failed")
  where
    unless p action = if p then pure () else action
