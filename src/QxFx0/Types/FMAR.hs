{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.FMAR
Description : canonical — FMAR activation mode enum.

The 'FmarMode' enum lives in 'Types' so that 'TurnReplayTrace'
(a 'Types' record) can reference it without a 'Core' import.
-}
module QxFx0.Types.FMAR
  ( FmarMode (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

-- | FMAR activation mode, parsed from the @QXFX0_FMAR@ environment value.
--
--   * 'FmarOff'    — the static path is unchanged (byte-identical output).
--   * 'FmarShadow' — FMAR computes its choice and a directive for tracing,
--     but the detector family still drives rendering.
--   * 'FmarLive'   — FMAR drives both routing and rendering.
data FmarMode = FmarOff | FmarShadow | FmarLive
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
