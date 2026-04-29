{-# LANGUAGE StrictData #-}

{-| Prepared effect outputs and per-stage timestamps for prepare pipeline observability. -}
module QxFx0.Core.TurnPipeline.Prepare.Types
  ( PrepareTimeline(..)
  , PrepareEffectResults(..)
  , TimedResult(..)
  ) where

import QxFx0.Types
import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop)
import QxFx0.Core.Intuition (IntuitiveFlash)
import QxFx0.Core.Semantic.Embedding (EmbeddingResult)

import Data.Text (Text)
import Data.Time.Clock (UTCTime)

data PrepareTimeline = PrepareTimeline
  { ptlStartTime :: !UTCTime
  , ptlPrepareStaticDone :: !UTCTime
  , ptlEmbeddingStart :: !UTCTime
  , ptlEmbeddingDone :: !UTCTime
  , ptlNixStart :: !UTCTime
  , ptlNixDone :: !UTCTime
  , ptlConsciousnessStart :: !UTCTime
  , ptlConsciousnessDone :: !UTCTime
  , ptlIntuitionStart :: !UTCTime
  , ptlIntuitionDone :: !UTCTime
  , ptlApiHealthStart :: !UTCTime
  , ptlApiHealthDone :: !UTCTime
  }

data PrepareEffectResults = PrepareEffectResults
  { perTimeline :: !PrepareTimeline
  , perEmbeddingResult :: !EmbeddingResult
  , perNixStatus :: !NixGuardStatus
  , perConsciousLoop :: !ConsciousnessLoop
  , perCurrentNarrative :: !(Maybe ConsciousnessNarrative)
  , perNarrativeFragment :: !(Maybe Text)
  , perFlash :: !(Maybe IntuitiveFlash)
  , perIntuitPosterior :: !Double
  , perIntuitionState :: !IntuitiveState
  , perApiHealthy :: !Bool
  }

data TimedResult a = TimedResult
  { trStarted :: !UTCTime
  , trEnded :: !UTCTime
  , trValue :: !a
  }
