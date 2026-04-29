{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Prepare-stage construction of `TurnInput` and `TurnSignals` from resolved effects. -}
module QxFx0.Core.TurnPipeline.Prepare.Build
  ( buildTurnInput
  , buildTurnSignals
  ) where

import QxFx0.Core.Observability
import QxFx0.Core.TurnPipeline.Effects
  ( PrepareEffectPlan(..)
  , PrepareStatic(..)
  )
import QxFx0.Core.TurnPipeline.Prepare.Types
  ( PrepareEffectResults(..)
  , PrepareTimeline(..)
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.Semantic.Embedding
  ( EmbeddingQuality(..)
  , cosineSimilarity
  , erEmbedding
  , erSource
  , embeddingSourceQuality
  , embeddingSourceText
  )
import QxFx0.Types

import Data.Text (Text)

buildTurnInput :: SystemState -> Text -> Text -> PrepareEffectPlan -> PrepareEffectResults -> TurnInput
buildTurnInput ss requestId sessionId effectPlan effectResults =
  let prepareStatic = pepStatic effectPlan
      embResult = perEmbeddingResult effectResults
      emb = erEmbedding embResult
      embQuality = embeddingSourceQuality (erSource embResult)
      embSimilarity =
        case (embQuality, ssLastEmbedding ss) of
          (EmbeddingQualityModeled, Just prevEmb) -> realToFrac (cosineSimilarity emb prevEmb)
          _ -> 0.0
      timeline = perTimeline effectResults
      !metrics0 = emptyTurnMetrics requestId sessionId
      !metrics1 =
        addPhase
          (recordPhase "prepare_static" (ptlStartTime timeline) (ptlPrepareStaticDone timeline))
          metrics0
      !metrics2 =
        (addPhase
          (recordPhase "embedding" (ptlEmbeddingStart timeline) (ptlEmbeddingDone timeline))
          metrics1)
            { tmEmbeddingSource = embeddingSourceText (erSource embResult) }
      !metrics3 =
        addPhase
          (recordPhase "nix_check" (ptlNixStart timeline) (ptlNixDone timeline))
          metrics2
      !metrics4 =
        addPhase
          (recordPhase "consciousness" (ptlConsciousnessStart timeline) (ptlConsciousnessDone timeline))
          metrics3
      !metrics5 =
        addPhase
          (recordPhase "intuition" (ptlIntuitionStart timeline) (ptlIntuitionDone timeline))
          metrics4
      !metrics6 =
        addPhase
          (recordPhase "api_health" (ptlApiHealthStart timeline) (ptlApiHealthDone timeline))
          metrics5
      nixStatus = perNixStatus effectResults
      nixAvailable = case nixStatus of Unavailable _ -> False; _ -> True
      isNixBlocked = case nixStatus of Blocked _ -> True; _ -> False
  in TurnInput
      { tiStartTime = ptlStartTime timeline
      , tiEmbedding = emb
      , tiEmbeddingSource = erSource embResult
      , tiEmbeddingQuality = embQuality
      , tiEmbSimilarity = embSimilarity
      , tiAtomSet = psAtomSet prepareStatic
      , tiNewTrace = psNewTrace prepareStatic
      , tiNextUserState = psNextUserState prepareStatic
      , tiRecommendedFamily = psRecommendedFamily prepareStatic
      , tiFrame = psFrame prepareStatic
      , tiNixStatus = nixStatus
      , tiNixAvailable = nixAvailable
      , tiIsNixBlocked = isNixBlocked
      , tiConceptToCheck = psConceptToCheck prepareStatic
      , tiBestTopic = psBestTopic prepareStatic
      , tiMetrics = metrics6
      }

buildTurnSignals :: PrepareEffectResults -> TurnSignals
buildTurnSignals effectResults =
  TurnSignals
    { tsConsciousLoop' = perConsciousLoop effectResults
    , tsCurrentNarrative = perCurrentNarrative effectResults
    , tsNarrativeFragment = perNarrativeFragment effectResults
    , tsFlash = perFlash effectResults
    , tsIntuitPosterior = perIntuitPosterior effectResults
    , tsIntuitionState = perIntuitionState effectResults
    , tsApiHealthy = perApiHealthy effectResults
    }
