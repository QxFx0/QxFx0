{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Generic Cap-Clarify admission pattern.

Replaces 3 hand-rolled modules (EarlyFamily, SemanticContribution, SemanticLogic).
InterpretationAdmission is left hand-rolled (4th constructor + frame mutation).

Logic:
  not in-scope → admit raw;
  authoritative && !conatus → admit raw;
  all weak → preserve;
  otherwise → cap to CMClarify.
-}
module QxFx0.Types.Admission.PatternCapClarify
  ( CapClarifyConfig(..)
  , admitByCapClarify
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.Observability (TruthContractStatus)

data CapClarifyConfig input dat admitted decision = CapClarifyConfig
  { cccGetTruthContract :: input -> TruthContractStatus
  , cccConatusFired     :: input -> Bool
  , cccInScope          :: input -> dat -> Bool
  , cccAllWeak          :: dat -> Bool
  , cccCapDat           :: dat -> dat
  , cccBuildAdmitted    :: input -> dat -> dat -> decision -> admitted
  , cccDecisionAdmit    :: decision
  , cccDecisionPreserve :: decision
  , cccDecisionCap      :: decision
  }

admitByCapClarify
  :: CapClarifyConfig input dat admitted decision
  -> input
  -> dat
  -> admitted
admitByCapClarify cfg inp dat
  | not (cccInScope cfg inp dat) =
      cccBuildAdmitted cfg inp dat dat (cccDecisionAdmit cfg)
  | truthContractIsAuthoritative (cccGetTruthContract cfg inp)
      && not (cccConatusFired cfg inp) =
      cccBuildAdmitted cfg inp dat dat (cccDecisionAdmit cfg)
  | cccAllWeak cfg dat =
      cccBuildAdmitted cfg inp dat dat (cccDecisionPreserve cfg)
  | otherwise =
      cccBuildAdmitted cfg inp dat (cccCapDat cfg dat) (cccDecisionCap cfg)
