{-# LANGUAGE StrictData, OverloadedStrings, DerivingStrategies, RankNTypes #-}
{-|
Description : supplier
Internal `PipelineIO` runtime contracts, policy enums, and interpreter record. -}
module QxFx0.Core.PipelineIO.Internal
  ( PipelineRuntimeMode(..)
  , LocalRecoveryPolicy(..)
  , ShadowPolicy(..)
  , ShadowResult(..)
  , ConatusPrior
  , defaultConatusPrior
  , TurnEffectInterpreter
  , PipelineIO(..)
  ) where

import QxFx0.Core.TurnPipeline.Effects (TurnEffectRequest(..), TurnEffectResult)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop)
import QxFx0.Core.Intuition (IntuitiveState)
import QxFx0.Self.Conatus (ConatusEnergy(..))
import QxFx0.Types (CanonicalMoveFamily, IllocutionaryForce)
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowSnapshotId
  )
import Data.Text (Text)
import Data.Sequence (Seq)

data PipelineRuntimeMode
  = RuntimeDegraded
  | RuntimeStrict
  deriving stock (Eq, Show)

data ShadowPolicy
  = ShadowObserve
  | ShadowPreferVerified
  | ShadowBlockOnUnavailableOrDivergence
  deriving stock (Eq, Show)

data ShadowResult = ShadowResult
  { srDatalogVerdict :: !(Maybe (CanonicalMoveFamily, IllocutionaryForce))
  , srStatus :: !ShadowStatus
  , srDivergence :: !ShadowDivergence
  , srSnapshotId :: !ShadowSnapshotId
  , srDiagnostics :: ![Text]
  } deriving stock (Show, Eq)

type TurnEffectInterpreter = TurnEffectRequest -> IO TurnEffectResult

type ConatusPrior = ConatusEnergy -> TurnEffectRequest -> Double

defaultConatusPrior :: ConatusPrior
defaultConatusPrior conatus request =
  let conatusBias
        | ceScalar conatus < 0 = 100
        | ceScalar conatus < 0.5 = 10
        | otherwise = 0
  in conatusBias + intrinsicPriority request
  where
    intrinsicPriority req =
      case req of
        TurnReqApiHealth -> 90
        TurnReqReadEnv _ -> 85
        TurnReqSemanticIntrospectionEnv -> 85
        TurnReqCurrentTime -> 85
        TurnReqRequestId -> 85
        TurnReqAgdaVerify -> 80
        TurnReqShadow _ _ _ -> 75
        TurnReqConsciousness _ _ _ _ _ -> 70
        TurnReqIntuition _ _ _ _ _ _ _ -> 65
        TurnReqEmbedding _ -> 60
        TurnReqNixGuard _ _ _ -> 55
        TurnReqLinearizeClaimAst _ _ _ -> 50
        TurnReqLinearizeDialogAtoms _ _ _ -> 50
        TurnReqExternalQuery _ _ _ -> 45
        TurnReqCommitRuntimeState _ _ _ -> 40
        TurnReqSaveState _ _ _ _ -> 35
        TurnReqRollbackTurnProjections _ _ -> 30
        TurnReqCheckpoint _ -> 25
        TurnReqTestMarkOnceFile _ -> 20

data PipelineIO = PipelineIO
  { pioRuntimeMode      :: !PipelineRuntimeMode
  , pioShadowPolicy     :: !ShadowPolicy
  , pioLocalRecoveryPolicy :: !LocalRecoveryPolicy
  , pioInterpreter      :: !TurnEffectInterpreter
  , pioUpdateHistory    :: Text -> Seq Text -> Seq Text
  , pioModifyConsciousLoop :: forall a. (ConsciousnessLoop -> IO (ConsciousnessLoop, a)) -> IO a
  , pioModifyIntuition :: forall a. (IntuitiveState -> IO (IntuitiveState, a)) -> IO a
  , pioConatusPrior     :: !ConatusPrior
  }
