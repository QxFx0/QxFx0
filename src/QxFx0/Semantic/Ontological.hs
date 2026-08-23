{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Ontological
Description : observer — deterministic v1 classifier of the utterance's ontological directedness (concept v3 §5).

@classifyOntological@ projects one utterance onto the three category
pairs of 'OntologicalVector' via fixed marker lexicons.  Each axis is
the total-count-normalized balance

@
axis = (posHits − negHits) / max 1 (posHits + negHits)
@

so the result is bounded by construction and zero when no markers
fire (a philosophical question carries no ontological act — the
concept v3 §9 decoy requirement).

Negation safety uses the same replace-then-count discipline as the
R5 encoder: negative phrases are blanked out before positive
markers are counted, so \"не хочу\" never counts as striving+.

'resonanceGateThreshold' / 'ontologicalMoveAdmissible' implement the
concept v3 §5 /resonance threshold/: the operator of affirmation of
being may be applied only when the user's resonance is above the
gate.  Order of moves — mirror the state, establish resonance, then
make the ontological move — is the move-graph's concern; this
predicate is the pure gate it will consume.
-}
module QxFx0.Semantic.Ontological
  ( classifyOntological
  , resonanceGateThreshold
  , ontologicalMoveAdmissible
    -- * Marker lexicons (exported for tests and audit)
  , beingPositiveMarkers
  , beingNegativeMarkers
  , strivingPositiveMarkers
  , strivingNegativeMarkers
  , affirmationPositiveMarkers
  , affirmationNegativeMarkers
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Semantic.OntologicalAxis
import QxFx0.Types.User.R5 (UserR5State (..))
import QxFx0.Semantic.Markers
  ( beingPositiveMarkers
  , beingNegativeMarkers
  , strivingPositiveMarkers
  , strivingNegativeMarkers
  , affirmationPositiveMarkers
  , affirmationNegativeMarkers
  )

-- | Classify the ontological directedness of one utterance.  Total
-- and deterministic; empty and marker-free input yields
-- 'neutralOntologicalVector'.
classifyOntological :: Text -> OntologicalVector
classifyOntological raw =
  let norm = T.intercalate " " . T.words . T.replace "ё" "е" . T.toLower $ raw
      being = axisOf norm beingPositiveMarkers beingNegativeMarkers
      striving = axisOf norm strivingPositiveMarkers strivingNegativeMarkers
      affirmation = axisOf norm affirmationPositiveMarkers affirmationNegativeMarkers
  in mkOntologicalVector being striving affirmation
  where
    -- Negation safety: negative phrases are counted and blanked out
    -- before positive markers fire ("не хочу" is not striving+).
    axisOf text pos neg =
      let negHits = fromIntegral (countAny text neg)
          cleaned = blankAll text neg
          posHits = fromIntegral (countAny cleaned pos)
          total = posHits + negHits
      in if total <= 0 then 0.0 else (posHits - negHits) / total
    countAny text markers =
      length (filter (`T.isInfixOf` text) markers)
    blankAll text markers =
      foldr (\m acc -> T.replace m " § " acc) text markers

-- | The resonance gate for applying the affirmation-of-being
-- operator (concept v3 §5).  Hand-set v1; calibration against
-- labelled dialogue is a later, governed phase.
resonanceGateThreshold :: Double
resonanceGateThreshold = 0.55

-- | May the ontological move (the counter-vector of affirmation of
-- being) be applied given the user's current resonance?  Below the
-- gate the system must first mirror the state and establish
-- resonance — applying the move too early reads as cold rejection
-- and pushes the receiver deeper into non-being.
ontologicalMoveAdmissible :: UserR5State -> Bool
ontologicalMoveAdmissible userState =
  r5Resonance userState > resonanceGateThreshold
