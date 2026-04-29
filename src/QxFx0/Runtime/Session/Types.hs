{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Public session types and output-mode codecs for the runtime shell. -}
module QxFx0.Runtime.Session.Types
  ( RuntimeOutputMode(..)
  , Session(..)
  , StateOrigin(..)
  , renderRuntimeOutputMode
  , runtimeToDialogueMode
  , dialogueToRuntimeMode
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), withText)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Resources (ReadinessMode)
import QxFx0.Runtime.Context (RuntimeContext)
import QxFx0.Types.Decision (DialogueOutputMode(..))
import QxFx0.Types.State (SystemState)

data RuntimeOutputMode
  = DialogueMode
  | SemanticIntrospectionMode
  deriving stock (Eq, Show)

data StateOrigin
  = FreshOrigin
  | RestoredOrigin
  | RecoveredCorruptOrigin
  deriving stock (Eq, Show)

instance ToJSON StateOrigin where
  toJSON FreshOrigin = String "fresh"
  toJSON RestoredOrigin = String "restored"
  toJSON RecoveredCorruptOrigin = String "recovered_corrupt"

instance FromJSON StateOrigin where
  parseJSON = withText "StateOrigin" $ \t ->
    case T.toLower (T.strip t) of
      "fresh" -> pure FreshOrigin
      "restored" -> pure RestoredOrigin
      "recovered_corrupt" -> pure RecoveredCorruptOrigin
      _ -> fail ("Unknown StateOrigin: " <> T.unpack t)

data Session = Session
  { sessSystemState :: !SystemState
  , sessOutputMode :: !RuntimeOutputMode
  , sessSessionId :: !Text
  , sessDbPath :: !FilePath
  , sessStateOrigin :: !StateOrigin
  , sessReadinessMode :: !ReadinessMode
  , sessRuntime :: !RuntimeContext
  }

renderRuntimeOutputMode :: RuntimeOutputMode -> Text
renderRuntimeOutputMode DialogueMode = "dialogue"
renderRuntimeOutputMode SemanticIntrospectionMode = "semantic"

runtimeToDialogueMode :: RuntimeOutputMode -> DialogueOutputMode
runtimeToDialogueMode DialogueMode = DialogueOutput
runtimeToDialogueMode SemanticIntrospectionMode = SemanticIntrospectionOutput

dialogueToRuntimeMode :: DialogueOutputMode -> RuntimeOutputMode
dialogueToRuntimeMode DialogueOutput = DialogueMode
dialogueToRuntimeMode SemanticIntrospectionOutput = SemanticIntrospectionMode
