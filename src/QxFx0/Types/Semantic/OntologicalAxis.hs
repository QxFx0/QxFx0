{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.Semantic.OntologicalAxis
Description : canonical — the three ontological axes of concept v3 §5.

Concept v3 §5 projects every utterance onto three base ontological
category pairs:

* Бытие \/ Небытие       — 'ovBeing' in @[-1,1]@ (+1 = affirmation of
  being, −1 = negation of being).
* Стремление \/ Отрицание — 'ovStriving' in @[-1,1]@ (+1 = striving,
  −1 = denial/renunciation).
* Утверждение \/ Разрушение — 'ovAffirmation' in @[-1,1]@ (+1 =
  building/affirming, −1 = destroying).

This is a /new dimension/ of the semantic layer: distinct from the
existing 'AtomTag' vocabulary (cognitive signals), from
'InputPolarity' (a boolean), and from the knowledge-graph relation
types (@RelNegates@, @RelDestroys@, @RelOrientsToward@), which
remain edge-level.  The axes classify the /utterance as an
ontological act/, which is the input side of concept v3 §1:
\"язык — онтологическое действие\".
-}
module QxFx0.Types.Semantic.OntologicalAxis
  ( OntologicalVector(..)
  , mkOntologicalVector
  , neutralOntologicalVector
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import GHC.Generics (Generic)

-- | The ontological directedness of one utterance, one scalar per
-- category pair, each in @[-1,1]@.  Zero is genuinely neutral
-- (philosophical questions about topics carry no ontological act).
data OntologicalVector = OntologicalVector
  { ovBeing :: !Double
  , ovStriving :: !Double
  , ovAffirmation :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Clamp each axis into @[-1,1]@.
mkOntologicalVector :: Double -> Double -> Double -> OntologicalVector
mkOntologicalVector being striving affirmation = OntologicalVector
  { ovBeing = clamp11 being
  , ovStriving = clamp11 striving
  , ovAffirmation = clamp11 affirmation
  }

-- | The no-act vector: all axes zero.
neutralOntologicalVector :: OntologicalVector
neutralOntologicalVector = OntologicalVector 0.0 0.0 0.0

clamp11 :: Double -> Double
clamp11 = max (-1.0) . min 1.0
