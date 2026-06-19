{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Description : observer — Prepare-stage construction of `TurnInput` and `TurnSignals` from resolved effects. -}
module QxFx0.Core.TurnPipeline.Prepare.Build
  ( buildTurnInput
  , buildTurnSignals
  ) where

import QxFx0.Core.Observability
import QxFx0.Core.ConsciousnessLoop (computeDoubt)
import QxFx0.Core.TurnPipeline.Effects
  ( PrepareEffectPlan(..)
  , PrepareStatic(..)
  )
import QxFx0.Self.Salience (svSalience)
import QxFx0.Memory.Episodic
  ( EpisodicEvent
  , EpisodicQuery(..)
  , EpisodicStore
  , episodicRecallActive
  , retrieve
  )
import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))
import QxFx0.Core.TurnPipeline.Prepare.Types
  ( PrepareEffectResults(..)
  , PrepareTimeline(..)
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Semantic.Embedding
  ( EmbeddingQuality(..)
  , cosineSimilarity
  , erEmbedding
  , erSource
  , embeddingSourceQuality
  , embeddingSourceText
  )
import QxFx0.Types
import QxFx0.Semantic.Network (activate, contentDensityGate)

import Data.Text (Text)

-- | WP-B R-B1: construct frame-driven episodic query from current turn context.
-- Query strategy: retrieve recent episodes (last 20 turns) that might inform
-- the current response. This is a minimal implementation; more sophisticated
-- queries (ByCommitment, ByKind filtering) can be added later.
buildEpisodicQuery :: SystemState -> EpisodicQuery
buildEpisodicQuery ss =
  let currentTurn = TurnSeq (ssTurnCount ss)
      -- Query last 20 turns (episodic window is 50, we use a tighter window for relevance)
      startTurn = TurnSeq (max 0 (unTurnSeq currentTurn - 20))
  in ByTurnRange (startTurn, currentTurn)

-- | WP-B R-B1: retrieve relevant episodes if recall is active.
-- Returns empty list when flag is off or no store exists.
retrieveRelevantEpisodes :: SystemState -> [EpisodicEvent]
retrieveRelevantEpisodes ss
  | not episodicRecallActive = []
  | otherwise = case ssEpisodic ss of
      Nothing    -> []
      Just store -> retrieve (buildEpisodicQuery ss) store

buildTurnInput :: SystemState -> Text -> Text -> PrepareEffectPlan -> PrepareEffectResults -> TurnInput
buildTurnInput ss requestId sessionId effectPlan effectResults =
  let prepareStatic = pepStatic effectPlan
      retrievedEpisodes = retrieveRelevantEpisodes ss
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
      -- Phase 1: spreading activation on semantic network
      activatedNetwork =
        let network = ssSemanticNetwork ss
        in if contentDensityGate network
           then Just (activate (psBestTopic prepareStatic) network)
           else Nothing
   in TurnInput
      { tiStartTime = perTurnCurrentTime effectResults
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
      , tiConatusEnergy = psConatusEnergy prepareStatic
      , tiBlanketViolationCount = psBlanketViolationCount prepareStatic
      , tiConatusGateFired = psConatusGateFired prepareStatic
       , tiField = psField prepareStatic
       , tiFieldHeuristics = psFieldHeuristics prepareStatic
       , tiSelfVerdict = psSelfVerdict prepareStatic
        , tiSenseVector = psSenseVector prepareStatic
       , tiDialogueThread = psDialogueThread prepareStatic
       , tiDialogueCommitmentLedger = psDialogueCommitmentLedger prepareStatic
        , tiDialoguePhase = psDialoguePhase prepareStatic
        , tiTruthContractStatus = psTruthContractStatus prepareStatic
          , tiEssence = psEssence prepareStatic
          , tiGeoResult = psGeoResult prepareStatic
         , tiDoubtScore = computeDoubt (svSalience (psSelfVerdict prepareStatic))
         , tiRetrievedEpisodes = retrievedEpisodes
         , tiActivatedNetwork = activatedNetwork
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
