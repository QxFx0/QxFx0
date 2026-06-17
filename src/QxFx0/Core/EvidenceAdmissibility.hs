{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Core.EvidenceAdmissibility
Description : SLICE-012 — evidence admissibility classification.

== Policy

> Guard Unavailable is allowed runtime degradation, but forbidden proof
> substrate.

In /normal runtime mode/, an @Unavailable@ guard is fail-open degraded:
the turn proceeds, output is produced, and the evidence is marked
'EvidenceDegradedGuardUnavailable' for observability.

In /governed-evidence mode/ (@QXFX0_GOVERNED_EVIDENCE=1@), an
@Unavailable@ guard makes the evidence 'EvidenceInadmissible'. The
caller (finalize precommit) fail-closes by throwing
'QxFx0.ExceptionPolicy.EvidenceInadmissibleFailure' to prevent
inadmissible evidence from entering the evidence package.

This module is the /classification/ layer; the /enforcement/ (throwing)
lives in the caller.
-}
module QxFx0.Core.EvidenceAdmissibility
  ( isGovernedEvidenceMode
  , classifyEvidence
  , classifyEvidenceIO
  ) where

import System.Environment (lookupEnv)
import Data.Maybe (isJust)
import Data.Text (Text)

import QxFx0.Types.Domain (NixGuardStatus(..))
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))

-- | Read @QXFX0_GOVERNED_EVIDENCE@ env var. Returns 'True' when set to
-- @1@. This is the governed-evidence mode flag — orthogonal to
-- @QXFX0_RUNTIME_MODE@ (strict/degraded), which governs runtime safety.
-- Governed-evidence mode governs /evidence admissibility/, not runtime
-- behavior.
isGovernedEvidenceMode :: IO Bool
isGovernedEvidenceMode = do
  mVal <- lookupEnv "QXFX0_GOVERNED_EVIDENCE"
  pure (isJust mVal && mVal == Just "1")

-- | Pure classification of evidence admissibility from guard status and
-- governed-evidence mode flag.
--
-- * 'Allowed' or 'Blocked' → 'EvidenceGoverned' (guard was present and
--   checked, regardless of mode).
-- * 'Unavailable' + normal mode → 'EvidenceDegradedGuardUnavailable'
--   (observability marker; runtime continues).
-- * 'Unavailable' + governed-evidence mode → 'EvidenceInadmissible'
--   (evidence forbidden; caller should fail-closed).
classifyEvidence :: Bool -> NixGuardStatus -> EvidenceAdmissibility
classifyEvidence governedMode = \case
  Allowed       -> EvidenceGoverned
  Blocked _     -> EvidenceGoverned
  Unavailable _ ->
    if governedMode
      then EvidenceInadmissible
      else EvidenceDegradedGuardUnavailable

-- | IO variant: reads the env var, then classifies.
classifyEvidenceIO :: NixGuardStatus -> IO EvidenceAdmissibility
classifyEvidenceIO guardStatus = do
  governed <- isGovernedEvidenceMode
  pure (classifyEvidence governed guardStatus)
