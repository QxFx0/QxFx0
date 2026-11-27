{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Generic Lower-Confidence admission pattern.

Replaces 2 hand-rolled modules:
- RouteHintAdmission
- SemanticFrameAdmission

Pattern:
  not in-scope → admit raw;
  stateIntegrity && !weak → lower confidence;
  !authoritative && !weak → lower confidence;
  stateIntegrity || !authoritative → preserve ambiguous;
  otherwise → admit raw.
-}
module QxFx0.Types.Admission.PatternLowerConfidence
  ( LowerConfConfig(..)
  , admitByLowerConfidence
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.Observability (TruthContractStatus)

data LowerConfConfig input dat admitted decision = LowerConfConfig
  { lccGetTruthContract :: input -> TruthContractStatus
  , lccStateIntegrityFired     :: input -> Bool
  , lccInScope          :: input -> dat -> Bool
  , lccAlreadyWeak      :: dat -> Bool
  , lccSoften           :: input -> dat -> dat
  , lccMarkAmbiguous    :: input -> dat -> dat
  , lccBuildAdmitted    :: input -> dat -> decision -> admitted
  , lccDecisionAdmit    :: decision
  , lccDecisionPreserve :: decision
  , lccDecisionLower    :: decision
  }

admitByLowerConfidence
  :: LowerConfConfig input dat admitted decision
  -> input
  -> dat
  -> admitted
admitByLowerConfidence cfg inp dat
  | not (lccInScope cfg inp dat) =
      lccBuildAdmitted cfg inp dat (lccDecisionAdmit cfg)
  | lccStateIntegrityFired cfg inp && not (lccAlreadyWeak cfg dat) =
      lccBuildAdmitted cfg inp (lccSoften cfg inp dat) (lccDecisionLower cfg)
  | not (truthContractIsAuthoritative (lccGetTruthContract cfg inp))
      && not (lccAlreadyWeak cfg dat) =
      lccBuildAdmitted cfg inp (lccSoften cfg inp dat) (lccDecisionLower cfg)
  | lccStateIntegrityFired cfg inp || not (truthContractIsAuthoritative (lccGetTruthContract cfg inp)) =
      lccBuildAdmitted cfg inp (lccMarkAmbiguous cfg inp dat) (lccDecisionPreserve cfg)
  | otherwise =
      lccBuildAdmitted cfg inp dat (lccDecisionAdmit cfg)
