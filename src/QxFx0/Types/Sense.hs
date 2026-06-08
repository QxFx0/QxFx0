{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Sense
  ( SemanticNodeId(..)
  , FamilyId(..)
  , SenseAxis(..)
  , SensePolarity(..)
  , SenseOperator(..)
  , SenseVector(..)
  , ResponseSensePlan(..)
  , MicroPlan(..)
  , RhetoricalMove(..)
  , FallbackPolicy(..)
  , ImplicationDirection(..)
  , emptySenseVector
  , emptyResponseSensePlan
  , emptyMicroPlan
  , renderSenseAxis
  , renderSenseOperator
  , rhetoricalMoveFromOperator
  , fallbackPolicyFromPhase
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase(..))

newtype SemanticNodeId = SemanticNodeId { unSemanticNodeId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype FamilyId = FamilyId { unFamilyId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SenseAxis
  = AxIdentity
  | AxCause
  | AxPurpose
  | AxContrast
  | AxBoundary
  | AxAction
  | AxState
  | AxKnowledge
  | AxNorm
  | AxTime
  | AxPossibility
  | AxSelf
  | AxOther
  | AxRepair
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

data SensePolarity
  = SpAffirm
  | SpDeny
  | SpUncertain
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SenseOperator
  = OpDefine
  | OpGround
  | OpDistinguish
  | OpExplainCause
  | OpExplainPurpose
  | OpReflect
  | OpConstrain
  | OpRepair
  | OpClarify
  | OpDeepen
  | OpNextStep
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SenseVector = SenseVector
  { svAnchor :: !SemanticNodeId
  , svLexicalFamily :: !(Maybe FamilyId)
  , svEvidenceNodes :: ![SemanticNodeId]
  , svAxes :: !(Map SenseAxis Double)
  , svOperators :: ![SenseOperator]
  , svPolarity :: !SensePolarity
  , svAgent :: !(Maybe SemanticNodeId)
  , svTarget :: !(Maybe SemanticNodeId)
  , svConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data ResponseSensePlan = ResponseSensePlan
  { rspInputVector :: !SenseVector
  , rspChosenOperator :: !SenseOperator
  , rspPreservedAxes :: ![SenseAxis]
  , rspShiftReason :: !Text
  , rspDistance :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data MicroPlan = MicroPlan
  { mpRhetoricalMoves :: ![RhetoricalMove]
  , mpExplicitness :: !Double
  , mpStructureBudget :: !Int
  , mpFallbackPolicy :: !FallbackPolicy
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | RhetoricalMove — typed representation of micro-plan moves.
-- Replaces string literals like "repair", "clarify", "ground", etc.
data RhetoricalMove
  = MvRepair
  | MvClarify
  | MvGround
  | MvDefine
  | MvDistinguish
  | MvDeepen
  | MvReflect
  | MvExplainCause
  | MvExplainPurpose
  | MvNextStep
  | MvConstrain
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | FallbackPolicy — typed representation of fallback strategies.
-- Replaces string literals like "repair_first", "clarify_first", etc.
data FallbackPolicy
  = FbRepairFirst
  | FbClarifyFirst
  | FbGroundFirst
  | FbContestBound
  | FbCloseBound
  | FbSafeDegrade
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | ImplicationDirection — typed representation of implication direction.
-- Replaces string literals "forward" / "bounded".
data ImplicationDirection
  = DirForward
  | DirBounded
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | Convert SenseOperator to RhetoricalMove.
rhetoricalMoveFromOperator :: SenseOperator -> RhetoricalMove
rhetoricalMoveFromOperator OpRepair = MvRepair
rhetoricalMoveFromOperator OpClarify = MvClarify
rhetoricalMoveFromOperator OpGround = MvGround
rhetoricalMoveFromOperator OpDefine = MvDefine
rhetoricalMoveFromOperator OpDistinguish = MvDistinguish
rhetoricalMoveFromOperator OpDeepen = MvDeepen
rhetoricalMoveFromOperator OpReflect = MvReflect
rhetoricalMoveFromOperator OpExplainCause = MvExplainCause
rhetoricalMoveFromOperator OpExplainPurpose = MvExplainPurpose
rhetoricalMoveFromOperator OpNextStep = MvNextStep
rhetoricalMoveFromOperator OpConstrain = MvConstrain

-- | Convert DialoguePhase to FallbackPolicy.
fallbackPolicyFromPhase :: DialoguePhase -> FallbackPolicy
fallbackPolicyFromPhase Repairing = FbRepairFirst
fallbackPolicyFromPhase Clarifying = FbClarifyFirst
fallbackPolicyFromPhase Grounding = FbGroundFirst
fallbackPolicyFromPhase Contesting = FbContestBound
fallbackPolicyFromPhase Closing = FbCloseBound
fallbackPolicyFromPhase _ = FbSafeDegrade

emptySenseVector :: SenseVector
emptySenseVector = SenseVector
  { svAnchor = SemanticNodeId "unknown"
  , svLexicalFamily = Nothing
  , svEvidenceNodes = []
  , svAxes = M.empty
  , svOperators = [OpGround]
  , svPolarity = SpUncertain
  , svAgent = Nothing
  , svTarget = Nothing
  , svConfidence = 0.0
  }

emptyResponseSensePlan :: ResponseSensePlan
emptyResponseSensePlan = ResponseSensePlan
  { rspInputVector = emptySenseVector
  , rspChosenOperator = OpGround
  , rspPreservedAxes = []
  , rspShiftReason = "default_grounding"
  , rspDistance = 0
  }

emptyMicroPlan :: MicroPlan
emptyMicroPlan = MicroPlan
  { mpRhetoricalMoves = []
  , mpExplicitness = 0.5
  , mpStructureBudget = 1
  , mpFallbackPolicy = FbSafeDegrade
  }

renderSenseAxis :: SenseAxis -> Text
renderSenseAxis axis = case axis of
  AxIdentity -> "identity"
  AxCause -> "cause"
  AxPurpose -> "purpose"
  AxContrast -> "contrast"
  AxBoundary -> "boundary"
  AxAction -> "action"
  AxState -> "state"
  AxKnowledge -> "knowledge"
  AxNorm -> "norm"
  AxTime -> "time"
  AxPossibility -> "possibility"
  AxSelf -> "self"
  AxOther -> "other"
  AxRepair -> "repair"

renderSenseOperator :: SenseOperator -> Text
renderSenseOperator op = case op of
  OpDefine -> "define"
  OpGround -> "ground"
  OpDistinguish -> "distinguish"
  OpExplainCause -> "explain_cause"
  OpExplainPurpose -> "explain_purpose"
  OpReflect -> "reflect"
  OpConstrain -> "constrain"
  OpRepair -> "repair"
  OpClarify -> "clarify"
  OpDeepen -> "deepen"
  OpNextStep -> "next_step"
