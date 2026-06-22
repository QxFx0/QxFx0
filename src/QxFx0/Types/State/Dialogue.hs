{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Dialogue-facing persisted state: turn history, routing memory, and active scene. -}
module QxFx0.Types.State.Dialogue
  ( DialogueState(..)
  , emptyDialogueState
  , appendHistoryBounded
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Config.State
  ( defaultNeutralUserState
  , emptyDialogueActiveScene
  )
import QxFx0.Types.Domain
  ( CanonicalMoveFamily(..)
  , Embedding
  , IllocutionaryForce(..)
  , SemanticLayer(..)
  , SemanticScene
  , UserState
  )
import QxFx0.Semantic.DialogueContext (DialogueContext, emptyContext)

data DialogueState = DialogueState
  { dsHistory :: !(Seq Text)
  , dsRawInputHistory :: !(Seq Text)
  , dsTurnCount :: !Int
  , dsLastTopic :: !Text
  , dsLastFamily :: !CanonicalMoveFamily
  , dsLastForce :: !IllocutionaryForce
  , dsLastLayer :: !SemanticLayer
  , dsLastEmbedding :: !(Maybe Embedding)
  , dsConsecutiveReflect :: !Int
  , dsRecentFamilies :: ![CanonicalMoveFamily]
  , dsActiveScene :: !SemanticScene
  , dsUserState :: !UserState
  , dsLastSalienceBias :: !Double
  , dsHolisticStreak :: !Int
  , dsRecentNarrativeSuccess :: ![Bool]
  , dsContext :: !DialogueContext
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON DialogueState where
  toJSON = genericToJSON defaultOptions

instance FromJSON DialogueState where
  parseJSON = genericParseJSON defaultOptions

emptyDialogueState :: DialogueState
emptyDialogueState = DialogueState
  { dsHistory = Seq.empty
  , dsRawInputHistory = Seq.empty
  , dsTurnCount = 0
  , dsLastTopic = ""
  , dsLastFamily = CMGround
  , dsLastForce = IFAssert
  , dsLastLayer = ContentLayer
  , dsLastEmbedding = Nothing
  , dsConsecutiveReflect = 0
  , dsRecentFamilies = []
  , dsActiveScene = emptyDialogueActiveScene
  , dsUserState = defaultNeutralUserState
  , dsLastSalienceBias = 0.0
  , dsHolisticStreak = 0
  , dsRecentNarrativeSuccess = []
  , dsContext = emptyContext
  }

appendHistoryBounded :: Int -> Seq Text -> Text -> Seq Text
appendHistoryBounded maxLen hist item =
  let new = hist Seq.|> item
  in if Seq.length new > maxLen then Seq.drop (Seq.length new - maxLen) new else new
