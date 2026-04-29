{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Config.State
  ( defaultNeutralUserState
  , emptyDialogueActiveScene
  , defaultEgoTension
  , defaultEgoAgency
  , defaultEgoMission
  ) where

import Data.Text (Text)

import QxFx0.Types.Config.Domain
  ( defaultUserReadiness
  , defaultUserTone
  )
import QxFx0.Types.Domain
  ( Register(..)
  , SemanticLayer(..)
  , SemanticScene(..)
  , UserState(..)
  )

defaultEgoTension :: Double
defaultEgoTension = 0.5

defaultEgoAgency :: Double
defaultEgoAgency = 0.7

defaultEgoMission :: Text
defaultEgoMission = "Обеспечить содержательный диалог"

defaultNeutralUserState :: UserState
defaultNeutralUserState = UserState defaultUserTone ContentLayer defaultUserReadiness Neutral

emptyDialogueActiveScene :: SemanticScene
emptyDialogueActiveScene = SemanticScene 0.0 0.0 [] ""
