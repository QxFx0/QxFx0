{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | Trace representation of a graph-wired meaning assembly.
-- Populated (not decided) per turn: selection and rendering never
-- consult these candidates — they exist so the calibration corpus
-- and the operator can see what the composer would propose.
module QxFx0.Types.Semantic.Assembly
  ( AssemblyCandidate(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

data AssemblyCandidate = AssemblyCandidate
  { acTopicA    :: !Text
  , acTopicB    :: !Text
  , acBridge    :: !Text
  , acHead      :: !(Maybe Text)
  , acRelations :: ![(Text, Text)]
  , acPathLen   :: !Int
  , acPathScore :: !Double
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
