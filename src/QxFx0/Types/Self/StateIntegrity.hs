{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Self.StateIntegrity
  ( StateIntegrityWeights(..)
  , StateIntegrityComponents(..)
  , StateIntegrity(..)
  , stateIntegrityComponentSum
  , StateIntegrityGradient(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.=), (.:), (.:?), (.!=))
import Data.Aeson.Types (Parser)
import GHC.Generics (Generic)

data StateIntegrityWeights = StateIntegrityWeights
  { siwMorphology :: !Double
  , siwIdentity   :: !Double
  , siwTurns      :: !Double
  , siwViolation  :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Persisted under the historical @cw*@ keys (frozen 2026-11-23, P4
-- rename): the Haskell field names changed, the wire schema did not.
instance ToJSON StateIntegrityWeights where
  toJSON w = object
    [ "cwMorphology" .= siwMorphology w
    , "cwIdentity" .= siwIdentity w
    , "cwTurns" .= siwTurns w
    , "cwViolation" .= siwViolation w
    ]

instance FromJSON StateIntegrityWeights where
  parseJSON = withObject "StateIntegrityWeights" $ \o ->
    StateIntegrityWeights
      <$> o .: "cwMorphology"
      <*> o .: "cwIdentity"
      <*> o .: "cwTurns"
      <*> o .: "cwViolation"

-- | The decomposed scalar contribution of each axis. Kept separate
-- from 'StateIntegrity' so that diagnostics and observability can
-- show which axis is carrying (or failing) the system, not only the
-- aggregate.
data StateIntegrityComponents = StateIntegrityComponents
  { sicMorphology     :: !Double
  , sicIdentity       :: !Double
  , sicTurns          :: !Double
  , sicPenalty        :: !Double
    -- ^ Violation penalty only ('BlanketViolation's). Semantically
    --   locked: self-divergence adjustments never land here.
  , sicSelfDivergence :: !Double
    -- ^ A-slice: self-consistency penalty share (<= 0), set by the
    --   prepare-stage application of the previous turn's divergence.
    --   Kept as a dedicated component so the violation channel stays
    --   semantically pure.  Invariant: @siScalar == sum of all five@.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON StateIntegrityComponents where
  toJSON comps = object
    [ "ccMorphology" .= sicMorphology comps
    , "ccIdentity" .= sicIdentity comps
    , "ccTurns" .= sicTurns comps
    , "ccPenalty" .= sicPenalty comps
    , "ccSelfDivergence" .= sicSelfDivergence comps
    ]

-- | Backward-compatible parse: persisted pre-A2 traces lacked the
-- @sicSelfDivergence@ key, so it defaults to 0.0 when absent.
instance FromJSON StateIntegrityComponents where
  parseJSON = withObject "StateIntegrityComponents" $ \o ->
    StateIntegrityComponents
      <$> o .:? "ccMorphology" .!= 0.0
      <*> o .:? "ccIdentity" .!= 0.0
      <*> o .:? "ccTurns" .!= 0.0
      <*> o .:? "ccPenalty" .!= 0.0
      <*> o .:? "ccSelfDivergence" .!= 0.0

-- | The scalar value of the structural integrity functional together
-- with its per-axis decomposition. Invariant: @siScalar == sum of all
-- five 'StateIntegrityComponents' fields@.
data StateIntegrity = StateIntegrity
  { siScalar     :: !Double
  , siComponents :: !StateIntegrityComponents
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Persisted under the historical @ce*@ keys (frozen 2026-11-23, P4
-- rename): the Haskell field names changed, the wire schema did not.
instance ToJSON StateIntegrity where
  toJSON si = object
    [ "ceScalar" .= siScalar si
    , "ceComponents" .= siComponents si
    ]

-- | Sum of all five components — the definition that produces
-- 'siScalar' ('QxFx0.Self.StateIntegrity.computeStateIntegrityEnergyWith').
stateIntegrityComponentSum :: StateIntegrityComponents -> Double
stateIntegrityComponentSum c =
  sicMorphology c + sicIdentity c + sicTurns c + sicPenalty c + sicSelfDivergence c

-- | Audit 2026-10-16 (p.11): persisted JSON is a trust boundary.
-- 'siScalar' is re-derived from the component sum on every decode; the
-- mandatory key is still required (schema unchanged), but its value is
-- not trusted, so a persisted inconsistency cannot contradict the
-- components in consumers (replay traces, corpus extraction,
-- promotion).  Backward compatible: pre-A2 blobs default the fifth
-- component to 0.0, where the old scalar already equaled the
-- four-component sum.
instance FromJSON StateIntegrity where
  parseJSON = withObject "StateIntegrity" $ \o -> do
    _ <- (o .: "ceScalar" :: Parser Double)
    comps <- o .: "ceComponents"
    pure StateIntegrity
      { siScalar     = stateIntegrityComponentSum comps
      , siComponents = comps
      }

-- | The gradient of the smooth part of \(C\) at a blanket. Each
-- component is the partial derivative of \(C\) with respect to that
-- blanket axis, treating the blanket fields as real-valued for the
-- duration of the derivative. The violation penalty contributes
-- nothing because it is a step function in \(|v|\), not a smooth
-- function of \((m, c, t)\).
--
-- All components are strictly positive on any blanket whose
-- integer fields are non-negative (which is the universe of all
-- legitimately-constructed 'SelfBlanket' values), so the gradient
-- always points into the strictly-growing orthant.
data StateIntegrityGradient = StateIntegrityGradient
  { sigMorphology :: !Double
  , sigIdentity   :: !Double
  , sigTurns      :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Persisted under the historical @cg*@ keys (frozen 2026-11-23, P4
-- rename): the Haskell field names changed, the wire schema did not.
instance ToJSON StateIntegrityGradient where
  toJSON g = object
    [ "cgMorphology" .= sigMorphology g
    , "cgIdentity" .= sigIdentity g
    , "cgTurns" .= sigTurns g
    ]

instance FromJSON StateIntegrityGradient where
  parseJSON = withObject "StateIntegrityGradient" $ \o ->
    StateIntegrityGradient
      <$> o .: "cgMorphology"
      <*> o .: "cgIdentity"
      <*> o .: "cgTurns"