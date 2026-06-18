{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.TruthContract
  ( truthContractIsAuthoritative
  , truthContractAllowsStrongMutation
  , truthContractAllowsHardKnowledgeTone
  , applyTruthContractCeiling
  , capByTruthContract
  , capEpistemicByTruthContract
  , capCommitmentStrengthByTruthContract
  , replayProvenanceStatusForAuthority
  , replayProvenanceStatusForOutcome
  , normalizedReplayProvenanceStatus
  , authorityClassIsAuthoritative
  , truthContractRebindRenderedText
  ) where

import Data.Text (Text)

import QxFx0.Types

truthContractIsAuthoritative :: TruthContractStatus -> Bool
truthContractIsAuthoritative truthStatus =
  truthStatus `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved]

truthContractAllowsStrongMutation :: TruthContractStatus -> Bool
truthContractAllowsStrongMutation = truthContractIsAuthoritative

truthContractAllowsHardKnowledgeTone :: TruthContractStatus -> Bool
truthContractAllowsHardKnowledgeTone CanonicalSurfacePreserved = True
truthContractAllowsHardKnowledgeTone _ = False

authorityClassIsAuthoritative :: AuthorityClass -> Bool
authorityClassIsAuthoritative authority =
  authority `elem` [AuthorityCanonical, AuthorityAssembled]

applyTruthContractCeiling :: TruthContractStatus -> EpistemicStatus -> EpistemicStatus
applyTruthContractCeiling = capEpistemicByTruthContract

capByTruthContract :: TruthContractStatus -> EpistemicStatus -> EpistemicStatus
capByTruthContract = capEpistemicByTruthContract

capEpistemicByTruthContract :: TruthContractStatus -> EpistemicStatus -> EpistemicStatus
capEpistemicByTruthContract truthStatus epistemic
  | truthContractIsAuthoritative truthStatus = epistemic
  | otherwise =
      case epistemic of
        Known confidence -> Probable confidence
        Probable confidence -> Uncertain confidence
        other -> other

capCommitmentStrengthByTruthContract :: TruthContractStatus -> Double -> Double
capCommitmentStrengthByTruthContract truthStatus strength =
  case truthStatus of
    CanonicalSurfacePreserved -> strength
    AssembledSurfacePreserved -> min 0.75 strength
    _ -> min 0.45 strength

replayProvenanceStatusForAuthority :: AuthorityClass -> ReplayProvenanceStatus
replayProvenanceStatusForAuthority authority =
  case authority of
    AuthorityCanonical -> ReplayProvenanceComplete
    AuthorityAssembled -> ReplayProvenanceComplete
    AuthorityGeneratedArtifact -> ReplayProvenanceLegacyIncomplete
    AuthorityLegacyIncomplete -> ReplayProvenanceLegacyIncomplete
    AuthorityRecovery -> ReplayProvenanceLegacyIncomplete
    AuthorityFallback -> ReplayProvenanceLegacyIncomplete
    AuthorityShim -> ReplayProvenanceLegacyIncomplete
    AuthorityDefault -> ReplayProvenanceLegacyIncomplete

replayProvenanceStatusForOutcome :: ExecutedTurnOutcome -> ReplayProvenanceStatus
replayProvenanceStatusForOutcome = replayProvenanceStatusForAuthority . etoAuthorityClass

normalizedReplayProvenanceStatus :: ReplayProvenanceStatus -> AuthorityClass -> ReplayProvenanceStatus
normalizedReplayProvenanceStatus replayStatus authority
  | authorityClassIsAuthoritative authority = replayStatus
  | otherwise = ReplayProvenanceLegacyIncomplete

truthContractRebindRenderedText :: TruthContractStatus -> AuthorityClass -> Text -> Text
truthContractRebindRenderedText _truthStatus _authority rendered = rendered
