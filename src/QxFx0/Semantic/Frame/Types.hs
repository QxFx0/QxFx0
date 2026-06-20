{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Frame.Types
Description : Semantic frame types for compositional response generation.

Semantic frames describe /what to say/ (content structure) rather than
/which template to use/ (render structure). They bridge the gap between
intent classification and text generation.

Each frame carries enough semantic information for a compositional
generator to produce text without hardcoded templates.
-}
module QxFx0.Semantic.Frame.Types
  ( SemanticFrame(..)
  , FrameDepth(..)
  , FrameStrength(..)
  , FrameAuthority(..)
  , FrameScope(..)
  , frameTypeText
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)

-- | Semantic frame: what content to generate, structurally.
--
-- Frames carry semantic fields that a compositional generator uses
-- to produce text. Unlike templates, frames are not tied to specific
-- surface forms — they describe the /shape/ of the response content.
data SemanticFrame
  = DefinitionFrame
      { dfTopic :: !Text
      , dfScope :: !FrameScope
      , dfAuthority :: !FrameAuthority
      }
    -- ^ "X — это Y": definition of a concept.
  | DistinctionFrame
      { distLeft :: !Text
      , distRight :: !Text
      , distCriteria :: ![Text]
      }
    -- ^ "Различим A и B по критерию C": contrastive distinction.
  | ChallengeFrame
      { chTarget :: !Text
      , chBasis :: !Text
      , chStrength :: !FrameStrength
      , chRawText :: !Text
      }
    -- ^ "Возражу: ... противоречит ...": response to challenge.
  | GroundFrame
      { gfTopic :: !Text
      , gfDepth :: !FrameDepth
      }
    -- ^ "Держу это как опору...": grounding/concretization.
  | RepairFrame
    -- ^ "Вижу сигнал перегруза...": recovery response.
  | ContactFrame
      { cfGreeting :: !Text
      }
    -- ^ "Привет, как дела?": greeting/relationship.
  | ReflectFrame
      { rfTopic :: !Text
      }
    -- ^ "Когда я думаю о X...": reflective response.
  | LearnFrame
      { lfTopic :: !Text
      , lfDepth :: !FrameDepth
      }
    -- ^ "X — это...": learning/explanation response.
  | HelpFrame
      { hfTask :: !Text
      }
    -- ^ "Помогу с X: ...": help/assistance response.
  | PurposeFrame
      { pfTopic :: !Text
      }
    -- ^ "Функция X проявляется через...": purpose explanation.
  | WorldCauseFrame
      { wcTopic :: !Text
      }
    -- ^ "Причина X в...": world causation explanation.
  | DeepenFrame
      { dpTopic :: !Text
      }
    -- ^ "Углубимся в X...": deepening response.
  | NextStepFrame
    -- ^ "Следующий шаг: ...": actionable next step.
  | ExploratoryFrame
    -- ^ "Если представить...": hypothetical exploration.
  | OperationalFrame
    -- ^ "Я работаю...": operational status.
  | SelfReferenceFrame
    -- ^ "О себе я знаю...": self-description.
  | GenericFrame
      { gfContent :: !Text
      }
    -- ^ Fallback: pass-through content.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Depth of response content.
data FrameDepth
  = Shallow     -- ^ One sentence, high-level
  | Detailed    -- ^ Multiple sentences, specific examples
  deriving stock (Eq, Show, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Strength of challenge/response.
data FrameStrength
  = Soft    -- ^ "Понимаю, но..."
  | Firm    -- ^ "Возражу: ..."
  deriving stock (Eq, Show, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Epistemic authority of the claim.
data FrameAuthority
  = Known     -- ^ "Известно, что..."
  | Probable  -- ^ "Вероятно, ..."
  | Uncertain -- ^ "Мне кажется..."
  deriving stock (Eq, Show, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Scope of the definition/claim.
data FrameScope
  = GeneralScope     -- ^ "В общем смысле..."
  | SpecificScope    -- ^ "В контексте X..."
  | DomainScope Text -- ^ "В области Y..."
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Render frame type to stable text tag for traces.
frameTypeText :: SemanticFrame -> Text
frameTypeText DefinitionFrame{}    = "definition"
frameTypeText DistinctionFrame{}   = "distinction"
frameTypeText ChallengeFrame{}     = "challenge"
frameTypeText GroundFrame{}        = "ground"
frameTypeText RepairFrame          = "repair"
frameTypeText ContactFrame{}       = "contact"
frameTypeText ReflectFrame{}       = "reflect"
frameTypeText LearnFrame{}         = "learn"
frameTypeText HelpFrame{}          = "help"
frameTypeText PurposeFrame{}       = "purpose"
frameTypeText WorldCauseFrame{}    = "world_cause"
frameTypeText DeepenFrame{}        = "deepen"
frameTypeText NextStepFrame        = "next_step"
frameTypeText ExploratoryFrame     = "exploratory"
frameTypeText OperationalFrame     = "operational"
frameTypeText SelfReferenceFrame   = "self_reference"
frameTypeText GenericFrame{}       = "generic"
