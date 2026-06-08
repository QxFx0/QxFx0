{-# LANGUAGE OverloadedStrings, DerivingStrategies #-}

{-|
CTS-41: ResponseContentAdmission — constitution-aware filtering of ContentMove
between TurnPlan (RMP + RCP) and render.

Priority order (truth-contract first, then shadow):
1. NonExpansiveRecoverySurface && family ∉ {CMClarify, CMRepair} → RadRerouteClarify
2. severity ∈ {Safety, Contract} && legitScore < threshold        → RadWeakenStance
3. severity ∈ {Safety, Contract}                                  → RadSoftenExplicitness
4. otherwise                                                       → RadAdmitPlans
-}
module QxFx0.Core.ResponseContentAdmission
  ( ResponseContentAdmissionInput(..)
  , ResponseContentAdmissionDecision(..)
  , AdmittedResponseContent(..)
  , admitResponseContent
  ) where

import QxFx0.Types.Observability (TruthContractStatus(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..))
import QxFx0.Types.Decision.Model
  ( ResponseMeaningPlan(..)
  , ResponseContentPlan(..)
  )
import QxFx0.Types.Sense (MicroPlan(..))
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily(..))
import QxFx0.Types.Decision.Enums.Conversation (StanceMarker(..), ContentMove(..))
import QxFx0.Types.Decision.Enums.Render (RenderStyle(..))
import QxFx0.Types.Thresholds (legitimacyRecoveryThreshold)

data ResponseContentAdmissionInput = ResponseContentAdmissionInput
  { rcaiTruthContractStatus      :: !TruthContractStatus
  , rcaiShadowDivergenceSeverity :: !ShadowDivergenceSeverity
  , rcaiLegitScore               :: !Double
  } deriving stock (Eq, Show)

data ResponseContentAdmissionDecision
  = RadAdmitPlans
  | RadSoftenExplicitness
  | RadWeakenStance
  | RadRerouteClarify
  deriving stock (Eq, Show)

data AdmittedResponseContent = AdmittedResponseContent
  { arcDecision :: !ResponseContentAdmissionDecision
  , arcRmp      :: !ResponseMeaningPlan
  , arcRcp      :: !ResponseContentPlan
  } deriving stock (Eq, Show)

admitResponseContent
  :: ResponseContentAdmissionInput
  -> ResponseMeaningPlan
  -> ResponseContentPlan
  -> AdmittedResponseContent
admitResponseContent input rmp rcp =
  let decision = classifyDecision input rmp
  in case decision of
       RadRerouteClarify ->
         AdmittedResponseContent decision rmp
           (rcp { rcpFamily     = CMClarify
                , rcpOpening    = MoveClarifyDisambiguate
                , rcpCore       = MoveClarifyDisambiguate
                , rcpLimit      = MoveClarifyDisambiguate
                , rcpContinuation = MoveClarifyDisambiguate
                , rcpStyle      = StyleStandard
                })
       RadWeakenStance ->
         let currentStrength = rmpCommitmentStrength rmp
         in AdmittedResponseContent decision
              (rmp { rmpStance              = HoldBack
                   , rmpCommitmentStrength  = min currentStrength 0.3
                   })
              rcp
       RadSoftenExplicitness ->
         let origMicro = rmpMicroPlan rmp
         in AdmittedResponseContent decision
              (rmp { rmpMicroPlan = origMicro { mpExplicitness = mpExplicitness origMicro * 0.5 } })
              rcp
       RadAdmitPlans ->
         AdmittedResponseContent decision rmp rcp

classifyDecision
  :: ResponseContentAdmissionInput
  -> ResponseMeaningPlan
  -> ResponseContentAdmissionDecision
classifyDecision input rmp
  -- 1. truth-contract priority: NonExpansiveRecoverySurface → reroute to clarify
  --    (unless already in CMClarify or CMRepair — those are already recovery-mode)
  | rcaiTruthContractStatus input == NonExpansiveRecoverySurface
    && rmpFamily rmp `notElem` [CMClarify, CMRepair]
    = RadRerouteClarify
  -- 2. shadow severity + low legit → weaken stance
  | rcaiShadowDivergenceSeverity input `elem` [ShadowSeveritySafety, ShadowSeverityContract]
    && rcaiLegitScore input < legitimacyRecoveryThreshold
    = RadWeakenStance
  -- 3. shadow severity (any legit) → soften explicitness
  | rcaiShadowDivergenceSeverity input `elem` [ShadowSeveritySafety, ShadowSeverityContract]
    = RadSoftenExplicitness
  -- 4. default → admit as-is
  | otherwise
    = RadAdmitPlans
