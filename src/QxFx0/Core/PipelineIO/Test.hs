{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : supplier
Deterministic `PipelineIO` test harness and default in-memory effect interpreter. -}
module QxFx0.Core.PipelineIO.Test
  ( TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  ) where

import QxFx0.Core.ConsciousnessLoop
  ( clLastNarrative
  , initialLoop
  , runConsciousnessLoopWithSalience
  )
import QxFx0.Self.Field (emptyField, fieldResonance, mkResonance)
import QxFx0.Self.Salience (computeSalience)
import QxFx0.Core.Intuition
  ( checkIntuition
  , defaultIntuitiveState
  , effectivePosterior
  )
import QxFx0.Core.PipelineIO.Internal
  ( PipelineIO(..)
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , TurnEffectInterpreter
  , defaultConatusPrior
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Types.ExternalQuery (ExternalQueryError(..))
import QxFx0.Semantic.Embedding (textToEmbeddingResult)
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.Domain (NixGuardStatus(..))
import QxFx0.Types.Persistence (PersistenceDiagnostic(..), PersistenceStage(..))
import QxFx0.Types.Readiness (AgdaVerificationStatus(..))
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowSnapshotId(..)
  , emptyShadowDivergence
  )

import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Time.Clock as Clock
import Data.Time.Calendar (Day(ModifiedJulianDay))
import Control.Concurrent.MVar (modifyMVar, newMVar)
import System.IO.Unsafe (unsafePerformIO)

data TestPipelineConfig = TestPipelineConfig
  { tpcRuntimeMode :: !PipelineRuntimeMode
  , tpcShadowPolicy :: !ShadowPolicy
  , tpcLocalRecoveryPolicy :: !LocalRecoveryPolicy
  , tpcInterpreter :: !TurnEffectInterpreter
  , tpcUpdateHistory :: Text -> Seq Text -> Seq Text
  }

defaultTestPipelineConfig :: TestPipelineConfig
defaultTestPipelineConfig = TestPipelineConfig
  { tpcRuntimeMode = RuntimeDegraded
  , tpcShadowPolicy = ShadowObserve
  , tpcLocalRecoveryPolicy = LocalRecoveryEnabled
  , tpcInterpreter = defaultTestInterpreter
  , tpcUpdateHistory = \new hist ->
      let updated = new Seq.<| hist
      in Seq.take 50 updated
  }

mkTestPipelineIO :: TestPipelineConfig -> PipelineIO
mkTestPipelineIO cfg =
  let consciousState = unsafePerformIO (newMVar initialLoop)
      intuitionState = unsafePerformIO (newMVar defaultIntuitiveState)
  in PipelineIO
      { pioRuntimeMode = tpcRuntimeMode cfg
      , pioShadowPolicy = tpcShadowPolicy cfg
      , pioLocalRecoveryPolicy = tpcLocalRecoveryPolicy cfg
      , pioInterpreter = tpcInterpreter cfg
      , pioUpdateHistory = tpcUpdateHistory cfg
      , pioModifyConsciousLoop = \f -> modifyMVar consciousState $ \st -> do
          (st', result) <- f st
          pure (st', result)
      , pioModifyIntuition = \f -> modifyMVar intuitionState $ \st -> do
          (st', result) <- f st
          pure (st', result)
      , pioConatusPrior = defaultConatusPrior
      }

defaultTestInterpreter :: TurnEffectInterpreter
defaultTestInterpreter request =
  case request of
    TurnReqEmbedding inputText ->
      TurnResEmbedding <$> textToEmbeddingResult inputText
    TurnReqNixGuard _ _ _ ->
      pure (TurnResNixGuard (Unavailable "nix_unavailable_default_test_pipeline"))
    TurnReqConsciousness semanticInput humanTheta resonance conatusEnergy salienceWeights -> do
      let salience = computeSalience salienceWeights conatusEnergy (emptyField { fieldResonance = mkResonance resonance })
          (nextLoop, fragment) =
            runConsciousnessLoopWithSalience salience initialLoop semanticInput humanTheta resonance
          nextNarrative = clLastNarrative nextLoop
          nextFragment = if T.null fragment then Nothing else Just fragment
      pure (TurnResConsciousness nextLoop nextNarrative nextFragment)
    TurnReqIntuition _inputText resonance tension turnNumber _conatusEnergy _salienceWeights _semanticConfig -> do
      let (mFlash, intuitive') = checkIntuition resonance tension turnNumber defaultIntuitiveState
      pure (TurnResIntuition mFlash (effectivePosterior intuitive') intuitive')
    TurnReqApiHealth ->
      pure (TurnResApiHealth False)
    TurnReqShadow _ _ _ ->
      pure
        (TurnResShadow
          Nothing
          ShadowUnavailable
          emptyShadowDivergence
          (ShadowSnapshotId "shadow:test_default")
          ["shadow_unavailable_default_test_pipeline"])
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaMissingWitness)
    TurnReqCurrentTime ->
      pure (TurnResCurrentTime fixedTestTime)
    TurnReqRequestId ->
      pure (TurnResRequestId "request-id-test")
    TurnReqReadEnv _ ->
      pure (TurnResReadEnv Nothing)
    TurnReqTestMarkOnceFile _ ->
      pure (TurnResTestMarkOnceFile False)
    TurnReqSemanticIntrospectionEnv ->
      pure (TurnResSemanticIntrospectionEnv False)
    TurnReqCommitRuntimeState _ _ _ ->
      pure TurnResCommitRuntimeState
    TurnReqSaveState _ _ _ _ ->
      pure (TurnResSaveState (Left (PdSaveFailed StageUnknown Nothing (Just "persistence_unavailable_default_test_pipeline"))))
    TurnReqRollbackTurnProjections _ _ ->
      pure (TurnResRollbackTurnProjections (Left (PdRollbackFailed StageUnknown Nothing (Just "persistence_unavailable_default_test_pipeline"))))
    TurnReqCheckpoint _ ->
      pure TurnResCheckpointCompleted
    TurnReqLinearizeClaimAst _ _ _ ->
      pure (TurnResLinearizeClaimAst (Left "pgf_unavailable_default_test_pipeline"))
    TurnReqLinearizeDialogAtoms _ _ _ ->
      pure (TurnResLinearizeDialogAtoms (Left "pgf_unavailable_default_test_pipeline"))
    TurnReqExternalQuery _ _ _ ->
      pure (TurnResExternalQuery (Left (EqeInvalidResponse "external_query_unavailable_default_test_pipeline")))

fixedTestTime :: Clock.UTCTime
fixedTestTime = Clock.UTCTime (ModifiedJulianDay 0) 0
