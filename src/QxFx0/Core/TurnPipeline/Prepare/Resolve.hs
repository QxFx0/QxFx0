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
import Data.Text (Text)
import Data.Time.Clock (UTCTime)

resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> IO PrepareEffectResults
resolvePrepareEffects pio effectPlan = do
  let t0 = pepCapturedCurrentTime effectPlan
  _ <- evaluate (pepStatic effectPlan)
  let tStatic1 = t0
      requestPairs :: [(Text, Maybe TurnEffectRequest)]
      requestPairs =
        [ ("embedding", prepareRequestToTurnEffect (pepEmbeddingRequest effectPlan))
        , ("nix", prepareRequestToTurnEffect (pepNixGuardRequest effectPlan))
        , ("consciousness", prepareRequestToTurnEffect (pepConsciousnessRequest effectPlan))
        , ("intuition", prepareRequestToTurnEffect (pepIntuitionRequest effectPlan))
        , ("api_health", prepareRequestToTurnEffect (pepApiHealthRequest effectPlan))
        ]
      scheduledPairs :: [(Text, TurnEffectRequest)]
      scheduledPairs =
        scheduleTurnEffects pio (psConatusEnergy (pepStatic effectPlan))
          [ (label, request)
          | (label, Just request) <- requestPairs
          ]
  resolved <- forConcurrently scheduledPairs $ \(label, turnRequest) -> do
    result <- resolveTurnEffect pio turnRequest
    pure (label, result)
  -- Prepare-stage missing or unexpected effect results are intentionally
  -- classified as degraded continuation rather than fail-closed termination:
  -- local embedding, nix-blocked, default intuition/consciousness, and
  -- apiHealthy=False keep the turn moving while reducing epistemic strength.
  let embeddingResult =
        fromMaybe fallbackEmbeddingResult $ do
          (_, TurnResEmbedding value) <- firstMatch (\(label, result) -> label == "embedding" && isEmbeddingResult result) resolved
          Just value
      nixStatus =
        fromMaybe (Blocked "nix_guard_missing_request") $ do
          (_, TurnResNixGuard value) <- firstMatch (\(label, result) -> label == "nix" && isNixResult result) resolved
          Just value
      consciousnessResult =
        fromMaybe (initialLoop, Nothing, Nothing) $ do
          (_, TurnResConsciousness loop narrative fragment) <- firstMatch (\(label, result) -> label == "consciousness" && isConsciousnessResult result) resolved
          Just (loop, narrative, fragment)
      intuitionResult =
        fromMaybe (Nothing, defaultPosterior, defaultIntuitiveState) $ do
          (_, TurnResIntuition flash posterior state) <- firstMatch (\(label, result) -> label == "intuition" && isIntuitionResult result) resolved
          Just (flash, posterior, state)
      apiHealthy =
        fromMaybe False $ do
          (_, TurnResApiHealth value) <- firstMatch (\(label, result) -> label == "api_health" && isApiHealthResult result) resolved
          Just value
      timedEmb = TimedResult t0 t0 embeddingResult
      timedNix = TimedResult t0 t0 nixStatus
      timedConsciousness = TimedResult t0 t0 consciousnessResult
      timedIntuition = TimedResult t0 t0 intuitionResult
      timedApiHealth = TimedResult t0 t0 apiHealthy
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

firstMatch :: (a -> Bool) -> [a] -> Maybe a
firstMatch predicate = go
  where
    go [] = Nothing
    go (x:xs)
      | predicate x = Just x
      | otherwise = go xs
