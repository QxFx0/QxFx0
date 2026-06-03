{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.SenseVectorAdmission
  ( SenseVectorAdmissionInput(..)
  , SenseVectorAdmissionDecision(..)
  , AdmittedSenseVector(..)
  , admitSenseVector
  ) where

import QxFx0.Semantic.Sense
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types

import qualified Data.Map.Strict as M

data SenseVectorAdmissionInput = SenseVectorAdmissionInput
  { svaiTruthContractStatus :: !TruthContractStatus
  , svaiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data SenseVectorAdmissionDecision
  = SvdAdmitRaw
  | SvdPreserveAmbiguous
  | SvdDampenClarify
  deriving stock (Eq, Show)

data AdmittedSenseVector = AdmittedSenseVector
  { asvVector :: !SenseVector
  , asvDecision :: !SenseVectorAdmissionDecision
  } deriving stock (Eq, Show)

admitSenseVector :: SenseVectorAdmissionInput -> SenseVector -> AdmittedSenseVector
admitSenseVector input vec
  | not (vectorAdmissionInScope vec) = AdmittedSenseVector vec SvdAdmitRaw
  | svaiConatusGateFired input && not (vectorAlreadyWeakOrAmbiguous vec) =
      AdmittedSenseVector (softenVector vec) SvdDampenClarify
  | not (truthContractIsAuthoritative (svaiTruthContractStatus input))
      && not (vectorAlreadyWeakOrAmbiguous vec) =
      AdmittedSenseVector (softenVector vec) SvdDampenClarify
  | svaiConatusGateFired input || not (truthContractIsAuthoritative (svaiTruthContractStatus input)) =
      AdmittedSenseVector vec SvdPreserveAmbiguous
  | otherwise = AdmittedSenseVector vec SvdAdmitRaw

softenVector :: SenseVector -> SenseVector
softenVector vec =
  vec
    { svOperators = [OpClarify]
    , svAxes = M.filterWithKey (\axis _ -> axis `elem` [AxKnowledge, AxRepair, AxSelf]) (svAxes vec)
    , svConfidence = min 0.55 (svConfidence vec)
    }

vectorAlreadyWeakOrAmbiguous :: SenseVector -> Bool
vectorAlreadyWeakOrAmbiguous vec =
  svConfidence vec <= 0.55
    || svOperators vec `elem` [[OpClarify], [OpRepair], [OpGround]]

vectorAdmissionInScope :: SenseVector -> Bool
vectorAdmissionInScope vec =
  svAgent vec /= Nothing || svTarget vec /= Nothing || AxSelf `M.member` svAxes vec
