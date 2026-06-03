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
  , emptySenseVector
  , emptyResponseSensePlan
  , emptyMicroPlan
  , renderSenseAxis
  , renderSenseOperator
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)

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
  { mpRhetoricalMoves :: ![Text]
  , mpExplicitness :: !Double
  , mpStructureBudget :: !Int
  , mpFallbackPolicy :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

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
  , mpFallbackPolicy = "safe_degrade"
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
