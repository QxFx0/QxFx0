{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

{-| Public operations over `PipelineIO`, including effect dispatch and typed adapters. -}
module QxFx0.Core.PipelineIO.Operations
  ( pipelineRuntimeMode
  , pipelineRuntimeModeText
  , pipelineShadowPolicy
  , shadowPolicyText
  , pipelineLocalRecoveryPolicy
  , localRecoveryPolicyText
  , resolveTurnEffect
  , resolveTurnEffects
  , runShadowVerification
  , verifyPipelineAgda
  , savePipelineState
  , checkpointPipelineState
  , resolvePipelineNixPath
  , runPipelineNixCheck
  , modifyPipelineConsciousLoop
  , modifyPipelineIntuition
  , checkPipelineApiHealth
  , pipelineUpdateHistory
  ) where

import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, initialLoop)
import QxFx0.Core.Intuition (IntuitiveState, defaultIntuitiveState)
import QxFx0.Core.PipelineIO.Internal
  ( PipelineIO(..)
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , ShadowResult(..)
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Types
  ( CanonicalMoveFamily
  , IllocutionaryForce
  , SystemState
  )
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.Domain (AtomTag, NixGuardStatus(..))
import QxFx0.Types.Readiness (AgdaVerificationStatus(..))
import QxFx0.Types.Recovery (LocalRecoveryPolicy, renderLocalRecoveryPolicy)
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowSnapshotId(..)
  , emptyShadowDivergence
  )
import QxFx0.Types.Persistence (PersistenceDiagnostic(..), PersistenceStage(..))
import QxFx0.Types.TurnProjection (TurnProjection)

import Data.Sequence (Seq)
import Data.Text (Text)

pipelineRuntimeMode :: PipelineIO -> PipelineRuntimeMode
pipelineRuntimeMode = pioRuntimeMode

pipelineRuntimeModeText :: PipelineRuntimeMode -> Text
pipelineRuntimeModeText mode =
  case mode of
    RuntimeStrict -> "strict"
    RuntimeDegraded -> "degraded"

pipelineShadowPolicy :: PipelineIO -> ShadowPolicy
pipelineShadowPolicy = pioShadowPolicy

shadowPolicyText :: ShadowPolicy -> Text
shadowPolicyText policy =
  case policy of
    ShadowObserve -> "observe"
    ShadowPreferVerified -> "prefer_verified"
    ShadowBlockOnUnavailableOrDivergence -> "block_on_unavailable_or_divergence"

pipelineLocalRecoveryPolicy :: PipelineIO -> LocalRecoveryPolicy
pipelineLocalRecoveryPolicy = pioLocalRecoveryPolicy

localRecoveryPolicyText :: LocalRecoveryPolicy -> Text
localRecoveryPolicyText = renderLocalRecoveryPolicy

resolveTurnEffect :: PipelineIO -> TurnEffectRequest -> IO TurnEffectResult
resolveTurnEffect pio request = pioInterpreter pio request

resolveTurnEffects :: PipelineIO -> [TurnEffectRequest] -> IO [TurnEffectResult]
resolveTurnEffects pio = mapM (resolveTurnEffect pio)

runShadowVerification :: PipelineIO -> CanonicalMoveFamily -> IllocutionaryForce -> [AtomTag] -> IO ShadowResult
runShadowVerification pio family force atomTags = do
  result <- resolveTurnEffect pio (TurnReqShadow family force atomTags)
  case result of
    TurnResShadow datalogVerdict shadowStatus divergence snapshotId diagnostics ->
      pure ShadowResult
        { srDatalogVerdict = datalogVerdict
        , srStatus = shadowStatus
        , srDivergence = divergence
        , srSnapshotId = snapshotId
        , srDiagnostics = diagnostics
        }
    _ ->
      pure ShadowResult
        { srDatalogVerdict = Nothing
        , srStatus = ShadowUnavailable
        , srDivergence = emptyShadowDivergence { sdKind = ShadowBridgeSkew }
        , srSnapshotId = ShadowSnapshotId "shadow:unexpected_effect"
        , srDiagnostics = ["unexpected_shadow_effect_result"]
        }

verifyPipelineAgda :: PipelineIO -> IO AgdaVerificationStatus
verifyPipelineAgda pio = do
  result <- resolveTurnEffect pio TurnReqAgdaVerify
  case result of
    TurnResAgdaVerify agdaStatus -> pure agdaStatus
    _ -> pure AgdaInvalid

savePipelineState :: PipelineIO -> SystemState -> Text -> Maybe TurnProjection -> IO (Either PersistenceDiagnostic SystemState)
savePipelineState pio ss sid mProj = do
  result <- resolveTurnEffect pio (TurnReqSaveState ss sid mProj)
  case result of
    TurnResSaveState saved -> pure saved
    _ -> pure (Left (PdSaveFailed StageUnknown (Just "savePipelineState") (Just "unexpected_save_state_effect_result")))

checkpointPipelineState :: PipelineIO -> Int -> IO ()
checkpointPipelineState pio turnCount = do
  _ <- resolveTurnEffect pio (TurnReqCheckpoint turnCount)
  pure ()

resolvePipelineNixPath :: PipelineIO -> IO (Maybe FilePath)
resolvePipelineNixPath _ = pure Nothing

runPipelineNixCheck :: PipelineIO -> Maybe FilePath -> Text -> Double -> Double -> IO NixGuardStatus
runPipelineNixCheck pio _ concept agency tension = do
  result <- resolveTurnEffect pio (TurnReqNixGuard concept agency tension)
  case result of
    TurnResNixGuard nixStatus -> pure nixStatus
    _ -> pure (Unavailable "unexpected_nix_effect_result")

modifyPipelineConsciousLoop :: PipelineIO -> (forall a. (ConsciousnessLoop -> IO (ConsciousnessLoop, a)) -> IO a)
modifyPipelineConsciousLoop _ f = do
  let cl = initialLoop
  (_, result) <- f cl
  pure result

modifyPipelineIntuition :: PipelineIO -> (forall a. (IntuitiveState -> IO (IntuitiveState, a)) -> IO a)
modifyPipelineIntuition _ f = do
  let intuitive = defaultIntuitiveState
  (_, result) <- f intuitive
  pure result

checkPipelineApiHealth :: PipelineIO -> IO Bool
checkPipelineApiHealth pio = do
  result <- resolveTurnEffect pio TurnReqApiHealth
  case result of
    TurnResApiHealth ok -> pure ok
    _ -> pure False

pipelineUpdateHistory :: PipelineIO -> Text -> Seq Text -> Seq Text
pipelineUpdateHistory pio = pioUpdateHistory pio
