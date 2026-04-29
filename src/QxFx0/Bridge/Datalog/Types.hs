{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Public shadow execution result types plus internal fallback constructors. -}
module QxFx0.Bridge.Datalog.Types
  ( ShadowResult(..)
  , shadowUnavailableResult
  ) where

import Data.Text (Text)
import QxFx0.Types (R5Verdict)
import QxFx0.Types.Decision (ShadowStatus(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind
  , ShadowSnapshot(..)
  , ShadowSnapshotId
  , emptyShadowDivergence
  , mkShadowSnapshotId
  )

data ShadowResult = ShadowResult
  { srStatus :: !ShadowStatus
  , srDivergence :: !ShadowDivergence
  , srDatalogVerdict :: !(Maybe R5Verdict)
  , srSnapshotId :: !ShadowSnapshotId
  , srDiagnostics :: ![Text]
  }
  deriving stock (Eq, Show)

shadowUnavailableResult :: ShadowSnapshot -> ShadowDivergenceKind -> Text -> ShadowResult
shadowUnavailableResult snapshot kind err =
  ShadowResult
    { srStatus = ShadowUnavailable
    , srDivergence = emptyShadowDivergence {sdKind = kind}
    , srDatalogVerdict = Nothing
    , srSnapshotId = mkShadowSnapshotId snapshot
    , srDiagnostics = [err]
    }
