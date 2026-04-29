{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Governance and gating enums for decision legitimacy and planner state. -}
module QxFx0.Types.Decision.Enums.Governance where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , Value(..)
  )
import Data.Text (Text)
import GHC.Generics (Generic)
import QxFx0.Types.Decision.Enums.Support (parseTextEnum, withTextEnum)

data ShadowStatus
  = ShadowUnavailable
  | ShadowMatch
  | ShadowDiverged
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

shadowStatusText :: ShadowStatus -> Text
shadowStatusText ShadowUnavailable = "unavailable"
shadowStatusText ShadowMatch = "match"
shadowStatusText ShadowDiverged = "diverged"

instance ToJSON ShadowStatus where
  toJSON = String . shadowStatusText

instance FromJSON ShadowStatus where
  parseJSON = withTextEnum "ShadowStatus" (parseTextEnum ShadowUnavailable
    [ ("unavailable", ShadowUnavailable)
    , ("match", ShadowMatch)
    , ("diverged", ShadowDiverged)
    ])

data LegitimacyReason
  = ReasonShadowDivergence
  | ReasonShadowUnavailable
  | ReasonLowParserConfidence
  | ReasonOk
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

legitimacyReasonText :: LegitimacyReason -> Text
legitimacyReasonText ReasonShadowDivergence = "shadow_divergence"
legitimacyReasonText ReasonShadowUnavailable = "shadow_unavailable"
legitimacyReasonText ReasonLowParserConfidence = "low_parser_confidence"
legitimacyReasonText ReasonOk = "ok"

instance ToJSON LegitimacyReason where
  toJSON = String . legitimacyReasonText

instance FromJSON LegitimacyReason where
  parseJSON = withTextEnum "LegitimacyReason" (parseTextEnum ReasonOk
    [ ("shadow_divergence", ReasonShadowDivergence)
    , ("shadow_unavailable", ReasonShadowUnavailable)
    , ("low_parser_confidence", ReasonLowParserConfidence)
    , ("ok", ReasonOk)
    ])

data DecisionDisposition
  = DispositionPermit
  | DispositionRepair
  | DispositionDeny
  | DispositionAdvisory
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

decisionDispositionText :: DecisionDisposition -> Text
decisionDispositionText DispositionPermit = "permit"
decisionDispositionText DispositionRepair = "repair"
decisionDispositionText DispositionDeny = "deny"
decisionDispositionText DispositionAdvisory = "advisory"

instance ToJSON DecisionDisposition where
  toJSON = String . decisionDispositionText

instance FromJSON DecisionDisposition where
  parseJSON = withTextEnum "DecisionDisposition" (parseTextEnum DispositionAdvisory
    [ ("permit", DispositionPermit)
    , ("repair", DispositionRepair)
    , ("deny", DispositionDeny)
    , ("advisory", DispositionAdvisory)
    ])

data PlannerMode
  = PrincipledPlanner
  | DefaultPlanner
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

plannerModeText :: PlannerMode -> Text
plannerModeText PrincipledPlanner = "principled"
plannerModeText DefaultPlanner = "default"

instance ToJSON PlannerMode where
  toJSON = String . plannerModeText

instance FromJSON PlannerMode where
  parseJSON = withTextEnum "PlannerMode" (parseTextEnum DefaultPlanner
    [ ("principled", PrincipledPlanner)
    , ("default", DefaultPlanner)
    ])

data ParserMode
  = ParserFrameV1
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

parserModeText :: ParserMode -> Text
parserModeText ParserFrameV1 = "frame_v1"

instance ToJSON ParserMode where
  toJSON = String . parserModeText

instance FromJSON ParserMode where
  parseJSON = withTextEnum "ParserMode" (parseTextEnum ParserFrameV1
    [("frame_v1", ParserFrameV1)])
