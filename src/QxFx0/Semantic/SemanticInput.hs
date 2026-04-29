{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, DeriveGeneric, DeriveAnyClass #-}
module QxFx0.Semantic.SemanticInput
  ( SemanticInput(..)
  , buildSemanticInputSimple
  ) where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Text (Text)
import Data.Aeson (ToJSON, FromJSON)

import QxFx0.Types
  ( AtomSet(..), InputPropositionFrame(..)
  , CanonicalMoveFamily(..), SemanticLayer(..), Register(..)
  )

data SemanticInput = SemanticInput
  { siRawInput          :: !Text
  , siAtomSet           :: !AtomSet
  , siPropositionFrame  :: !InputPropositionFrame
  , siRecommendedFamily :: !CanonicalMoveFamily
  , siRegister          :: !Register
  , siNeedLayer         :: !SemanticLayer
  } deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)

buildSemanticInputSimple
  :: Text -> AtomSet -> InputPropositionFrame
  -> CanonicalMoveFamily -> Register -> SemanticLayer
  -> SemanticInput
buildSemanticInputSimple raw atoms frame family reg needLayer =
  SemanticInput
    { siRawInput          = raw
    , siAtomSet           = atoms
    , siPropositionFrame  = frame
    , siRecommendedFamily = family
    , siRegister          = reg
    , siNeedLayer         = needLayer
    }
