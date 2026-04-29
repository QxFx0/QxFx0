{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Semantic-facing persisted state: traces, meaning graph, dream state, and decision memory. -}
module QxFx0.Types.State.Semantic
  ( SemanticState(..)
  , emptySemanticState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Decision (SemanticAnchor, TurnDecision)
import QxFx0.Types.Domain
  ( AtomTrace
  , ClusterDef
  , emptyAtomTrace
  )
import QxFx0.Types.Dream (DreamState, emptyDreamState)
import QxFx0.Types.Intuition (IntuitiveState, defaultIntuitiveState)
import QxFx0.Types.Observability
  ( KernelPulse
  , MeaningGraph
  , emptyKernelPulse
  , emptyMeaningGraph
  )
import QxFx0.Types.Vec (zeroVec)

data SemanticState = SemanticState
  { semTrace :: !AtomTrace
  , semMeaningGraph :: !MeaningGraph
  , semKernelPulse :: !KernelPulse
  , semBlockedConcepts :: ![Text]
  , semClusters :: ![ClusterDef]
  , semDreamState :: !DreamState
  , semIntuitionState :: !(Maybe IntuitiveState)
  , semSemanticAnchor :: !(Maybe SemanticAnchor)
  , semLastTurnDecision :: !(Maybe TurnDecision)
  , semIntuitConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticState where
  toJSON sem = object
    [ "trace" .= semTrace sem
    , "meaningGraph" .= semMeaningGraph sem
    , "kernelPulse" .= semKernelPulse sem
    , "blockedConcepts" .= semBlockedConcepts sem
    , "clusters" .= semClusters sem
    , "dreamState" .= semDreamState sem
    , "intuitionState" .= semIntuitionState sem
    , "semanticAnchor" .= semSemanticAnchor sem
    , "lastTurnDecision" .= semLastTurnDecision sem
    , "intuitConfidence" .= semIntuitConfidence sem
    ]

instance FromJSON SemanticState where
  parseJSON = withObject "SemanticState" $ \o -> SemanticState
    <$> o .: "trace"
    <*> o .: "meaningGraph"
    <*> o .: "kernelPulse"
    <*> o .: "blockedConcepts"
    <*> o .: "clusters"
    <*> o .:? "dreamState" .!= emptyDreamState zeroVec
    <*> o .:? "intuitionState" .!= Just defaultIntuitiveState
    <*> o .:? "semanticAnchor" .!= Nothing
    <*> o .:? "lastTurnDecision" .!= Nothing
    <*> o .: "intuitConfidence"

emptySemanticState :: SemanticState
emptySemanticState = SemanticState
  { semTrace = emptyAtomTrace
  , semMeaningGraph = emptyMeaningGraph
  , semKernelPulse = emptyKernelPulse
  , semBlockedConcepts = []
  , semClusters = []
  , semDreamState = emptyDreamState zeroVec
  , semIntuitionState = Just defaultIntuitiveState
  , semSemanticAnchor = Nothing
  , semLastTurnDecision = Nothing
  , semIntuitConfidence = 0.0
  }
