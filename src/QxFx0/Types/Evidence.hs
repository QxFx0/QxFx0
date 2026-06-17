{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Types.Evidence
Description : Evidence admissibility classification (SLICE-012).

The evidence admissibility type classifies whether a turn's trace
constitutes /governed evidence/ — evidence collected under a functioning
constitutional guard — or whether the guard was absent, making the
evidence inadmissible as a proof substrate.

== Policy (SLICE-012)

> Guard Unavailable is allowed runtime degradation, but forbidden proof
> substrate.

In /normal runtime mode/, an @Unavailable@ guard is fail-open degraded:
the turn proceeds, output is produced, and the trace is marked
'EvidenceDegradedGuardUnavailable' for observability. The runtime does
not fail.

In /governed-evidence mode/ (@QXFX0_GOVERNED_EVIDENCE=1@), an
@Unavailable@ guard makes the evidence 'EvidenceInadmissible'. The turn
may still produce output (degraded behavior is a separate axis), but the
evidence /cannot/ be claimed as \"governed\" or \"checked\". In
governed-evidence mode, the pipeline fail-closes for evidence collection
(throws 'QxFx0.ExceptionPolicy.EvidenceInadmissibleFailure') to prevent
inadmissible evidence from entering the evidence package.

== Orthogonality with runtime mode

This axis is /orthogonal/ to 'QXFX0_RUNTIME_MODE' (strict vs degraded),
which governs runtime safety. A run can be:

* @strict + governed-evidence@ — both safety and evidence enforced.
* @strict + non-governed@ — safety enforced, evidence not checked.
* @degraded + governed-evidence@ — safety relaxed, evidence still checked.
* @degraded + non-governed@ — both relaxed.

Governed-evidence mode does /not/ change runtime behavior; it changes
/evidence admissibility/ and fail-closes for evidence collection.
-}
module QxFx0.Types.Evidence
  ( EvidenceAdmissibility (..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Data.Text (Text)

-- | Classification of a turn's evidence relative to guard availability.
data EvidenceAdmissibility
  = EvidenceGoverned
    -- ^ Guard was present and checked ('Allowed' or 'Blocked').
    --   Evidence collected under this status /may/ be claimed as
    --   \"governed\" or \"checked\".
  | EvidenceDegradedGuardUnavailable
    -- ^ Guard was 'Unavailable'. Runtime degraded normally (fail-open).
    --   Evidence is /not/ governed; may /not/ be claimed as \"checked\".
    --   This is the normal-mode classification — observability, not failure.
  | EvidenceInadmissible
    -- ^ Guard was 'Unavailable' /and/ governed-evidence mode is active
    --   (@QXFX0_GOVERNED_EVIDENCE=1@). Evidence collection is forbidden;
    --   the turn is marked inadmissible. In governed-evidence mode this
    --   also triggers fail-closed via
    --   'QxFx0.ExceptionPolicy.EvidenceInadmissibleFailure'.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
