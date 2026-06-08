{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.AdaptivePosition
Description : FMAR Phase-2 — 8D adaptive state position over Field + spectral bands.

The position of the system in the space FMAR (Field-Modulated Adaptive
Routing) reasons over: the five-component 'Field', a three-component
spectral encoding of the current 'MeaningState', and the scalar Conatus
energy used by the downstream Conatus gate.

The spectral encoding maps each band to @[0,1]@ by its enumeration
position. It is deliberately a /minor/ contributor: three bands give
@4 * 3 * 3 = 36@ discrete states (~5.2 bits) against the five continuous
'Field' components that carry the dominant signal. Spectral position adds
contextual nudge, not the primary axis.

This module is pure: it sources no runtime values, touches no pipeline,
and only depends on the 'Field' record shape and the band types.
-}
module QxFx0.Self.AdaptivePosition
  ( SpectralEncoding (..)
  , AdaptivePosition (..)
  , emptyAdaptivePosition
  , encodeMeaningState
  , hammingDistance
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Self.Field (Field, emptyField)
import QxFx0.Types.Observability
  ( DepthBand
  , MeaningState (..)
  , PressureBand
  , ResonanceBand
  )

-- | A 'MeaningState' projected into @[0,1]³@. Each band is normalised by
-- its enumeration position over the band's maximum, so the lowest
-- constructor maps to @0.0@ and the highest to @1.0@.
data SpectralEncoding = SpectralEncoding
  { seResonance :: !Double
    -- ^ 'ResonanceBand' position, @{0.0, 0.5, 1.0}@.
  , sePressure  :: !Double
    -- ^ 'PressureBand' position, @{0.0, 0.5, 1.0}@.
  , seDepth     :: !Double
    -- ^ 'DepthBand' position, @{0.0, 0.333, 0.667, 1.0}@ (four bands).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | The system's position in the 8D adaptive space: 'Field' (5) +
-- 'SpectralEncoding' (3), plus the scalar Conatus energy carried for the
-- downstream Conatus gate (not itself a distance dimension).
data AdaptivePosition = AdaptivePosition
  { apField         :: !Field
  , apSpectral      :: !SpectralEncoding
  , apConatusEnergy :: !Double
    -- ^ @ceScalar@; consulted by the Conatus gate, not by 'fieldDistance'.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | The zero position: empty 'Field', spectral origin, zero energy.
emptyAdaptivePosition :: AdaptivePosition
emptyAdaptivePosition =
  AdaptivePosition
    { apField         = emptyField
    , apSpectral      = SpectralEncoding 0.0 0.0 0.0
    , apConatusEnergy = 0.0
    }

-- | Project a 'MeaningState' into its spectral coordinates. Each band is
-- @fromEnum band / (cardinality - 1)@, giving an evenly spaced @[0,1]@
-- coordinate per band.
encodeMeaningState :: MeaningState -> SpectralEncoding
encodeMeaningState ms =
  SpectralEncoding
    { seResonance = normEnum (msResonance ms) (maxBound :: ResonanceBand)
    , sePressure  = normEnum (msPressure ms)  (maxBound :: PressureBand)
    , seDepth     = normEnum (msDepth ms)     (maxBound :: DepthBand)
    }

-- | Normalise an 'Enum' value to @[0,1]@ by its position over the maximum
-- constructor. A single-constructor band would divide by zero; all band
-- types here have at least three constructors, so the denominator is
-- always positive.
normEnum :: (Enum a) => a -> a -> Double
normEnum x topVal =
  let denom = fromIntegral (fromEnum topVal) :: Double
   in if denom <= 0 then 0.0 else fromIntegral (fromEnum x) / denom

-- | Hamming distance between two 'MeaningState' nodes: one unit per band
-- that differs. Range @{0,1,2,3}@. Used by Track-II neighbourhood search;
-- defined here because it is a pure function of the band triple.
hammingDistance :: MeaningState -> MeaningState -> Int
hammingDistance a b =
  (if msResonance a == msResonance b then 0 else 1)
    + (if msPressure a == msPressure b then 0 else 1)
    + (if msDepth a == msDepth b then 0 else 1)
