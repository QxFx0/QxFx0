{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.MoveGraph
Description : observer — deterministic search for the ontological transition operator (concept v3 §6).

'planOntologicalMove' implements the Protocol A generation step of
concept v3 §6: /not a selection of replies, but a computation of the
transition operator/.  Given the decoded user state, the input's
ontological directedness, and the personalization context, it
returns the move whose modelled effect carries the state closest to
the target @S*@ — or 'Nothing' when the turn carries no ontological
act to answer and no drift toward the contour edge.

== When the layer fires (staged cutover)

The move layer /leads/ the turn with its act line; it never replaces
the corpus-backed content path (M4-SEMANTIC-CORE-003\/M6-FELT stay
untouched).  It fires only under Protocol A when at least one holds:

* the input carries a negative ontological act
  ('ovStriving' < 0, 'ovBeing' < 0, or 'ovAffirmation' < 0) — there
  is a vector to answer with a counter-vector; or
* the user's score has drifted below the personalized baseline by
  more than 'moveDriftMargin' — the state is sliding toward the
  contour edge.

== Target S* (v1)

@S*@ is the centre of viability — 'neutralUserR5State' — anchored
toward the personalized baseline where one exists: with a baseline
the resonance\/confidence mid-point shifts halfway toward the
baseline's implied operating point.  This is a hand-set v1
definition, frozen with the rest of the regime; concept v3 leaves
finer target shapes to the calibrated phase.

== Search

Every admissible move (all four, minus 'MoveAffirmBeing' below the
resonance gate) is scored by the predicted 'r5Distance' to @S*@;
the minimum wins; ties break by canonical move order.  The search is
therefore a total, deterministic function of its inputs.
-}
module QxFx0.Semantic.MoveGraph
  ( moveDriftMargin
  , viabilityTarget
  , moveNeeded
  , planOntologicalMove
  ) where

import QxFx0.Semantic.Ontological (ontologicalMoveAdmissible)
import QxFx0.Types.Semantic.MoveGraph
import QxFx0.Types.Semantic.OntologicalAxis (OntologicalVector (..))
import QxFx0.Types.User.R5
  ( UserR5State
  , mkUserR5State
  , negativeEvidenceEarned
  , r5Distance
  )

-- | How far below the personalized baseline the score must drift
-- before the move layer fires without a negative ontological act.
-- Hand-set v1 (frozen).
moveDriftMargin :: Double
moveDriftMargin = 0.10

-- | The target state S* for the search: the /connected-calm/ centre
-- of viability — resonance above the neutral midline (a connected
-- receiver), atmosphere low, confidence and consolidation mid,
-- counterfactual slightly open.  With a personalization the
-- confidence axis anchors halfway toward the baseline-mapped
-- operating point.  Hand-set v1 (frozen); finer target shapes are a
-- calibrated-phase change.
viabilityTarget :: Maybe Double -> UserR5State
viabilityTarget Nothing =
  mkUserR5State 0.65 0.20 0.50 0.50 0.50
viabilityTarget (Just baseline) =
  let anchor = max 0.0 (min 1.0 baseline)
      blend x = x + 0.5 * (anchor - x)
  in mkUserR5State
       0.65
       0.20
       (blend 0.50)
       0.50
       0.50

-- | Does this turn need an ontological counter-move at all?
-- The drift branch is evidence-gated by 'negativeEvidenceEarned':
-- the encoder's score conflates utterance form (question shape,
-- topic continuity) with user state, so a style change alone
-- (e.g. a challenge after a definitional question) must not fire
-- the move layer — the drop has to be earned by negative signals.
moveNeeded
  :: UserR5State    -- ^ observed state (evidence for the drift branch)
  -> OntologicalVector
  -> Maybe Double   -- ^ personalized baseline, if any
  -> Double         -- ^ observed user Conatus score
  -> Bool
moveNeeded userState onto mBaseline score
  | ovStriving onto < 0 = True
  | ovBeing onto < 0 = True
  | ovAffirmation onto < 0 = True
  | Just baseline <- mBaseline
  , negativeEvidenceEarned userState
  , score < baseline - moveDriftMargin = True
  | otherwise = False

-- | Deterministic search for the ontological transition operator.
-- Total: every (state, directedness, baseline, score) tuple yields
-- either 'Nothing' (no act to answer, no earned drift) or the best
-- admissible move with its predicted distances.
planOntologicalMove
  :: UserR5State           -- ^ decoded user state S_t
  -> OntologicalVector     -- ^ input's ontological directedness
  -> Maybe Double          -- ^ personalized baseline, if any
  -> Double                -- ^ observed user Conatus score
  -> Maybe OntologicalMovePlan
planOntologicalMove userState onto mBaseline score
  | not (moveNeeded userState onto mBaseline score) = Nothing
  | otherwise =
      let target = viabilityTarget mBaseline
          gatePassed = ontologicalMoveAdmissible userState
          admissible =
            if gatePassed
              then allOntologicalMoves
              else filter (/= MoveAffirmBeing) allOntologicalMoves
          distanceBefore = r5Distance userState target
          scored =
            [ (r5Distance (applyMoveEffect m userState) target, m)
            | m <- admissible
            ]
          pick (d1, m1) (d2, m2) =
            if d2 < d1 then (d2, m2) else (d1, m1)  -- canonical-order tie-break
          (distanceAfter, best) = foldr1 pick scored
      in Just OntologicalMovePlan
           { ompMove = best
           , ompDistanceBefore = distanceBefore
           , ompDistanceAfter = distanceAfter
           , ompAffirmGatePassed = gatePassed
           }
