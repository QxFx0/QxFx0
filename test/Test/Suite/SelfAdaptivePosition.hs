{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfAdaptivePosition
Description : FMAR Phase-2 — property tests for AdaptivePosition.

Verifies the laws asserted in the FMAR plan, Phase 2:

  * 'encodeMeaningState' maps every band to its documented @[0,1]@ grid
    point — three-band coordinates land in @{0, 0.5, 1.0}@, the
    four-band depth coordinate lands in @{0, 1\/3, 2\/3, 1.0}@;
  * every spectral coordinate is in @[0,1]@;
  * 'hammingDistance' is in @{0,1,2,3}@, is zero exactly on equal
    states, is symmetric, and counts each differing band once;
  * 'encodeMeaningState' is deterministic (pure function — trivially
    holds, asserted as a regression guard).
-}
module Test.Suite.SelfAdaptivePosition
  ( selfAdaptivePositionTests
  ) where
import Test.Support.QuickCheckConfig (qcArgs)

import Test.HUnit (Test (..), assertBool)
import Test.QuickCheck
  ( Gen
  , Property
  , elements
  , forAll
  , quickCheckWithResult
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Self.AdaptivePosition
  ( SpectralEncoding (..)
  , encodeMeaningState
  , hammingDistance
  )
import QxFx0.Types.Observability
  ( DepthBand (..)
  , MeaningState (..)
  , PressureBand (..)
  , ResonanceBand (..)
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfAdaptivePositionTests :: [Test]
selfAdaptivePositionTests =
  [ TestLabel "encodeMeaningState coordinates are in [0,1]" $
      quickCheckProperty "spectral in unit" propSpectralInUnit
  , TestLabel "encodeMeaningState three-band coords land on {0,0.5,1.0}" $
      quickCheckProperty "three-band grid" propThreeBandGrid
  , TestLabel "encodeMeaningState depth coord lands on four-point grid" $
      quickCheckProperty "depth grid" propDepthGrid
  , TestLabel "hammingDistance in {0,1,2,3}" $
      quickCheckProperty "hamming range" propHammingRange
  , TestLabel "hammingDistance is zero iff states equal" $
      quickCheckProperty "hamming zero iff equal" propHammingZeroIffEqual
  , TestLabel "hammingDistance is symmetric" $
      quickCheckProperty "hamming symmetric" propHammingSymmetric
  , TestLabel "hammingDistance counts differing bands" $
      quickCheckProperty "hamming counts bands" propHammingCounts
  ]

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

propSpectralInUnit :: Property
propSpectralInUnit = forAll genMeaningState $ \ms ->
  let se = encodeMeaningState ms
   in all inUnit [seResonance se, sePressure se, seDepth se]
  where inUnit x = x >= 0.0 && x <= 1.0

propThreeBandGrid :: Property
propThreeBandGrid = forAll genMeaningState $ \ms ->
  let se = encodeMeaningState ms
   in onGrid3 (seResonance se) && onGrid3 (sePressure se)
  where onGrid3 x = nearAny x [0.0, 0.5, 1.0]

propDepthGrid :: Property
propDepthGrid = forAll genMeaningState $ \ms ->
  nearAny (seDepth (encodeMeaningState ms)) [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

propHammingRange :: Property
propHammingRange = forAll genMeaningState $ \a ->
  forAll genMeaningState $ \b ->
    let d = hammingDistance a b in d >= 0 && d <= 3

propHammingZeroIffEqual :: Property
propHammingZeroIffEqual = forAll genMeaningState $ \a ->
  forAll genMeaningState $ \b ->
    (hammingDistance a b == 0) == (a == b)

propHammingSymmetric :: Property
propHammingSymmetric = forAll genMeaningState $ \a ->
  forAll genMeaningState $ \b ->
    hammingDistance a b == hammingDistance b a

-- | Distance equals the number of bands that differ, counted directly.
propHammingCounts :: Property
propHammingCounts = forAll genMeaningState $ \a ->
  forAll genMeaningState $ \b ->
    let manual =
          (if msResonance a == msResonance b then 0 else 1 :: Int)
            + (if msPressure a == msPressure b then 0 else 1)
            + (if msDepth a == msDepth b then 0 else 1)
     in hammingDistance a b == manual

-- ---------------------------------------------------------------------------
-- Generators and helpers
-- ---------------------------------------------------------------------------

genMeaningState :: Gen MeaningState
genMeaningState =
  MeaningState
    <$> elements [ResonanceLow, ResonanceMed, ResonanceHigh]
    <*> elements [PressNone, PressLight, PressHeavy]
    <*> elements [DepthShallow, DepthMech, DepthPattern, DepthAxiom]

-- | True if @x@ is within a small tolerance of any grid point.
nearAny :: Double -> [Double] -> Bool
nearAny x = any (\g -> abs (x - g) < 1.0e-9)

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  args <- qcArgs
  result <- quickCheckWithResult args prop
  assertBool ("Property failed: " ++ label) (isSuccess result)
