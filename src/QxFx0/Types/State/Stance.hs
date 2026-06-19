{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Stance tracking subsystem for anomaly detection.

This module implements the stance defense mechanism that allows the system
to maintain positions, doubt them under pressure, revise them when convinced,
or collapse when overwhelmed.

== Architecture

The stance subsystem consists of four orthogonal components:

* 'StanceState' — the system's position (Held/Doubted/Revised)
* 'AdversaryState' — classification of the interlocutor (Active/Classified)
* 'CollapsePolicy' — threshold for structural collapse
* 'RecoveryPolicy' — parameters for confidence recovery

These are aggregated in 'StanceDefense', which tracks the defense state
for a specific topic.

== State Transitions

The stance follows a graded trajectory:

@
StanceHeld → StanceDoubted → StanceRevised
@

Transitions are triggered by user challenges with sufficient evidence
weight. Recovery allows returning from Doubted to Held (capped at 0.9).

== Bounded Collections

All history collections are bounded to prevent unbounded growth:

* 'sdEvidenceSeen' — max 50 atoms (FIFO eviction)
* 'slHistory' — max 50 transitions
* 'ustHistory' — max 20 user stances
-}
module QxFx0.Types.State.Stance
  ( -- * Stance State
    StanceState(..)
  , stanceConfidence
  , isHeld
  , isDoubted
  , isRevised
  , stanceConsistent
    -- * Adversary State
  , AdversaryState(..)
  , isActive
  , isClassified
    -- * Policies
  , CollapsePolicy(..)
  , defaultCollapsePolicy
  , RecoveryPolicy(..)
  , defaultRecoveryPolicy
    -- * Stance Defense
  , StanceDefense(..)
  , emptyStanceDefense
  , incrementRecoveryCounter
    -- * User Stance Tracking
  , UserStance(..)
  , emptyUserStance
  , UserStanceTracker(..)
  , emptyUserStanceTracker
    -- * Stance Lineage
  , StanceTransition(..)
  , StanceLineage(..)
  , emptyStanceLineage
  , addTransition
    -- * Constants
  , maxEvidenceSeen
  , maxLineageHistory
  , maxUserStanceHistory
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Sequence (Seq, empty)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.State.SemanticCommitment (CommitmentId, TurnSeq(..))

-- | Maximum number of atoms tracked in evidence history (FIFO eviction).
maxEvidenceSeen :: Int
maxEvidenceSeen = 50

-- | Maximum number of stance transitions in lineage history.
maxLineageHistory :: Int
maxLineageHistory = 50

-- | Maximum number of user stances in tracker history.
maxUserStanceHistory :: Int
maxUserStanceHistory = 20

-- | The system's stance on a topic.
--
-- Follows a graded trajectory: Held → Doubted → Revised.
-- Each transition is triggered by user challenges with sufficient evidence.
data StanceState
  = StanceHeld !Double
    -- ^ Position is held with given confidence (0.0-1.0).
    --   System defends against challenges.
  | StanceDoubted !Double
    -- ^ Position is doubted with reduced confidence.
    --   System is open to revision but not yet convinced.
  | StanceRevised !Text
    -- ^ Position has been revised to new text.
    --   Old position preserved in lineage for temporal anomaly detection.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Extract confidence from any stance state.
--
-- For StanceRevised, returns 1.0 (revision is complete).
stanceConfidence :: StanceState -> Double
stanceConfidence (StanceHeld conf) = conf
stanceConfidence (StanceDoubted conf) = conf
stanceConfidence (StanceRevised _) = 1.0

-- | Check if stance is in Held state.
isHeld :: StanceState -> Bool
isHeld (StanceHeld _) = True
isHeld _ = False

-- | Check if stance is in Doubted state.
isDoubted :: StanceState -> Bool
isDoubted (StanceDoubted _) = True
isDoubted _ = False

-- | Check if stance is in Revised state.
isRevised :: StanceState -> Bool
isRevised (StanceRevised _) = True
isRevised _ = False

-- | Check if stance is internally consistent.
--
-- A stance is consistent when its state constructor matches its confidence level.
-- StanceHeld with high confidence (> 0.7) is consistent.
-- StanceDought with high confidence is inconsistent (state says weakened, confidence says strong).
-- StanceRevised is always consistent (revision is complete).
-- This is used by AntiConatusChoice to detect when a move would undermine
-- the system's established position.
stanceConsistent :: StanceState -> Bool
stanceConsistent (StanceHeld conf) = conf > 0.7
stanceConsistent (StanceDoubted conf) = conf <= 0.7
stanceConsistent (StanceRevised _) = True

-- | Classification of the interlocutor's stance consistency.
--
-- When the user repeatedly challenges without changing their own position,
-- the system may classify them as static and exit the defense cycle.
data AdversaryState
  = AdversaryActive
    -- ^ User is actively engaging with changing arguments.
  | AdversaryClassified
    -- ^ User is classified as static (not changing position).
    --   System may exit defense cycle.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Check if adversary is in Active state.
isActive :: AdversaryState -> Bool
isActive AdversaryActive = True
isActive _ = False

-- | Check if adversary is in Classified state.
isClassified :: AdversaryState -> Bool
isClassified AdversaryClassified = True
isClassified _ = False

-- | Policy for structural collapse.
--
-- When conatus energy falls below the threshold while stance is Doubted,
-- the system initiates collapse (Essence reset).
data CollapsePolicy = CollapsePolicy
  { cpConatusFloor :: !Double
    -- ^ Conatus energy threshold for collapse.
    --   Default: 5.0 (matches revisePosition threshold).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default collapse policy.
defaultCollapsePolicy :: CollapsePolicy
defaultCollapsePolicy = CollapsePolicy
  { cpConatusFloor = 5.0
  }

-- | Policy for confidence recovery.
--
-- When no attacks occur for a window of turns, the system may recover
-- confidence from Doubted back to Held (capped at 0.9).
data RecoveryPolicy = RecoveryPolicy
  { rwTurnsSinceLastChallenge :: !Int
    -- ^ Number of turns without attack before recovery triggers.
    --   Default: 5.
  , rwRecoveryRate :: !Double
    -- ^ Multiplicative recovery rate per turn.
    --   Default: 0.1 (10% recovery per turn).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default recovery policy.
defaultRecoveryPolicy :: RecoveryPolicy
defaultRecoveryPolicy = RecoveryPolicy
  { rwTurnsSinceLastChallenge = 5
  , rwRecoveryRate = 0.1
  }

-- | Aggregated stance defense state for a topic.
--
-- Combines all four orthogonal components (StanceState, AdversaryState,
-- CollapsePolicy, RecoveryPolicy) with tracking fields for attack history,
-- evidence seen, and recovery counter.
data StanceDefense = StanceDefense
  { sdStance :: !StanceState
    -- ^ Current stance state (Held/Doubted/Revised).
  , sdAdversary :: !AdversaryState
    -- ^ Classification of interlocutor (Active/Classified).
  , sdAttackCount :: !Int
    -- ^ Number of consecutive attacks on this stance.
  , sdEvidenceSeen :: !(Set Text)
    -- ^ Set of atoms from user challenges (bounded by maxEvidenceSeen).
    --   Used for novelty detection in evidence weight calculation.
  , sdRecoveryCounter :: !Int
    -- ^ Number of turns since last attack.
    --   Incremented in Finalize, reset to 0 on attack.
  , sdCollapsePolicy :: !CollapsePolicy
    -- ^ Policy for structural collapse.
  , sdRecoveryPolicy :: !RecoveryPolicy
    -- ^ Policy for confidence recovery.
  , sdUserTracker :: !UserStanceTracker
    -- ^ Tracker for user's stance consistency.
  , sdCommitmentId :: !(Maybe CommitmentId)
    -- ^ Associated commitment ID from SemanticCommitmentStore.
    --   Nothing if no commitment exists for this topic.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Empty stance defense (initial state).
emptyStanceDefense :: StanceDefense
emptyStanceDefense = StanceDefense
  { sdStance = StanceHeld 0.5
  , sdAdversary = AdversaryActive
  , sdAttackCount = 0
  , sdEvidenceSeen = Set.empty
  , sdRecoveryCounter = 0
  , sdCollapsePolicy = defaultCollapsePolicy
  , sdRecoveryPolicy = defaultRecoveryPolicy
  , sdUserTracker = emptyUserStanceTracker
  , sdCommitmentId = Nothing
  }

-- | Increment recovery counter for a stance defense.
-- Used in Finalize phase to track turns since last attack.
incrementRecoveryCounter :: StanceDefense -> StanceDefense
incrementRecoveryCounter sd = sd { sdRecoveryCounter = sdRecoveryCounter sd + 1 }

-- | User's stance on a topic.
--
-- Extracted from user utterances via SemanticFeatures (sfHasChallengeMark,
-- sfHasContradiction). Used to detect consistency in user's position.
data UserStance = UserStance
  { usCommittedClaims :: !(Set Text)
    -- ^ Atoms representing user's committed claims.
    --   For challenges, contains atoms from the challenge text.
  , usConfidence :: !Double
    -- ^ User's confidence in their stance (0.0-1.0).
    --   Challenges default to 0.8 (high confidence in opposition).
  , usTurn :: !TurnSeq
    -- ^ Turn when this stance was recorded.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Empty user stance (initial state).
emptyUserStance :: UserStance
emptyUserStance = UserStance
  { usCommittedClaims = Set.empty
  , usConfidence = 0.0
  , usTurn = TurnSeq 0
  }

-- | Tracker for user's stance history.
--
-- Maintains bounded history of user stances for consistency detection.
-- Used by userStanceConsistent to check if user is maintaining position.
data UserStanceTracker = UserStanceTracker
  { ustCurrent :: !UserStance
    -- ^ Current user stance.
  , ustHistory :: !(Seq UserStance)
    -- ^ Bounded history of user stances (max maxUserStanceHistory).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Empty user stance tracker (initial state).
emptyUserStanceTracker :: UserStanceTracker
emptyUserStanceTracker = UserStanceTracker
  { ustCurrent = emptyUserStance
  , ustHistory = empty
  }

-- | A transition in the stance lineage.
--
-- Records when and why the stance changed state. Used by temporal anomaly
-- detection to explain divergence between past and present positions.
data StanceTransition = StanceTransition
  { stFrom :: !StanceState
    -- ^ Previous stance state.
  , stTo :: !StanceState
    -- ^ New stance state.
  , stTrigger :: !Text
    -- ^ Reason for transition (e.g., "user challenge with evidence X").
  , stTurn :: !TurnSeq
    -- ^ Turn when transition occurred.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Lineage of stance transitions.
--
-- Bounded history of all stance transitions for a topic. Used by temporal
-- anomaly detection to find when and why the system changed its position.
data StanceLineage = StanceLineage
  { slHistory :: !(Seq StanceTransition)
    -- ^ Bounded history of transitions (max maxLineageHistory).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Empty stance lineage (initial state).
emptyStanceLineage :: StanceLineage
emptyStanceLineage = StanceLineage
  { slHistory = empty
  }

-- | Add a transition to the lineage, maintaining bounded size.
--
-- If history exceeds maxLineageHistory, oldest transitions are evicted (FIFO).
addTransition :: StanceTransition -> StanceLineage -> StanceLineage
addTransition trans lineage =
  let newHistory = slHistory lineage Seq.|> trans
      boundedHistory =
        if Seq.length newHistory > maxLineageHistory
          then Seq.drop (Seq.length newHistory - maxLineageHistory) newHistory
          else newHistory
  in lineage { slHistory = boundedHistory }
