{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Discourse state: turn memory, topic continuity, anaphora resolution. -}
module QxFx0.Types.State.Discourse
  ( DiscourseState(..)
  , emptyDiscourseState
  , recomputeDiscourse
  , TurnMemory(..)
  , EngagementLevel(..)
  , DialogPhase(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Domain (CanonicalMoveFamily)

data EngagementLevel = HighEngagement | MediumEngagement | LowEngagement
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DialogPhase = PhaseOpening | PhaseExploring | PhaseDeep | PhaseClosing
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data TurnMemory = TurnMemory
  { tmrTurnIndex :: !Int
  , tmrTopic :: !Text
  , tmrFamily :: !CanonicalMoveFamily
  , tmrRendered :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data DiscourseState = DiscourseState
  { dscTurnMemory :: !(Seq TurnMemory)
  , dscTopicChain :: ![Text]
  , dscAnaphora :: !(Map Text Text)
  , dscDiscourseMarkers :: ![Text]
  , dscEngagement :: !EngagementLevel
  , dscPhase :: !DialogPhase
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptyDiscourseState :: DiscourseState
emptyDiscourseState = DiscourseState
  { dscTurnMemory = Seq.empty
  , dscTopicChain = []
  , dscAnaphora = M.empty
  , dscDiscourseMarkers = []
  , dscEngagement = MediumEngagement
  , dscPhase = PhaseOpening
  }

recomputeDiscourse :: DiscourseState -> DiscourseState
recomputeDiscourse ds =
  let turnCount = Seq.length (dscTurnMemory ds)
      phase = case () of
        _ | turnCount <= 2  -> PhaseOpening
        _ | turnCount <= 7  -> PhaseExploring
        _                   -> PhaseDeep
  in ds { dscPhase = phase }
