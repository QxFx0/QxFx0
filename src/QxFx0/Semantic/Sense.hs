{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Sense
  ( SemanticNodeId(..)
  , FamilyId(..)
  , SenseAxis(..)
  , SensePolarity(..)
  , SenseOperator(..)
  , SenseVector(..)
  , ResponseSensePlan(..)
  , emptySenseVector
  , emptyResponseSensePlan
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
  | AxBoundary
  | AxAction
  | AxState
  | AxKnowledge
  | AxSelf
  | AxOther
  | AxRepair
  | AxComparison
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
  | OpConstrain
  | OpRepair
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

renderSenseAxis :: SenseAxis -> Text
renderSenseAxis axis = case axis of
  AxIdentity -> "identity"
  AxCause -> "cause"
  AxBoundary -> "boundary"
  AxAction -> "action"
  AxState -> "state"
  AxKnowledge -> "knowledge"
  AxSelf -> "self"
  AxOther -> "other"
  AxRepair -> "repair"
  AxComparison -> "comparison"

renderSenseOperator :: SenseOperator -> Text
renderSenseOperator op = case op of
  OpDefine -> "define"
  OpGround -> "ground"
  OpDistinguish -> "distinguish"
  OpExplainCause -> "explain_cause"
  OpConstrain -> "constrain"
  OpRepair -> "repair"
  OpNextStep -> "next_step"
