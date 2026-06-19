{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Anomaly detection types for stance-based routing.

This module defines the types used to represent anomalies detected during
dialogue routing. Anomalies occur when the system's stance is challenged
beyond its capacity to maintain coherence.

== Anomaly Types

* 'AnomalyUnclassifiable' — input cannot be classified into any known family
* 'AnomalyAntiConatus' — input threatens system's operational viability
* 'AnomalySelfReferential' — self-referential loop detected
* 'AnomalyTemporal' — temporal inconsistency in stance history

== Architecture

Anomalies are detected in Route phase and handled via 'AnomalySurface',
which provides typed render payloads for the Render phase. This maintains
the separation between detection (pure logic) and rendering (surface form).
-}
module QxFx0.Types.Anomaly
  ( -- * Anomaly Types
    AnomalyType(..)
  , Anomaly(..)
  , AnomalySurface(..)
  , AnomalyTrace(..)
    -- * Constructors
  , mkAnomaly
  , mkUnclassifiable
  , mkAntiConatus
  , mkSelfReferential
  , mkTemporal
    -- * Predicates
  , isUnclassifiable
  , isAntiConatus
  , isSelfReferential
  , isTemporal
    -- * Accessors
  , anomalySeverity
  , requiresStanceRevision
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.State.SemanticCommitment (CommitmentId, TurnSeq)
import QxFx0.Types.State.Stance (StanceState)

-- | Type of anomaly detected during routing.
--
-- Each constructor represents a distinct failure mode in the dialogue
-- system's ability to maintain coherent stance.
data AnomalyType
  = AnomalyUnclassifiable
    -- ^ Input cannot be classified into any known canonical family.
    --   Triggered when all family similarity scores fall below threshold.
  | AnomalyAntiConatus
    -- ^ Input threatens system's operational viability.
    --   Triggered when conatus energy drops below critical threshold.
  | AnomalySelfReferential
    -- ^ Self-referential loop detected in input processing.
    --   Triggered when input refers to system's own processing state.
  | AnomalyTemporal
    -- ^ Temporal inconsistency in stance history.
    --   Triggered when current stance contradicts established lineage.
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Surface representation of an anomaly for rendering.
--
-- Provides typed payloads for each anomaly type, allowing the Render phase
-- to generate appropriate surface forms without re-detecting the anomaly.
data AnomalySurface
  = SurfaceUnclassifiable
      { susInput :: !Text
        -- ^ Original input text that could not be classified
      , susFamilyScores :: ![(Text, Double)]
        -- ^ Similarity scores for all canonical families
      }
  | SurfaceAntiConatus
      { sacCurrentEnergy :: !Double
        -- ^ Current conatus energy level
      , sacThreshold :: !Double
        -- ^ Critical threshold that was breached
      , sacInputText :: !Text
        -- ^ Input that triggered the energy drop
      }
  | SurfaceSelfReferential
      { ssrLoopDepth :: !Int
        -- ^ Number of self-referential iterations detected
      , ssrContext :: !Text
        -- ^ Context in which self-reference occurred
      }
  | SurfaceTemporal
      { stCurrentStance :: !StanceState
        -- ^ Current stance state
      , stHistoricalStance :: !StanceState
        -- ^ Historical stance that contradicts current
      , stContradiction :: !Text
        -- ^ Description of the temporal contradiction
      }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Trace information for anomaly detection.
--
-- Records metadata about when and how an anomaly was detected,
-- supporting observability and debugging.
data AnomalyTrace = AnomalyTrace
  { atTurn :: !TurnSeq
    -- ^ Turn sequence number when anomaly was detected
  , atCommitmentId :: !(Maybe CommitmentId)
    -- ^ Associated commitment ID, if any
  , atDetectedAtoms :: !(Set Text)
    -- ^ Atoms that triggered the anomaly detection
  , atConfidence :: !Double
    -- ^ Confidence level of the anomaly detection (0.0-1.0)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Complete anomaly record combining type, surface, and trace.
--
-- This is the primary type returned by anomaly detection functions
-- and consumed by the routing and rendering phases.
data Anomaly = Anomaly
  { aType :: !AnomalyType
    -- ^ Classification of the anomaly
  , aSurface :: !AnomalySurface
    -- ^ Surface representation for rendering
  , aTrace :: !AnomalyTrace
    -- ^ Trace information for observability
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Construct an anomaly from its components.
mkAnomaly :: AnomalyType -> AnomalySurface -> AnomalyTrace -> Anomaly
mkAnomaly = Anomaly

-- | Construct an unclassifiable anomaly.
mkUnclassifiable
  :: Text
  -- ^ Input text
  -> [(Text, Double)]
  -- ^ Family similarity scores
  -> TurnSeq
  -- ^ Turn sequence
  -> Set Text
  -- ^ Detected atoms
  -> Double
  -- ^ Detection confidence
  -> Anomaly
mkUnclassifiable input scores turn atoms conf = Anomaly
  { aType = AnomalyUnclassifiable
  , aSurface = SurfaceUnclassifiable input scores
  , aTrace = AnomalyTrace turn Nothing atoms conf
  }

-- | Construct an anti-conatus anomaly.
mkAntiConatus
  :: Double
  -- ^ Current energy
  -> Double
  -- ^ Threshold
  -> Text
  -- ^ Input text
  -> TurnSeq
  -- ^ Turn sequence
  -> Maybe CommitmentId
  -- ^ Associated commitment
  -> Set Text
  -- ^ Detected atoms
  -> Double
  -- ^ Detection confidence
  -> Anomaly
mkAntiConatus energy threshold input turn cid atoms conf = Anomaly
  { aType = AnomalyAntiConatus
  , aSurface = SurfaceAntiConatus energy threshold input
  , aTrace = AnomalyTrace turn cid atoms conf
  }

-- | Construct a self-referential anomaly.
mkSelfReferential
  :: Int
  -- ^ Loop depth
  -> Text
  -- ^ Context
  -> TurnSeq
  -- ^ Turn sequence
  -> Set Text
  -- ^ Detected atoms
  -> Double
  -- ^ Detection confidence
  -> Anomaly
mkSelfReferential depth context turn atoms conf = Anomaly
  { aType = AnomalySelfReferential
  , aSurface = SurfaceSelfReferential depth context
  , aTrace = AnomalyTrace turn Nothing atoms conf
  }

-- | Construct a temporal anomaly.
mkTemporal
  :: StanceState
  -- ^ Current stance
  -> StanceState
  -- ^ Historical stance
  -> Text
  -- ^ Contradiction description
  -> TurnSeq
  -- ^ Turn sequence
  -> Maybe CommitmentId
  -- ^ Associated commitment
  -> Set Text
  -- ^ Detected atoms
  -> Double
  -- ^ Detection confidence
  -> Anomaly
mkTemporal current historical contradiction turn cid atoms conf = Anomaly
  { aType = AnomalyTemporal
  , aSurface = SurfaceTemporal current historical contradiction
  , aTrace = AnomalyTrace turn cid atoms conf
  }

-- | Check if anomaly is unclassifiable.
isUnclassifiable :: Anomaly -> Bool
isUnclassifiable a = aType a == AnomalyUnclassifiable

-- | Check if anomaly is anti-conatus.
isAntiConatus :: Anomaly -> Bool
isAntiConatus a = aType a == AnomalyAntiConatus

-- | Check if anomaly is self-referential.
isSelfReferential :: Anomaly -> Bool
isSelfReferential a = aType a == AnomalySelfReferential

-- | Check if anomaly is temporal.
isTemporal :: Anomaly -> Bool
isTemporal a = aType a == AnomalyTemporal

-- | Get severity level of anomaly (higher = more severe).
--
-- Severity ordering:
-- * Unclassifiable: 1 (lowest)
-- * Temporal: 2
-- * SelfReferential: 3
-- * AntiConatus: 4 (highest)
anomalySeverity :: Anomaly -> Int
anomalySeverity a = case aType a of
  AnomalyUnclassifiable -> 1
  AnomalyTemporal -> 2
  AnomalySelfReferential -> 3
  AnomalyAntiConatus -> 4

-- | Check if anomaly requires stance revision.
--
-- Only temporal anomalies directly require stance revision.
-- Other anomalies may lead to revision indirectly through
-- the defense mechanism.
requiresStanceRevision :: Anomaly -> Bool
requiresStanceRevision a = aType a == AnomalyTemporal
