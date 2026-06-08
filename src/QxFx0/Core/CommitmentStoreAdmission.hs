{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Core.CommitmentStoreAdmission
Description : CTS-42 — constitution-dependent gate on FactualClaim persistence.

A turn's rendered surface may be authoritative (canonical/assembled) or
degraded (fallback, recovery, shim, default, generated, legacy). Only
authoritative surfaces should commit a 'FactualClaimPayload' into the
persistent 'SemanticCommitmentStore'.

The decision depends only on 'TruthContractStatus'. It is taken once in
Finalize and applied to both the anchor claim and the surface-parsed claim.

Exhaustive pattern-match on all 8 constructors — no wildcard, no Ord/Enum.
Adding a 9th constructor yields a compilation error, forcing classification.
-}
module QxFx0.Core.CommitmentStoreAdmission
  ( CommitmentStoreAdmissionDecision (..)
  , admitCommitmentToStore
  ) where

import Data.Aeson (ToJSON (..), FromJSON (..), defaultOptions, genericToJSON, genericParseJSON)
import GHC.Generics (Generic)

import QxFx0.Types.Observability (TruthContractStatus(..))

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

-- | Admit only when the truth contract reports an authoritative surface.
--
-- Exhaustive match on all 8 constructors. No wildcard, no Ord/Enum.
admitCommitmentToStore :: TruthContractStatus -> CommitmentStoreAdmissionDecision
admitCommitmentToStore status = case status of
  CanonicalSurfacePreserved   -> CsaAdmitCanonical
  AssembledSurfacePreserved   -> CsaAdmitCanonical
  ExplicitFallbackSurface       -> CsaSuppress
  NonExpansiveRecoverySurface -> CsaSuppress
  CompatibilityShimSurface      -> CsaSuppress
  DefaultedSurface              -> CsaSuppress
  GeneratedArtifactSurface      -> CsaSuppress
  LegacyIncompleteSurface       -> CsaSuppress
