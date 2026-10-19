{-# LANGUAGE OverloadedStrings #-}

{-| Concurrent resolution of prepare-stage effects through `PipelineIO`. -}
module QxFx0.Core.TurnPipeline.Prepare.Resolve
  ( resolvePrepareEffects
  ) where

import Control.Concurrent.Async (forConcurrently)
import QxFx0.Core.ConsciousnessLoop (initialLoop)
import QxFx0.Core.Intuition
  ( defaultIntuitiveState
  , effectivePosterior
  )
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , scheduleTurnEffects
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.EffectLabel (PipelineEffectLabel(..))
import QxFx0.Core.TurnPipeline.Effects
  ( PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , PrepareStatic(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Prepare.Types
  ( PrepareEffectResults(..)
  , PrepareTimeline(..)
  , TimedResult(..)
  )
import QxFx0.Semantic.Embedding
  ( EmbeddingResult(..)
  , EmbeddingSource(..)
  )
import QxFx0.Types
  ( NixGuardStatus(..)
  )

import Control.Exception (evaluate)
import Data.Maybe (fromMaybe)
import Data.Time.Clock (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)

resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> IO PrepareEffectResults
resolvePrepareEffects pio effectPlan = do
  let t0 = pepCapturedCurrentTime effectPlan
  -- Audit 2026-10-16 п.14: the prepare timeline used to stamp every
  -- window as t0/t0 — zero durations for all five effect phases. Measure
  -- the real windows instead, anchored at the turn's captured time t0
  -- (production t0 arrives through 'TurnReqCurrentTime'; tests fix it),
  -- so the timeline keeps the turn's single clock source while the
  -- durations become real.
  base <- getCurrentTime
  _ <- evaluate (pepStatic effectPlan)
  staticDone <- getCurrentTime
  let anchored stamp = addUTCTime (diffUTCTime stamp base) t0
      tStatic1 = anchored staticDone
      requestPairs :: [(PipelineEffectLabel, Maybe TurnEffectRequest)]
      requestPairs =
        [ (PelEmbedding, prepareRequestToTurnEffect (pepEmbeddingRequest effectPlan))
        , (PelNix, prepareRequestToTurnEffect (pepNixGuardRequest effectPlan))
        , (PelConsciousness, prepareRequestToTurnEffect (pepConsciousnessRequest effectPlan))
        , (PelIntuition, prepareRequestToTurnEffect (pepIntuitionRequest effectPlan))
        , (PelApiHealth, prepareRequestToTurnEffect (pepApiHealthRequest effectPlan))
        ]
      scheduledPairs :: [(PipelineEffectLabel, TurnEffectRequest)]
      scheduledPairs =
        scheduleTurnEffects pio (psConatusEnergy (pepStatic effectPlan))
          [ (label, request)
          | (label, Just request) <- requestPairs
          ]
  resolved <- forConcurrently scheduledPairs $ \(label, turnRequest) -> do
    started <- getCurrentTime
    result <- resolveTurnEffect pio turnRequest
    ended <- getCurrentTime
    pure (label, result, started, ended)
  let results = [ (label, result) | (label, result, _, _) <- resolved ]
      timing label =
        case [ (anchored started, anchored ended)
             | (l, _, started, ended) <- resolved
             , l == label
             ] of
          (window : _) -> window
          []            -> (t0, t0)
  -- Prepare-stage missing or unexpected effect results are intentionally
  -- classified as degraded continuation rather than fail-closed termination:
  -- local embedding, nix-blocked, default intuition/consciousness, and
  -- apiHealthy=False keep the turn moving while reducing epistemic strength.
  let embeddingResult =
        fromMaybe fallbackEmbeddingResult $ do
          TurnResEmbedding value <- lookup PelEmbedding (filter (isEmbeddingResult . snd) results)
          Just value
      nixStatus =
        fromMaybe (Blocked "nix_guard_missing_request") $ do
          TurnResNixGuard value <- lookup PelNix (filter (isNixResult . snd) results)
          Just value
      consciousnessResult =
        fromMaybe (initialLoop, Nothing, Nothing) $ do
          TurnResConsciousness loop narrative fragment <- lookup PelConsciousness (filter (isConsciousnessResult . snd) results)
          Just (loop, narrative, fragment)
      intuitionResult =
        fromMaybe (Nothing, defaultPosterior, defaultIntuitiveState) $ do
          TurnResIntuition flash posterior state <- lookup PelIntuition (filter (isIntuitionResult . snd) results)
          Just (flash, posterior, state)
      apiHealthy =
        fromMaybe False $ do
          TurnResApiHealth value <- lookup PelApiHealth (filter (isApiHealthResult . snd) results)
          Just value
      (tEmbStart, tEmbEnd) = timing PelEmbedding
      (tNixStart, tNixEnd) = timing PelNix
      (tConsciousnessStart, tConsciousnessEnd) = timing PelConsciousness
      (tIntuitionStart, tIntuitionEnd) = timing PelIntuition
      (tApiHealthStart, tApiHealthEnd) = timing PelApiHealth
      timedEmb = TimedResult tEmbStart tEmbEnd embeddingResult
      timedNix = TimedResult tNixStart tNixEnd nixStatus
      timedConsciousness = TimedResult tConsciousnessStart tConsciousnessEnd consciousnessResult
      timedIntuition = TimedResult tIntuitionStart tIntuitionEnd intuitionResult
      timedApiHealth = TimedResult tApiHealthStart tApiHealthEnd apiHealthy
      (consciousLoop', currentNarrative, narrativeFragment') = consciousnessResult
      (mFlash, intuitPosterior, intuitionState) = intuitionResult
  pure PrepareEffectResults
    { perTimeline = PrepareTimeline
        { ptlStartTime = t0
        , ptlPrepareStaticDone = tStatic1
        , ptlEmbeddingStart = trStarted timedEmb
        , ptlEmbeddingDone = trEnded timedEmb
        , ptlNixStart = trStarted timedNix
        , ptlNixDone = trEnded timedNix
        , ptlConsciousnessStart = trStarted timedConsciousness
        , ptlConsciousnessDone = trEnded timedConsciousness
        , ptlIntuitionStart = trStarted timedIntuition
        , ptlIntuitionDone = trEnded timedIntuition
        , ptlApiHealthStart = trStarted timedApiHealth
        , ptlApiHealthDone = trEnded timedApiHealth
        }
    , perTurnCurrentTime = t0
    , perEmbeddingResult = trValue timedEmb
    , perNixStatus = trValue timedNix
    , perConsciousLoop = consciousLoop'
    , perCurrentNarrative = currentNarrative
    , perNarrativeFragment = narrativeFragment'
    , perFlash = mFlash
    , perIntuitPosterior = intuitPosterior
    , perIntuitionState = intuitionState
    , perApiHealthy = trValue timedApiHealth
    }

prepareRequestToTurnEffect :: PrepareEffectRequest -> Maybe TurnEffectRequest
prepareRequestToTurnEffect request =
  case request of
    PrepareReqEmbedding inputText ->
      Just (TurnReqEmbedding inputText)
    PrepareReqNixGuard concept currentLoad atomLoad ->
      Just (TurnReqNixGuard concept currentLoad atomLoad)
    PrepareReqConsciousness semanticInput humanTheta resonance conatusEnergy salienceWeights ->
      Just (TurnReqConsciousness semanticInput humanTheta resonance conatusEnergy salienceWeights)
    PrepareReqIntuition inputText resonance tension turnNumber conatusEnergy salienceWeights semanticConfig ->
      Just (TurnReqIntuition inputText resonance tension turnNumber conatusEnergy salienceWeights semanticConfig)
    PrepareReqApiHealth ->
      Just TurnReqApiHealth

defaultPosterior :: Double
defaultPosterior = effectivePosterior defaultIntuitiveState

fallbackEmbeddingResult :: EmbeddingResult
fallbackEmbeddingResult = EmbeddingResult { erEmbedding = mempty, erSource = EmbeddingLocalImplicit }

isEmbeddingResult :: TurnEffectResult -> Bool
isEmbeddingResult result = case result of
  TurnResEmbedding _ -> True
  _ -> False

isNixResult :: TurnEffectResult -> Bool
isNixResult result = case result of
  TurnResNixGuard _ -> True
  _ -> False

isConsciousnessResult :: TurnEffectResult -> Bool
isConsciousnessResult result = case result of
  TurnResConsciousness _ _ _ -> True
  _ -> False

isIntuitionResult :: TurnEffectResult -> Bool
isIntuitionResult result = case result of
  TurnResIntuition _ _ _ -> True
  _ -> False

isApiHealthResult :: TurnEffectResult -> Bool
isApiHealthResult result = case result of
  TurnResApiHealth _ -> True
  _ -> False
