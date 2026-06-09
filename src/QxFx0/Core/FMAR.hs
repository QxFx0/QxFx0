{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Core.FMAR
Description : FMAR Phase-4 — Field-Modulated Adaptive Routing core.

'fmarSelectFamily' reconciles the keyword-detector recommendation with the
system's Field position. The detector remains the content-classification
backbone; FMAR may override its choice when the current 'AdaptivePosition'
is too far (in 'fieldDistance') from the recommended family's target Field —
i.e. when the system's state does not match the state in which that family
is authentic.

FMAR does NOT subsume the Conatus gate. This module computes the
Field-modulated choice; the downstream Conatus gate (in
@QxFx0.Core.TurnRouting.Cascade@) may still veto a risky family, in which
case 'fmarSelectFamilyRescue' picks the closest Conatus-permitted family.
The wiring of both into the live pipeline (behind @QXFX0_FMAR@) is Phase 7.

Pure: no IO, no runtime state.
-}
module QxFx0.Core.FMAR
  ( fmarSelectFamily
  , fmarSeed
  , computeAdaptivePosition
  , FmarMode (..)
  , readFmarMode
  , isFmarActive
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.FMAR (FmarMode(..))
import QxFx0.Self.AdaptivePosition
  ( AdaptivePosition (..)
  , SpectralEncoding
  , encodeMeaningState
  )
import QxFx0.Self.Conatus (ConatusEnergy (..))
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  )
import QxFx0.Self.FamilyTargets
  ( FamilyTarget (..)
  , closestFamilyByField
  , familyTargetFor
  , fieldDistance
  , fmarDistanceThreshold
  )
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily (..))
import QxFx0.Types.Observability (MeaningState (..))

-- | Select the Field-modulated move family.
--
-- 1. Trust the detector recommendation as the candidate.
-- 2. If the current position is within 'fmarDistanceThreshold' of the
--    recommended family's target Field, keep the recommendation.
-- 3. Otherwise, search for the closest /viable/ family — one whose
--    @ftMinConatus@ is satisfied by the position's energy and whose
--    @ftMaxCounterfactual@ admits the position's current counterfactual.
-- 4. If no family is viable, fall back to 'CMContact'.
--
-- This function does not apply the Conatus gate's hard veto; that is a
-- separate downstream step. It only uses @ftMinConatus@ as a /viability/
-- filter when searching for an override, so FMAR never proposes a family
-- the system plainly lacks the energy to sustain.
fmarSelectFamily
  :: AdaptivePosition
  -> CanonicalMoveFamily      -- ^ recommendedFamily from keyword detectors
  -> [FamilyTarget]
  -> CanonicalMoveFamily
fmarSelectFamily pos recommended targets =
  let recTarget = familyTargetFor recommended
      recDist   = fieldDistance pos (ftTargetField recTarget)
   in if recDist <= fmarDistanceThreshold
        then recommended
        else closestFamilyByField pos viableTargets
  where
    curCounterfactual = unCounterfactual (fieldCounterfactual (apField pos))

    viable t =
      ftMinConatus t <= apConatusEnergy pos
        && ftMaxCounterfactual t >= curCounterfactual

    viableTargets = filter viable targets

-- | FMAR Phase-6: extend a hash seed with the three most salient Field
-- components — confidence, valence, arousal — so that different Field
-- states systematically map to different tone variants through
-- 'QxFx0.Render.Dialogue.pickDeterministic' modulo-indexing.
--
-- Zero new logic; different Field → different seed → different variant.
-- With 'emptyField' (the baseline), the seed carries neutral zeros and
-- behaviour is identical to the non-FMAR path.
--
-- Deliberate deferral: exported and unit-tested but has zero production
-- call sites. Wiring into the dialogue rendering pipeline is Phase 7.
fmarSeed :: Text -> Field -> Text
fmarSeed baseSeed delta =
  baseSeed <> T.pack "|"
    <> T.pack (show (unFieldConfidence (fieldConfidence delta)))
    <> T.pack "|" <> T.pack (show (atmosphereValence (fieldAtmosphere delta)))
    <> T.pack "|" <> T.pack (show (atmosphereArousal (fieldAtmosphere delta)))

-- | FMAR Phase-7: compute the 8D 'AdaptivePosition' from the three
-- signals already present in the Prepare phase — 'Field', 'MeaningState',
-- and 'ConatusEnergy'. Pure; no IO.
computeAdaptivePosition :: Field -> MeaningState -> ConatusEnergy -> AdaptivePosition
computeAdaptivePosition field ms ce =
  AdaptivePosition
    { apField         = field
    , apSpectral      = encodeMeaningState ms
    , apConatusEnergy = ceScalar ce
    }

-- | Parse a @QXFX0_FMAR@ value into an 'FmarMode'. Unset (@Nothing@),
-- empty, @0@, @off@, or @false@ → 'FmarOff'. @shadow@ → 'FmarShadow'.
-- @live@, @1@, @on@, @true@ → 'FmarLive'. Unrecognised → 'FmarOff'
-- (fail-closed: an unknown value never silently enables live routing).
readFmarMode :: Maybe Text -> FmarMode
readFmarMode mraw =
  case fmap (T.toLower . T.strip) mraw of
    Just v
      | v == T.pack "shadow"                         -> FmarShadow
      | v `elem` map T.pack ["live", "1", "on", "true"] -> FmarLive
      | otherwise                                    -> FmarOff
    Nothing -> FmarOff

-- | True when FMAR should compute its decision at all (shadow or live).
isFmarActive :: FmarMode -> Bool
isFmarActive FmarOff = False
isFmarActive _       = True
