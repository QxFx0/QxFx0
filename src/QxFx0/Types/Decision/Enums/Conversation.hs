{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Conversational and semantic-plan enums used by decision routing. -}
module QxFx0.Types.Decision.Enums.Conversation where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data SpeechAct
  = Ask | Assert | Confront | Offer | MakeContact | Reflect
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON SpeechAct where toJSON = genericToJSON defaultOptions
instance FromJSON SpeechAct where parseJSON = genericParseJSON defaultOptions

data SemanticRelation
  = SRGround | SRDefine | SRDistinguish | SRReflect | SRDescribe
  | SRPurpose | SRHypothesis | SRRepair | SRContact | SRAnchor
  | SRClarify | SRDeepen | SRConfront | SRNextStep
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON SemanticRelation where toJSON = genericToJSON defaultOptions
instance FromJSON SemanticRelation where parseJSON = genericParseJSON defaultOptions

data EpistemicStatus
  = Known !Double
  | Probable !Double
  | Uncertain !Double
  | Unknown !Double
  | Speculative !Double
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

epistemicConfidence :: EpistemicStatus -> Double
epistemicConfidence (Known confidence) = confidence
epistemicConfidence (Probable confidence) = confidence
epistemicConfidence (Uncertain confidence) = confidence
epistemicConfidence (Unknown confidence) = confidence
epistemicConfidence (Speculative confidence) = confidence

instance ToJSON EpistemicStatus where
  toJSON (Known confidence) = object ["tag" .= ("Known" :: Text), "confidence" .= confidence]
  toJSON (Probable confidence) = object ["tag" .= ("Probable" :: Text), "confidence" .= confidence]
  toJSON (Uncertain confidence) = object ["tag" .= ("Uncertain" :: Text), "confidence" .= confidence]
  toJSON (Unknown confidence) = object ["tag" .= ("Unknown" :: Text), "confidence" .= confidence]
  toJSON (Speculative confidence) = object ["tag" .= ("Speculative" :: Text), "confidence" .= confidence]

instance FromJSON EpistemicStatus where
  parseJSON = withObject "EpistemicStatus" $ \objectValue -> do
    tag <- objectValue .: "tag"
    confidence <- objectValue .: "confidence"
    case tag :: Text of
      "Known" -> pure (Known confidence)
      "Probable" -> pure (Probable confidence)
      "Uncertain" -> pure (Uncertain confidence)
      "Unknown" -> pure (Unknown confidence)
      "Speculative" -> pure (Speculative confidence)
      _ -> fail ("unknown EpistemicStatus: " ++ T.unpack tag)

data StanceMarker
  = Commit | Observe | Explore | HoldBack
  | Firm | Honest | Tentative | Curated
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON StanceMarker where toJSON = genericToJSON defaultOptions
instance FromJSON StanceMarker where parseJSON = genericParseJSON defaultOptions

data AnswerStrategy
  = DirectThenGround | DefineThenUnfold | ContrastThenDistinguish
  | ReflectThenMirror | DescribeThenSketch | PurposeThenTeleology
  | HypothesizeThenTest | RepairThenRestore | ContactThenBridge
  | AnchorThenStabilize | ClarifyThenDisambiguate | DeepenThenProbe
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON AnswerStrategy where toJSON = genericToJSON defaultOptions
instance FromJSON AnswerStrategy where parseJSON = genericParseJSON defaultOptions

data ContentMove
  = MoveGroundKnown | MoveGroundBasis | MoveShiftFromLabel
  | MoveDefineFrame | MoveStateDefinition | MoveShowContrast
  | MoveStateBoundary | MoveReflectMirror | MoveReflectResonate
  | MoveDescribeSketch | MovePurposeTeleology | MoveHypothesizeTest
  | MoveAffirmPresence | MoveAcknowledgeRupture | MoveRepairBridge
  | MoveContactBridge | MoveContactReach | MoveAnchorStabilize
  | MoveClarifyDisambiguate | MoveDeepenProbe | MoveConfrontChallenge
  | MoveNextStep
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON ContentMove where toJSON = genericToJSON defaultOptions
instance FromJSON ContentMove where parseJSON = genericParseJSON defaultOptions
