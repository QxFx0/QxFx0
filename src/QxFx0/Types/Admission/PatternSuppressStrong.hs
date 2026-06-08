{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Generic Suppress-Strong admission pattern.

Replaces 7 hand-rolled modules that share this logic:
  authoritative → admit raw;
  all-safe → preserve;
  otherwise → suppress/filter unsafe items.

Configured via @SuppressStrongConfig@ so each caller provides:
- truth-contract accessor
- "all safe?" predicate
- suppress/filter function
- admitted-result builder
- three decision constructors
-}
module QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..)
  , admitBySuppressStrong
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.Observability (TruthContractStatus)

data SuppressStrongConfig input dat admitted decision = SuppressStrongConfig
  { sscGetTruthContract :: input -> TruthContractStatus
  , sscAllSafe          :: dat -> Bool
  , sscSuppress         :: dat -> dat
  , sscBuildAdmitted    :: input -> dat -> dat -> decision -> admitted
  , sscDecisionAdmit    :: decision
  , sscDecisionPreserve :: decision
  , sscDecisionSuppress :: decision
  }

admitBySuppressStrong
  :: SuppressStrongConfig input dat admitted decision
  -> input
  -> dat
  -> admitted
admitBySuppressStrong cfg inp dat
  | truthContractIsAuthoritative (sscGetTruthContract cfg inp) =
      sscBuildAdmitted cfg inp dat dat (sscDecisionAdmit cfg)
  | sscAllSafe cfg dat =
      sscBuildAdmitted cfg inp dat dat (sscDecisionPreserve cfg)
  | otherwise =
      sscBuildAdmitted cfg inp dat (sscSuppress cfg dat) (sscDecisionSuppress cfg)
