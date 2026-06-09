{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.CommitmentStoreAdmission
Description : canonical — CTS-42 admission decision type.

The 'CommitmentStoreAdmissionDecision' enum lives in 'Types' so that
'TurnReplayTrace' (a 'Types' record) can reference it without a
'Core' import.
-}
module QxFx0.Types.CommitmentStoreAdmission
  ( CommitmentStoreAdmissionDecision (..)
  ) where

import Data.Aeson (ToJSON (..), FromJSON (..), defaultOptions, genericToJSON, genericParseJSON)
import GHC.Generics (Generic)

-- | Decision whether a turn's factual claim may be persisted.
--
-- 'CsaAdmitCanonical' — the surface is authoritative (canonical or
-- assembled), the claim is written to 'scsActive'.
--
-- 'CsaSuppress' — the surface is degraded or non-authoritative; the claim
-- is NOT written. This closes the M6 C3 "commitment accountability" leak.
data CommitmentStoreAdmissionDecision
  = CsaAdmitCanonical
  | CsaSuppress
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
