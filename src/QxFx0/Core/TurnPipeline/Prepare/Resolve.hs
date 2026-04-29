{-# LANGUAGE OverloadedStrings #-}

{-| Concurrent resolution of prepare-stage effects through `PipelineIO`. -}
module QxFx0.Core.TurnPipeline.Prepare.Resolve
  ( resolvePrepareEffects
  ) where

import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, initialLoop)
import QxFx0.Core.Intuition
  ( IntuitiveFlash
  , defaultIntuitiveState
  , effectivePosterior
  )
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.Effects
  ( PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Prepare.Types
  ( PrepareEffectResults(..)
  , PrepareTimeline(..)
  , TimedResult(..)
  )
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , throwQxFx0
  )
import QxFx0.Core.Semantic.Embedding
  ( EmbeddingResult(..)
  , EmbeddingSource(..)
  )
import QxFx0.Types
  ( IntuitiveState
  , NixGuardStatus(..)
  )

import Control.Concurrent.Async (Concurrently(..), runConcurrently)
import Control.Exception (evaluate)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)

resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> IO PrepareEffectResults
resolvePrepareEffects pio effectPlan = do
  t0 <- resolveEffectCurrentTime pio
  _ <- evaluate (pepStatic effectPlan)
  tStatic1 <- resolveEffectCurrentTime pio
  (timedEmb, timedNix, timedConsciousness, timedIntuition, timedApiHealth) <-
    runConcurrently $
      (,,,,)
        <$> Concurrently (timeAction pio (resolveEmbedding pio effectPlan))
        <*> Concurrently (timeAction pio (resolveNixGuard pio effectPlan))
        <*> Concurrently (timeAction pio (resolveConsciousness pio effectPlan))
        <*> Concurrently (timeAction pio (resolveIntuition pio effectPlan))
        <*> Concurrently (timeAction pio (resolveApiHealth pio effectPlan))
  let (consciousLoop', currentNarrative, narrativeFragment') = trValue timedConsciousness
      (mFlash, intuitPosterior, intuitionState) = trValue timedIntuition
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

resolveEmbedding :: PipelineIO -> PrepareEffectPlan -> IO EmbeddingResult
resolveEmbedding pio plan =
  case prepareRequestToTurnEffect (pepEmbeddingRequest plan) of
    Just request -> do
      result <- resolveTurnEffect pio request
      case result of
        TurnResEmbedding embeddingResult -> pure embeddingResult
        _ -> emptyEmbeddingResult
    Nothing ->
      emptyEmbeddingResult

resolveNixGuard :: PipelineIO -> PrepareEffectPlan -> IO NixGuardStatus
resolveNixGuard pio plan =
  case prepareRequestToTurnEffect (pepNixGuardRequest plan) of
    Just request -> do
      result <- resolveTurnEffect pio request
      case result of
        TurnResNixGuard nixStatus -> pure nixStatus
        _ -> pure (Unavailable "unexpected_prepare_nix_result")
    Nothing ->
      pure (Unavailable "unexpected_prepare_nix_request")

resolveConsciousness :: PipelineIO -> PrepareEffectPlan -> IO (ConsciousnessLoop, Maybe ConsciousnessNarrative, Maybe Text)
resolveConsciousness pio plan =
  case prepareRequestToTurnEffect (pepConsciousnessRequest plan) of
    Just request -> do
      result <- resolveTurnEffect pio request
      case result of
        TurnResConsciousness consciousLoop currentNarrative narrativeFragment ->
          pure (consciousLoop, currentNarrative, narrativeFragment)
        _ ->
          pure (initialLoop, Nothing, Nothing)
    Nothing ->
      pure (initialLoop, Nothing, Nothing)

resolveIntuition :: PipelineIO -> PrepareEffectPlan -> IO (Maybe IntuitiveFlash, Double, IntuitiveState)
resolveIntuition pio plan =
  case prepareRequestToTurnEffect (pepIntuitionRequest plan) of
    Just request -> do
      result <- resolveTurnEffect pio request
      case result of
        TurnResIntuition mFlash posterior intuitionState -> pure (mFlash, posterior, intuitionState)
        _ -> pure (Nothing, defaultPosterior, defaultIntuitiveState)
    Nothing ->
      pure (Nothing, defaultPosterior, defaultIntuitiveState)

resolveApiHealth :: PipelineIO -> PrepareEffectPlan -> IO Bool
resolveApiHealth pio plan =
  case prepareRequestToTurnEffect (pepApiHealthRequest plan) of
    Just request -> do
      result <- resolveTurnEffect pio request
      case result of
        TurnResApiHealth apiHealthy -> pure apiHealthy
        _ -> pure False
    Nothing ->
      pure False

prepareRequestToTurnEffect :: PrepareEffectRequest -> Maybe TurnEffectRequest
prepareRequestToTurnEffect request =
  case request of
    PrepareReqEmbedding inputText ->
      Just (TurnReqEmbedding inputText)
    PrepareReqNixGuard concept currentLoad atomLoad ->
      Just (TurnReqNixGuard concept currentLoad atomLoad)
    PrepareReqConsciousness semanticInput humanTheta resonance ->
      Just (TurnReqConsciousness semanticInput humanTheta resonance)
    PrepareReqIntuition resonance tension turnNumber ->
      Just (TurnReqIntuition resonance tension turnNumber)
    PrepareReqApiHealth ->
      Just TurnReqApiHealth

emptyEmbeddingResult :: IO EmbeddingResult
emptyEmbeddingResult =
  pure $
    EmbeddingResult
      { erEmbedding = mempty
      , erSource = EmbeddingLocalImplicit
      }

defaultPosterior :: Double
defaultPosterior = effectivePosterior defaultIntuitiveState

timeAction :: PipelineIO -> IO a -> IO (TimedResult a)
timeAction pio action = do
  started <- resolveEffectCurrentTime pio
  value <- action
  ended <- resolveEffectCurrentTime pio
  pure TimedResult
    { trStarted = started
    , trEnded = ended
    , trValue = value
    }

resolveEffectCurrentTime :: PipelineIO -> IO UTCTime
resolveEffectCurrentTime pio = do
  result <- resolveTurnEffect pio TurnReqCurrentTime
  case result of
    TurnResCurrentTime currentTime -> pure currentTime
    _ -> throwQxFx0 (PersistenceError "prepare timeline current time effect returned unexpected result")
