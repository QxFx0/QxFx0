{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Output-shaping enums and textual codecs for rendered decisions. -}
module QxFx0.Types.Decision.Enums.Render where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , Value(..)
  )
import Data.Text (Text)
import GHC.Generics (Generic)
import QxFx0.Types.Decision.Enums.Support (parseTextEnum, withTextEnum)

data RenderStyle
  = StyleFormal
  | StyleWarm
  | StyleDirect
  | StylePoetic
  | StyleClinical
  | StyleCautious
  | StyleRecovery
  | StyleStandard
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

renderStyleText :: RenderStyle -> Text
renderStyleText StyleFormal = "formal"
renderStyleText StyleWarm = "warm"
renderStyleText StyleDirect = "direct"
renderStyleText StylePoetic = "poetic"
renderStyleText StyleClinical = "clinical"
renderStyleText StyleCautious = "cautious"
renderStyleText StyleRecovery = "recovery"
renderStyleText StyleStandard = "standard"

parseRenderStyle :: Text -> RenderStyle
parseRenderStyle = parseTextEnum StyleStandard
  [ ("formal", StyleFormal)
  , ("warm", StyleWarm)
  , ("direct", StyleDirect)
  , ("poetic", StylePoetic)
  , ("clinical", StyleClinical)
  , ("cautious", StyleCautious)
  , ("recovery", StyleRecovery)
  , ("standard", StyleStandard)
  ]

instance ToJSON RenderStyle where
  toJSON = String . renderStyleText

instance FromJSON RenderStyle where
  parseJSON = withTextEnum "RenderStyle" parseRenderStyle

data DialogueOutputMode
  = DialogueOutput
  | SemanticIntrospectionOutput
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

dialogueOutputModeText :: DialogueOutputMode -> Text
dialogueOutputModeText DialogueOutput = "dialogue"
dialogueOutputModeText SemanticIntrospectionOutput = "semantic"

parseDialogueOutputMode :: Text -> DialogueOutputMode
parseDialogueOutputMode = parseTextEnum DialogueOutput
  [ ("semantic", SemanticIntrospectionOutput)
  , ("dialogue", DialogueOutput)
  ]

instance ToJSON DialogueOutputMode where
  toJSON = String . dialogueOutputModeText

instance FromJSON DialogueOutputMode where
  parseJSON = withTextEnum "DialogueOutputMode" parseDialogueOutputMode

data DominantChannel
  = ChannelContact
  | ChannelRepair
  | ChannelAnchor
  | ChannelClarify
  | ChannelDefine
  | ChannelReflect
  | ChannelGround
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

dominantChannelText :: DominantChannel -> Text
dominantChannelText ChannelContact = "contact"
dominantChannelText ChannelRepair = "repair"
dominantChannelText ChannelAnchor = "anchor"
dominantChannelText ChannelClarify = "clarify"
dominantChannelText ChannelDefine = "define"
dominantChannelText ChannelReflect = "reflect"
dominantChannelText ChannelGround = "ground"

parseDominantChannel :: Text -> DominantChannel
parseDominantChannel = parseTextEnum ChannelGround
  [ ("contact", ChannelContact)
  , ("repair", ChannelRepair)
  , ("anchor", ChannelAnchor)
  , ("clarify", ChannelClarify)
  , ("define", ChannelDefine)
  , ("reflect", ChannelReflect)
  , ("ground", ChannelGround)
  ]

instance ToJSON DominantChannel where
  toJSON = String . dominantChannelText

instance FromJSON DominantChannel where
  parseJSON = withTextEnum "DominantChannel" parseDominantChannel

data EmotionalTone
  = ToneDistress
  | ToneHopeful
  | ToneCurious
  | ToneConfrontational
  | ToneNeutral
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

emotionalToneText :: EmotionalTone -> Text
emotionalToneText ToneDistress = "distress"
emotionalToneText ToneHopeful = "hopeful"
emotionalToneText ToneCurious = "curious"
emotionalToneText ToneConfrontational = "confrontational"
emotionalToneText ToneNeutral = "neutral"

instance ToJSON EmotionalTone where
  toJSON = String . emotionalToneText

instance FromJSON EmotionalTone where
  parseJSON = withTextEnum "EmotionalTone" (parseTextEnum ToneNeutral
    [ ("distress", ToneDistress)
    , ("hopeful", ToneHopeful)
    , ("curious", ToneCurious)
    , ("confrontational", ToneConfrontational)
    , ("neutral", ToneNeutral)
    ])
