{-# LANGUAGE StrictData, OverloadedStrings, DerivingStrategies, RankNTypes #-}
{-| Internal `PipelineIO` runtime contracts, policy enums, and interpreter record. -}
module QxFx0.Core.PipelineIO.Internal
  ( PipelineRuntimeMode(..)
  , LocalRecoveryPolicy(..)
  , ShadowPolicy(..)
  , ShadowResult(..)
  , TurnEffectInterpreter
  , PipelineIO(..)
  ) where

import QxFx0.Core.TurnPipeline.Effects (TurnEffectRequest, TurnEffectResult)
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

data PipelineIO = PipelineIO
  { pioRuntimeMode      :: !PipelineRuntimeMode
  , pioShadowPolicy     :: !ShadowPolicy
  , pioLocalRecoveryPolicy :: !LocalRecoveryPolicy
  , pioInterpreter      :: !TurnEffectInterpreter
  , pioUpdateHistory    :: Text -> Seq Text -> Seq Text
  }
