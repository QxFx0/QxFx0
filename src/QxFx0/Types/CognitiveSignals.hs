{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.CognitiveSignals
Description : WP-S — a compute-once bundle of derived cognitive signals.

A single, pure record of the derived signals that WP-D (doubt loop) and WP-E
(affect) both consume, so the same quantity is not recomputed (with divergent
magic constants) in three places. Computed once per turn on the Finalize path
and stored on the turn projection trace; downstream readers consult this record
rather than re-deriving from 'Field' / shadow status / posterior.

This module is in the Types layer: it holds only plain scalars/bools and depends
on nothing in Core/Bridge/Runtime.
-}
module QxFx0.Types.CognitiveSignals
  ( CognitiveSignals (..)
  , emptyCognitiveSignals
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

-- | Derived per-turn cognitive signals, computed once and shared.
data CognitiveSignals = CognitiveSignals
  { csCounterfactualEntropy :: !Double
    -- ^ Normalised parse-family entropy from @Field.fieldCounterfactual@
    --   (range @[0,1]@): high = ambiguous interpretation.
  , csFieldConfidence       :: !Double
    -- ^ Internal-coherence score from @Field.fieldConfidence@ (range
    --   @[0,1]@): low = signals disagree.
  , csShadowDisagreement    :: !Bool
    -- ^ Whether the shadow (Datalog) gate fired this turn — a
    --   verdict-vs-shadow disagreement.
  , csMaxPosterior          :: !Double
    -- ^ Peak of the Bayesian user-model posterior (@ssUserModel@,
    --   range @[0,1]@): low = no confident read of user intent.
  , csContentSaliency       :: !Double
    -- ^ WP-C: number of distinct spectral clusters detected in the meaning
    --   graph (normalised to @[0,1]@ via @/ 10@). High = many distinct topic
    --   regions; feeds the Salience controller as a top-down content signal.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | The \"no derived signals yet\" zero: maximal confidence, minimal
-- ambiguity, no disagreement, flat posterior. Mirrors the convention that an
-- uninformed system is confident-but-uninformed, not unconfident.
emptyCognitiveSignals :: CognitiveSignals
emptyCognitiveSignals = CognitiveSignals
  { csCounterfactualEntropy = 0.0
  , csFieldConfidence       = 1.0
  , csShadowDisagreement    = False
  , csMaxPosterior          = 0.0
  , csContentSaliency       = 0.0
  }
