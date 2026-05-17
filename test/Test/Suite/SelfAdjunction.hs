{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfAdjunction
Description : Property tests for the Phase-3 @Holistic ⊣ Formal@ adjunction.

Verifies, by QuickCheck, the laws asserted in
@docs\/adr\/0008-left-right-adjunction.md@ §10:

 * the hom-set isomorphism round-trips
   (@leftAdjunct@ ∘ @rightAdjunct@ ≡ id, and the reverse);
 * the left triangle identity on 'Holistic'
   (@counit . fmap unit@ ≡ id);
 * the right triangle identity on 'Formal'
   (@fmap counit . unit@ ≡ id, pointwise on probe fields);
 * value-level coherence of the derived combinators
   ('groundIn' / 'rebroaden');
 * the 'Functor' identity laws on both functors as a sanity check.

Functions cannot be compared structurally in Haskell, so equality on
'Formal' values is established pointwise: two formal commitments are
considered equal here iff they agree on every member of a small,
randomly-generated probe set of 'Field' values. Combined with
parametricity, this is sufficient to verify the implementation is
faithful to the categorical laws on the test family.
-}
module Test.Suite.SelfAdjunction
  ( selfAdjunctionTests
  ) where

import Test.HUnit (Test (..), assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  , vectorOf
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Self.Adjunction
  ( Adjunction (..)
  , Field (..)
  , Formal (..)
  , Holistic (..)
  , groundIn
  , probe
  , rebroaden
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfAdjunctionTests :: [Test]
selfAdjunctionTests =
  [ TestLabel "leftAdjunct ∘ rightAdjunct ≡ id (hom-set round-trip, l→r→l)" $
      quickCheckProperty "leftAdjunct . rightAdjunct ≡ id"  propLeftRightId
  , TestLabel "rightAdjunct ∘ leftAdjunct ≡ id (hom-set round-trip, r→l→r)" $
      quickCheckProperty "rightAdjunct . leftAdjunct ≡ id" propRightLeftId
  , TestLabel "Left triangle identity: counit . fmap unit ≡ id on Holistic" $
      quickCheckProperty "left triangle"  propLeftTriangle
  , TestLabel "Right triangle identity: fmap counit . unit ≡ id on Formal (pointwise)" $
      quickCheckProperty "right triangle" propRightTriangle
  , TestLabel "groundIn ≡ probe ∘ rebroaden (value-level coherence)" $
      quickCheckProperty "groundIn / rebroaden coherence" propGroundRebroaden
  , TestLabel "Functor identity on Holistic: fmap id ≡ id" $
      quickCheckProperty "Functor id on Holistic" propFunctorIdHolistic
  , TestLabel "Functor identity on Formal: fmap id ≡ id (pointwise)" $
      quickCheckProperty "Functor id on Formal" propFunctorIdFormal
  ]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
  if isSuccess result
    then pure ()
    else assertFailure ("Property failed: " ++ label)

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

arbitraryField :: Gen Field
arbitraryField = Field <$> choose (-10.0, 10.0)

arbitraryInt :: Gen Int
arbitraryInt = choose (-100, 100)

arbitraryHolisticInt :: Gen (Holistic Int)
arbitraryHolisticInt =
  (\a fd -> Holistic (a, fd)) <$> arbitraryInt <*> arbitraryField

-- | A small, randomly-chosen set of probe fields used to compare two
-- 'Formal' values for pointwise agreement.
probeFields :: Gen [Field]
probeFields = vectorOf 6 arbitraryField

-- | Build a 'Formal' @Int@ from two integer seeds. The affine
-- shape @\\(Field x) -> k + m * round x@ is sufficient to exercise
-- the categorical laws because they are natural in the type
-- parameter; the only structure being tested is the function
-- shape itself.
--
-- We expose the seeds rather than the constructed function so
-- QuickCheck can 'Show' counter-examples (function types have no
-- meaningful 'Show').
formalFromSeeds :: Int -> Int -> Formal Int
formalFromSeeds k m = Formal (\(Field x) -> k + m * round x)

-- | Pointwise equality of two 'Formal' values on a given probe set.
formalEqOn :: Eq a => [Field] -> Formal a -> Formal a -> Bool
formalEqOn probes f g =
  all (\fd -> probe f fd == probe g fd) probes

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

-- | Hom-set round-trip in the @(Holistic a -> b) → (a -> Formal b)@ direction:
-- @rightAdjunct (leftAdjunct g) ≡ g@ for every @g :: Holistic a -> b@.
--
-- We sample @g@ from a family parameterised by an integer seed so that
-- QuickCheck can drive it.
propLeftRightId :: Property
propLeftRightId =
  forAll arbitraryInt $ \seed ->
  forAll arbitraryHolisticInt $ \h ->
    let g :: Holistic Int -> Int
        g (Holistic (a, Field x)) = a + seed + round x
        g' = rightAdjunct (leftAdjunct g)
    in g h == g' h

-- | Hom-set round-trip in the @(a -> Formal b) → (Holistic a -> b)@ direction:
-- @leftAdjunct (rightAdjunct k) ≡ k@ for every @k :: a -> Formal b@.
--
-- Equality on the @Formal@ output is checked pointwise on a probe set.
propRightLeftId :: Property
propRightLeftId =
  forAll arbitraryInt $ \seed ->
  forAll arbitraryInt $ \a ->
  forAll probeFields $ \probes ->
    let k :: Int -> Formal Int
        k x = Formal (\(Field y) -> x * seed + round y)
        k' :: Int -> Formal Int
        k' = leftAdjunct (rightAdjunct k)
    in formalEqOn probes (k a) (k' a)

-- | Left triangle identity on @Holistic@:
--
-- @
-- counit . fmap unit ≡ id        on Holistic
-- @
--
-- Equality is structural since 'Holistic' has an 'Eq' instance.
propLeftTriangle :: Property
propLeftTriangle =
  forAll arbitraryHolisticInt $ \h ->
    counit (fmap unit h) == h

-- | Right triangle identity on @Formal@:
--
-- @
-- fmap counit . unit ≡ id        on Formal
-- @
--
-- Tested pointwise on the probe set (function equality). The
-- formal value is built from two integer seeds so QuickCheck can
-- present a meaningful counter-example if the property fails.
propRightTriangle :: Property
propRightTriangle =
  forAll arbitraryInt $ \k ->
  forAll arbitraryInt $ \m ->
  forAll probeFields $ \probes ->
    let f       = formalFromSeeds k m
        stepped :: Formal (Holistic (Formal Int))
        stepped = unit f
        lhs :: Formal Int
        lhs     = fmap counit stepped
    in formalEqOn probes lhs f

-- | Value-level coherence between 'groundIn' and 'rebroaden':
--
-- @groundIn (Holistic (a, fd)) ≡ probe (rebroaden a) fd@
--
-- Both sides equal @a@ by definition; the property guards against
-- accidental drift of either combinator from this contract.
propGroundRebroaden :: Property
propGroundRebroaden =
  forAll arbitraryInt $ \a ->
  forAll arbitraryField $ \fd ->
    groundIn (Holistic (a, fd)) == probe (rebroaden a) fd

-- | Sanity: 'Functor' identity law on 'Holistic'.
propFunctorIdHolistic :: Property
propFunctorIdHolistic =
  forAll arbitraryHolisticInt $ \h ->
    fmap id h == h

-- | Sanity: 'Functor' identity law on 'Formal' (pointwise).
propFunctorIdFormal :: Property
propFunctorIdFormal =
  forAll arbitraryInt $ \k ->
  forAll arbitraryInt $ \m ->
  forAll probeFields $ \probes ->
    let f = formalFromSeeds k m
    in formalEqOn probes (fmap id f) f
