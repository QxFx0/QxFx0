{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.Semantic.MoveGraph
Description : canonical — the ontological move graph: typed transition operators over the user R5 state (concept v3 §6).

Concept v3 §6 replaces reply selection with /computation of the
transition operator/: under Protocol A the system searches for the
ontological move that carries the user's state @S_t@ closest to the
target state @S*@ (return into the viability contour).  This module
is the typed shape of that graph:

* 'OntologicalMove' — a closed, ordered set of four operators
  (mirror the state → establish resonance → affirm being → open an
  alternative).  The canonical order is the deterministic
  tie-break of the search.
* 'moveEffect' — the frozen v1 effect matrix: each move's Δ on the
  five R5 axes.  Hand-set and frozen on release (same discipline as
  the R5 encoder); replacing the matrix with fitted values is an
  offline, governed 'currentMathVersion' bump.
* 'OntologicalMovePlan' — the search result carried through the
  turn: the chosen move, the predicted distances to @S*@ before and
  after, and whether the resonance gate admitted the
  affirmation-of-being move.
* 'OntologicalMoveTrace' — replay observability.

The search itself ('QxFx0.Semantic.MoveGraph.planOntologicalMove')
and the receiver-conditioned verbalisation
('QxFx0.User.Decompress') live in the implementation layers; this
module is pure typed shape so 'Types' stays implementation-free.

== Resonance ordering

'MoveAffirmBeing' is admissible only above the resonance gate
('QxFx0.Semantic.Ontological.resonanceGateThreshold').  At low
resonance the mirror/resonance moves dominate the search on their
own merits (they move the resonance axis toward @S*@), so the
concept v3 §5 ordering — first mirror the state, then establish
resonance, only then the ontological move — emerges from the search,
not from hardcoded sequencing.
-}
module QxFx0.Types.Semantic.MoveGraph
  ( OntologicalMove(..)
  , ontologicalMoveTag
  , allOntologicalMoves
  , moveEffect
  , applyMoveEffect
  , transitionUserR5
  , OntologicalMovePlan(..)
  , OntologicalMoveTrace(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.User.R5 (UserR5State(..), mkUserR5State)

-- | The closed set of ontological transition operators, in canonical
-- (tie-break) order.
data OntologicalMove
  = MoveMirrorState
    -- ^ Отражение состояния: name the receiver's state honestly,
    --   without smoothing it.  Effect: +resonance, −tension.
  | MoveEstablishResonance
    -- ^ Установление резонанса: presence and contact beside the
    --   state, not against it.  Effect: ++resonance, +consolidation.
  | MoveAffirmBeing
    -- ^ Встречный вектор утверждения бытия — the system's own
    --   ontological position, presented not as advice but as a
    --   standing alternative.  Gated by the resonance threshold.
  | MoveOpenAlternative
    -- ^ Контрфактуальный ход: open one alternative branch of the
    --   current frame.  Effect: ++counterfactual.
  deriving stock (Eq, Show, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Stable snake_case tag for traces and render tags.
ontologicalMoveTag :: OntologicalMove -> Text
ontologicalMoveTag m = case m of
  MoveMirrorState       -> "mirror_state"
  MoveEstablishResonance -> "establish_resonance"
  MoveAffirmBeing       -> "affirm_being"
  MoveOpenAlternative   -> "open_alternative"

-- | Canonical order (tie-break of the deterministic search).
allOntologicalMoves :: [OntologicalMove]
allOntologicalMoves = [minBound .. maxBound]

-- | The frozen v1 effect matrix: Δ on the R5 axes per move.  All
-- constructive moves are mild by design — the system proposes a
-- transition, it never claims to produce one.
moveEffect :: OntologicalMove -> (Double, Double, Double, Double, Double)
moveEffect m = case m of
  MoveMirrorState ->
    ( 0.10, -0.05, 0.00, 0.00, 0.00)
    -- being seen lowers pressure slightly and builds resonance.
  MoveEstablishResonance ->
    ( 0.20, -0.05, 0.00, 0.05, 0.00)
    -- presence is the strongest resonance lever in the set.
  MoveAffirmBeing ->
    ( 0.10, -0.05, 0.15, 0.00, 0.00)
    -- the counter-vector of the affirmation of being: confidence
    -- and resonance, no counterfactual push.
  MoveOpenAlternative ->
    ( 0.00, 0.00, 0.05, 0.00, 0.20)
    -- opens the ability to see alternatives.

-- | Apply a move's effect to a state (clamped by 'mkUserR5State').
applyMoveEffect :: OntologicalMove -> UserR5State -> UserR5State
applyMoveEffect m s =
  let (dRes, dAtm, dConf, dCons, dCf) = moveEffect m
  in mkUserR5State
       (r5Resonance s + dRes)
       (r5Atmosphere s + dAtm)
       (r5Confidence s + dConf)
       (r5Consolidation s + dCons)
       (r5Counterfactual s + dCf)

-- | The v1 transition model: @S_t+1 = transition(S_t, move)@ —
-- 'applyMoveEffect' with a move, persistence without one.  This is
-- the hypothesis the residual audit measures; fitting real
-- transitions offline is a governed later phase.
transitionUserR5 :: Maybe OntologicalMove -> UserR5State -> UserR5State
transitionUserR5 Nothing     s = s
transitionUserR5 (Just move) s = applyMoveEffect move s

-- | The route-stage plan produced by the deterministic search.
data OntologicalMovePlan = OntologicalMovePlan
  { ompMove :: !OntologicalMove
    -- ^ The chosen operator.
  , ompDistanceBefore :: !Double
    -- ^ Predicted 'r5Distance' from the current state to S*.
  , ompDistanceAfter :: !Double
    -- ^ Predicted distance after applying the chosen move.
  , ompAffirmGatePassed :: !Bool
    -- ^ Whether the resonance gate admitted 'MoveAffirmBeing' this
    --   turn (observability of the §5 ordering).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Replay-visible move-graph observability for one turn.
data OntologicalMoveTrace = OntologicalMoveTrace
  { omtMove :: !Text
    -- ^ 'ontologicalMoveTag' of the chosen move.
  , omtDistanceBefore :: !Double
  , omtDistanceAfter :: !Double
  , omtAffirmGatePassed :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
