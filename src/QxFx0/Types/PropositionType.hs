{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

{-| PropositionType — standalone sum type for proposition classification.

This module is intentionally low-dependency to avoid import cycles.
It lives in QxFx0.Types so that both Semantic and Decision modules
can import it without creating circular dependencies.
-}
module QxFx0.Types.PropositionType
  ( PropositionType(..)
  , propositionTypeText
  , propositionTypeFromText
  ) where

import Control.DeepSeq (NFData)
import Data.Text (Text)
import GHC.Generics (Generic)
import qualified Data.Text as T
import Text.Read (readMaybe)

-- | Proposition type classification for user utterances.
-- Each type maps to a canonical move family and has specific detection logic.
data PropositionType
  = DefinitionalQ
  | DistinctionQ
  | GroundQ
  | ReflectiveQ
  | SelfDescQ
  | PurposeQ
  | HypotheticalQ
  | RepairSignal
  | ContactSignal
  | AnchorSignal
  | ClarifyQ
  | DeepenQ
  | ConfrontQ
  | NextStepQ
  | PlainAssert
  | AffectiveQ
  | EpistemicQ
  | RequestQ
  | EvaluationQ
  | NarrativeQ
  | OperationalStatusQ
  | OperationalCauseQ
  | SystemLogicQ
  | SelfKnowledgeQ
  | DialogueInvitationQ
  | ConceptKnowledgeQ
  | WorldCauseQ
  | LocationFormationQ
  | SelfStateQ
  | ComparisonPlausibilityQ
  | MisunderstandingReport
  | GenerativePrompt
  | ContemplativeTopic
  | ExploratoryPrompt
    -- ^ Phase 9: system-initiated exploratory learning prompt.
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- | Convert a PropositionType to its Text representation.
propositionTypeText :: PropositionType -> Text
propositionTypeText = T.pack . show

-- | Parse a PropositionType from its Show representation.
propositionTypeFromText :: Text -> Maybe PropositionType
propositionTypeFromText = readMaybe . T.unpack
