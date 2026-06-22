{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.AdmissionEquivalence
Description : Behavioral lock for the P1-1 generic-admission refactor.

These tests pin the EXACT observable behavior of the proposition-admission
functions — all three decision branches and constructor identity — for a set
of representative 3-guard/label modules.

They are written to pass against the CURRENT (pre-refactor) code, so the
green-before baseline proves they capture real behavior.  After each module is
converted to delegate to 'admitPropositionTriggers', the same assertions must
stay green — that is the equivalence proof.  The hazard they specifically catch
is constructor miswiring: the three 'pacDecision*' fields all share one decision
type per module, so a swapped wiring (e.g. AdmitRaw <-> PreserveAmbiguous) type-
checks but is wrong.  Pinning the decision constructor on each branch makes that
swap go red.
-}
module Test.Suite.AdmissionEquivalence
  ( admissionEquivalenceTests
  ) where

import Test.HUnit (Test (..), assertEqual)
import Data.Text (Text)

import QxFx0.Types.Observability (TruthContractStatus(..))

import QxFx0.Self.Salience (SelfVerdict(..), Salience(..), SalienceDriver(..), SalienceVerdict(..))
import QxFx0.Semantic.Logic (RankedFamily)

import QxFx0.Core.EarlyFamilyAdmission (admitEarlyFamilyRecommendation, EarlyFamilyAdmissionInput(..), EarlyFamilyAdmissionDecision(..), AdmittedEarlyFamily(..))
import QxFx0.Core.FamilyAdmission (admitFamilyCrystallization, FamilyAdmissionInput(..), FamilyAdmissionDecision(..), AdmittedFamily(..))
import QxFx0.Core.SemanticLogicAdmission (admitSemanticLogicWeighting, SemanticLogicAdmissionInput(..), SemanticLogicAdmissionDecision(..), AdmittedSemanticLogic(..))
import QxFx0.Core.SemanticContributionAdmission (admitSemanticContributions, SemanticContributionAdmissionInput(..), SemanticContributionAdmissionDecision(..), AdmittedSemanticContributions(..))
import QxFx0.Core.InterpretationAdmission (admitInterpretationCandidate, InterpretationAdmissionInput(..), InterpretationAdmissionDecision(..), AdmittedInterpretation(..))

import QxFx0.Types.Admission.PropositionConfrontAdmission (admitPropositionConfrontTriggers)
import QxFx0.Types.PropositionConfrontAdmission
  ( PropositionConfrontAdmissionInput(..)
  , PropositionConfrontAdmissionDecision(..)
  , RawPropositionConfrontTrigger(..)
  , AdmittedPropositionConfrontTriggers(..)
  )

import QxFx0.Types.Admission.PropositionWorldCauseAdmission (admitPropositionWorldCauseTriggers)
import QxFx0.Types.PropositionWorldCauseAdmission
  ( PropositionWorldCauseAdmissionInput(..)
  , PropositionWorldCauseAdmissionDecision(..)
  , RawPropositionWorldCauseTrigger(..)
  , AdmittedPropositionWorldCauseTriggers(..)
  )

import QxFx0.Types.Admission.PropositionAffectiveSupportPhraseAdmission (admitPropositionAffectiveSupportPhraseTriggers)
import QxFx0.Types.PropositionAffectiveSupportPhraseAdmission
  ( PropositionAffectiveSupportPhraseAdmissionInput(..), PropositionAffectiveSupportPhraseAdmissionDecision(..)
  , RawPropositionAffectiveSupportPhraseTrigger(..), AdmittedPropositionAffectiveSupportPhraseTriggers(..) )

import QxFx0.Types.Admission.PropositionAffectiveSupportProbeAdmission (admitPropositionAffectiveSupportProbeTriggers)
import QxFx0.Types.PropositionAffectiveSupportProbeAdmission
  ( PropositionAffectiveSupportProbeAdmissionInput(..), PropositionAffectiveSupportProbeAdmissionDecision(..)
  , RawPropositionAffectiveSupportProbeTrigger(..), AdmittedPropositionAffectiveSupportProbeTriggers(..) )

import QxFx0.Types.Admission.PropositionConceptKnowledgeAdmission (admitPropositionConceptKnowledgeTriggers)
import QxFx0.Types.PropositionConceptKnowledgeAdmission
  ( PropositionConceptKnowledgeAdmissionInput(..), PropositionConceptKnowledgeAdmissionDecision(..)
  , RawPropositionConceptKnowledgeTrigger(..), AdmittedPropositionConceptKnowledgeTriggers(..) )

import QxFx0.Types.Admission.PropositionContemplativeTopicAdmission (admitPropositionContemplativeTopicTriggers)
import QxFx0.Types.PropositionContemplativeTopicAdmission
  ( PropositionContemplativeTopicAdmissionInput(..), PropositionContemplativeTopicAdmissionDecision(..)
  , RawPropositionContemplativeTopicTrigger(..), AdmittedPropositionContemplativeTopicTriggers(..) )

import QxFx0.Types.Admission.PropositionDistinctionAdmission (admitPropositionDistinctionTriggers)
import QxFx0.Types.PropositionDistinctionAdmission
  ( PropositionDistinctionAdmissionInput(..), PropositionDistinctionAdmissionDecision(..)
  , RawPropositionDistinctionTrigger(..), AdmittedPropositionDistinctionTriggers(..) )

import QxFx0.Types.Admission.PropositionLocationFormationAdmission (admitPropositionLocationFormationTriggers)
import QxFx0.Types.PropositionLocationFormationAdmission
  ( PropositionLocationFormationAdmissionInput(..), PropositionLocationFormationAdmissionDecision(..)
  , RawPropositionLocationFormationTrigger(..), AdmittedPropositionLocationFormationTriggers(..) )

import QxFx0.Types.Admission.PropositionMisunderstandingAdmission (admitPropositionMisunderstandingTriggers)
import QxFx0.Types.PropositionMisunderstandingAdmission
  ( PropositionMisunderstandingAdmissionInput(..), PropositionMisunderstandingAdmissionDecision(..)
  , RawPropositionMisunderstandingTrigger(..), AdmittedPropositionMisunderstandingTriggers(..) )

import QxFx0.Types.Admission.PropositionNextStepAdmission (admitPropositionNextStepTriggers)
import QxFx0.Types.PropositionNextStepAdmission
  ( PropositionNextStepAdmissionInput(..), PropositionNextStepAdmissionDecision(..)
  , RawPropositionNextStepTrigger(..), AdmittedPropositionNextStepTriggers(..) )

import QxFx0.Types.Admission.PropositionOperationalCauseAdmission (admitPropositionOperationalCauseTriggers)
import QxFx0.Types.PropositionOperationalCauseAdmission
  ( PropositionOperationalCauseAdmissionInput(..), PropositionOperationalCauseAdmissionDecision(..)
  , RawPropositionOperationalCauseTrigger(..), AdmittedPropositionOperationalCauseTriggers(..) )

import QxFx0.Types.Admission.PropositionOperationalStatusAdmission (admitPropositionOperationalStatusTriggers)
import QxFx0.Types.PropositionOperationalStatusAdmission
  ( PropositionOperationalStatusAdmissionInput(..), PropositionOperationalStatusAdmissionDecision(..)
  , RawPropositionOperationalStatusTrigger(..), AdmittedPropositionOperationalStatusTriggers(..) )

import QxFx0.Types.Admission.PropositionPurposeAdmission (admitPropositionPurposeTriggers)
import QxFx0.Types.PropositionPurposeAdmission
  ( PropositionPurposeAdmissionInput(..), PropositionPurposeAdmissionDecision(..)
  , RawPropositionPurposeTrigger(..), AdmittedPropositionPurposeTriggers(..) )

import QxFx0.Types.Admission.PropositionRepairDirectiveAdmission (admitPropositionRepairDirectiveTriggers)
import QxFx0.Types.PropositionRepairDirectiveAdmission
  ( PropositionRepairDirectiveAdmissionInput(..), PropositionRepairDirectiveAdmissionDecision(..)
  , RawPropositionRepairDirectiveTrigger(..), AdmittedPropositionRepairDirectiveTriggers(..) )

import QxFx0.Types.Admission.PropositionSelfKnowledgeAdmission (admitPropositionSelfKnowledgeTriggers)
import QxFx0.Types.PropositionSelfKnowledgeAdmission
  ( PropositionSelfKnowledgeAdmissionInput(..), PropositionSelfKnowledgeAdmissionDecision(..)
  , RawPropositionSelfKnowledgeTrigger(..), AdmittedPropositionSelfKnowledgeTriggers(..) )

import QxFx0.Types.Admission.PropositionSelfStateAdmission (admitPropositionSelfStateTriggers)
import QxFx0.Types.PropositionSelfStateAdmission
  ( PropositionSelfStateAdmissionInput(..), PropositionSelfStateAdmissionDecision(..)
  , RawPropositionSelfStateTrigger(..), AdmittedPropositionSelfStateTriggers(..) )

import QxFx0.Types.Admission.PropositionSystemLogicAdmission (admitPropositionSystemLogicTriggers)
import QxFx0.Types.PropositionSystemLogicAdmission
  ( PropositionSystemLogicAdmissionInput(..), PropositionSystemLogicAdmissionDecision(..)
  , RawPropositionSystemLogicTrigger(..), AdmittedPropositionSystemLogicTriggers(..) )

import QxFx0.Types.Admission.PropositionComparisonPlausibilityAdmission (admitPropositionComparisonPlausibilityTriggers)
import QxFx0.Types.PropositionComparisonPlausibilityAdmission
  ( PropositionComparisonPlausibilityAdmissionInput(..), PropositionComparisonPlausibilityAdmissionDecision(..)
  , RawPropositionComparisonPlausibilityTrigger(..), AdmittedPropositionComparisonPlausibilityTriggers(..) )

import QxFx0.Types.Admission.PropositionDialogueInvitationAdmission (admitPropositionDialogueInvitationTriggers)
import QxFx0.Types.PropositionDialogueInvitationAdmission
  ( PropositionDialogueInvitationAdmissionInput(..), PropositionDialogueInvitationAdmissionDecision(..)
  , RawPropositionDialogueInvitationTrigger(..), AdmittedPropositionDialogueInvitationTriggers(..) )

import QxFx0.Types.Admission.PropositionExploratoryPromptAdmission (admitPropositionExploratoryPromptTriggers)
import QxFx0.Types.PropositionExploratoryPromptAdmission
  ( PropositionExploratoryPromptAdmissionInput(..), PropositionExploratoryPromptAdmissionDecision(..)
  , RawPropositionExploratoryPromptTrigger(..), AdmittedPropositionExploratoryPromptTriggers(..) )

import QxFx0.Types.Admission.PropositionGenerativePromptAdmission (admitPropositionGenerativePromptTriggers)
import QxFx0.Types.PropositionGenerativePromptAdmission
  ( PropositionGenerativePromptAdmissionInput(..), PropositionGenerativePromptAdmissionDecision(..)
  , RawPropositionGenerativePromptTrigger(..), AdmittedPropositionGenerativePromptTriggers(..) )

import QxFx0.Types.Admission.PropositionContactAdmission (admitPropositionContactTriggers)
import qualified QxFx0.Types.PropositionContactAdmission as Contact
  ( PropositionContactAdmissionInput(..), PropositionContactAdmissionDecision(..)
  , RawPropositionContactTrigger(..), AdmittedPropositionContactTriggers(..) )

import QxFx0.Types.Admission.PropositionPhraseDecisionAdmission (admitPropositionPhraseDecisions)
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionPhraseDecisionAdmissionInput(..), PropositionPhraseDecisionAdmissionDecision(..)
  , PropositionFallbackType(..), RawPropositionPhraseDecision(..), AdmittedPropositionPhraseDecisions(..) )

import QxFx0.Core.RouteHintAdmission (admitRouteHint, RouteHintAdmissionInput(..), RouteHintAdmissionDecision(..), AdmittedRouteHint(..), InputRouteHint(..), InputRouteType(..))
import QxFx0.Types.Admission.PropositionAdmission (admitPropositionFrame, PropositionAdmissionInput(..), PropositionAdmissionDecision(..), AdmittedPropositionFrame(..))
import QxFx0.Core.SemanticFrameAdmission (admitSemanticFrameForInput, SemanticFrameAdmissionInput(..), SemanticFrameAdmissionDecision(..), AdmittedSemanticFrame(..))
import QxFx0.Core.SenseVectorAdmission (admitSenseVector, SenseVectorAdmissionInput(..), SenseVectorAdmissionDecision(..), AdmittedSenseVector(..))

import QxFx0.Types (InputPropositionFrame(..), SenseVector(..), SemanticNodeId(..), SenseAxis(..), SenseOperator(..), SensePolarity(..), Register(..), CanonicalMoveFamily(..), IllocutionaryForce(..), ClauseForm(..), SemanticLayer(..), EmotionalTone(..), MeaningAtom(..), AtomTag(..), AtomSet(..))
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Semantic.Input.Model (SemanticTag(..))
import qualified Data.Map.Strict as Map
import qualified Data.Vector as V

import QxFx0.Semantic.MeaningAtoms
  ( RawAtomFindings(..)
  , RawLexicalClusterHits(..), RawClusterHit(..), RawLexicalHit(..)
  , RawLexicalClusterMatches(..)
  , RawLexicalClusterPhraseContainment(..), RawClusterPhraseContainment(..), RawLexicalPhraseContainment(..), LexicalPhraseContainmentClass(..)
  , RawLexicalClusterPhraseDecisions(..), RawClusterPhraseDecision(..), RawLexicalPhraseDecision(..)
  )

import QxFx0.Core.AtomContributionAdmission (admitAtomContributions, AtomContributionAdmissionInput(..), AtomContributionAdmissionDecision(..), AdmittedAtomContributions(..))
import QxFx0.Core.AtomExtractionAdmission (admitAtomAvailability, AtomExtractionAdmissionInput(..), AtomExtractionAdmissionDecision(..), AdmittedAtomAvailability(..))
import QxFx0.Core.AtomFindingAdmission (admitAtomFindings, AtomFindingAdmissionInput(..), AtomFindingAdmissionDecision(..), AdmittedAtomFindings(..))
import QxFx0.Core.LexicalClusterHitAdmission (admitLexicalClusterHits, LexicalClusterHitAdmissionInput(..), LexicalClusterHitAdmissionDecision(..), AdmittedLexicalClusterHits(..))
import QxFx0.Core.LexicalClusterMatchAdmission (admitLexicalClusterMatches, LexicalClusterMatchAdmissionInput(..), LexicalClusterMatchAdmissionDecision(..), AdmittedLexicalClusterMatches(..))
import QxFx0.Core.LexicalClusterPhraseAdmission (admitLexicalClusterPhraseContainment, LexicalClusterPhraseAdmissionInput(..), LexicalClusterPhraseAdmissionDecision(..), AdmittedLexicalClusterPhraseContainment(..))
import QxFx0.Core.LexicalClusterPhraseDecisionAdmission (admitLexicalClusterPhraseDecisions, LexicalClusterPhraseDecisionAdmissionInput(..), LexicalClusterPhraseDecisionAdmissionDecision(..), AdmittedLexicalClusterPhraseDecisions(..))
import QxFx0.Core.StructuralAtomAdmission (admitStructuralAtoms, StructuralAtomAdmissionInput(..), StructuralAtomAdmissionDecision(..), AdmittedStructuralAtoms(..))

-- An authoritative and a non-authoritative truth-contract status.
authoritative :: TruthContractStatus
authoritative = CanonicalSurfacePreserved

nonAuthoritative :: TruthContractStatus
nonAuthoritative = GeneratedArtifactSurface

-- | Generic three-branch equivalence check for a 3-guard/label admission
-- module.  Each module supplies its own constructors/accessors explicitly
-- (no positional shortcuts), so an irregular constructor name or a flipped
-- field cannot hide.  @adm@ is wrapped to take the raw status and a trigger
-- list, returning the (rawEcho, processed, decision) triple as a tuple via
-- the caller's projections.
--
-- We assert all three branches AND the decision constructor on each branch —
-- the constructor-miswiring hazard (the 3 pacDecision* fields share one type).
threeBranchChecks
  :: (Eq admitted, Show admitted)
  => String                              -- ^ module label
  -> (TruthContractStatus -> [raw] -> admitted)  -- ^ wrapped admit fn
  -> (Text -> Bool -> raw)               -- ^ raw trigger builder (label matched)
  -> Text                                -- ^ a safe label for this module
  -> ([raw] -> [raw] -> dec -> admitted) -- ^ admitted ctor
  -> (raw -> raw)                        -- ^ soften (set matched False)
  -> dec -> dec -> dec                   -- ^ AdmitRaw / PreserveAmbiguous / SuppressStrong
  -> [Test]
threeBranchChecks name adm mkRaw safeLabel admittedCtor soften admitRaw preserve suppress =
  let safeMatched   = mkRaw safeLabel True
      unsafeMatched  = mkRaw "zzz_unsafe_label" True
  in
  [ TestLabel (name <> ": authoritative -> AdmitRaw, untouched") $ TestCase $
      assertEqual "authoritative passes raw through unchanged"
        (admittedCtor [unsafeMatched] [unsafeMatched] admitRaw)
        (adm authoritative [unsafeMatched])
  , TestLabel (name <> ": non-auth + all-safe -> PreserveAmbiguous, untouched") $ TestCase $
      assertEqual "all-safe under non-auth is preserved"
        (admittedCtor [safeMatched] [safeMatched] preserve)
        (adm nonAuthoritative [safeMatched])
  , TestLabel (name <> ": non-auth + unsafe -> SuppressStrong, unsafe softened") $ TestCase $
      assertEqual "unsafe matched trigger softened to Matched=False; safe preserved"
        (admittedCtor [safeMatched, unsafeMatched] [safeMatched, soften unsafeMatched] suppress)
        (adm nonAuthoritative [safeMatched, unsafeMatched])
  ]

-- | Generic two-branch equivalence check for a 2-guard admission module
-- (no PreserveAmbiguous branch).  Tests:
--   1. Authoritative → AdmitRaw, triggers untouched
--   2. Non-authoritative → SuppressStrong, all matched triggers softened
twoBranchChecks
  :: (Eq raw, Show raw, Eq dec, Show dec, Eq admitted, Show admitted)
  => String                                     -- ^ module label
  -> (TruthContractStatus -> [raw] -> admitted) -- ^ wrapped admit fn
  -> (Text -> Bool -> raw)                      -- ^ raw trigger builder (label matched)
  -> ([raw] -> [raw] -> dec -> admitted)        -- ^ admitted ctor
  -> (raw -> raw)                               -- ^ soften (set matched False)
  -> dec -> dec                                 -- ^ AdmitRaw / SuppressStrong
  -> [Test]
twoBranchChecks name adm mkRaw admittedCtor soften admitRaw suppress =
  let unsafeMatched = mkRaw "zzz_unsafe" True
  in
  [ TestLabel (name <> ": authoritative -> AdmitRaw, untouched") $ TestCase $
      assertEqual "authoritative passes raw through unchanged"
        (admittedCtor [unsafeMatched] [unsafeMatched] admitRaw)
        (adm authoritative [unsafeMatched])
  , TestLabel (name <> ": non-auth -> SuppressStrong, all softened") $ TestCase $
      assertEqual "non-auth suppresses all matched triggers"
        (admittedCtor [unsafeMatched] [soften unsafeMatched] suppress)
        (adm nonAuthoritative [unsafeMatched])
  ]

-- The 15 batch-converted modules.  Each line wires the module's own
-- constructors/accessors; the irregular ones (Misunderstanding's Pm*,
-- AffectiveSupportProbe's PasprSuppressStrongProbe) are spelled out here.
batchChecks :: [Test]
batchChecks = concat
  [ threeBranchChecks "AffectiveSupportPhrase"
      (\i -> admitPropositionAffectiveSupportPhraseTriggers (PropositionAffectiveSupportPhraseAdmissionInput i))
      RawPropositionAffectiveSupportPhraseTrigger "no_strength"
      AdmittedPropositionAffectiveSupportPhraseTriggers (\t -> t { rptMatched = False })
      PaspadAdmitRaw PaspadPreserveAmbiguous PaspadSuppressStrongTriggers
  , threeBranchChecks "AffectiveSupportProbe"
      (\i -> admitPropositionAffectiveSupportProbeTriggers (PropositionAffectiveSupportProbeAdmissionInput i))
      RawPropositionAffectiveSupportProbeTrigger "question_gate"
      AdmittedPropositionAffectiveSupportProbeTriggers (\t -> t { rpasprMatched = False })
      PasprAdmitRaw PasprPreserveAmbiguous PasprSuppressStrongProbe
  , threeBranchChecks "ConceptKnowledge"
      (\i -> admitPropositionConceptKnowledgeTriggers (PropositionConceptKnowledgeAdmissionInput i))
      RawPropositionConceptKnowledgeTrigger "concept_like_noun_guard"
      AdmittedPropositionConceptKnowledgeTriggers (\t -> t { rpckMatched = False })
      PckdAdmitRaw PckdPreserveAmbiguous PckdSuppressStrongTriggers
  , threeBranchChecks "ContemplativeTopic"
      (\i -> admitPropositionContemplativeTopicTriggers (PropositionContemplativeTopicAdmissionInput i))
      RawPropositionContemplativeTopicTrigger "bare_self_pronoun"
      AdmittedPropositionContemplativeTopicTriggers (\t -> t { rpctMatched = False })
      PpctdAdmitRaw PpctdPreserveAmbiguous PpctdSuppressStrongTriggers
  , threeBranchChecks "Distinction"
      (\i -> admitPropositionDistinctionTriggers (PropositionDistinctionAdmissionInput i))
      RawPropositionDistinctionTrigger "from_token_present"
      AdmittedPropositionDistinctionTriggers (\t -> t { rpdtMatched = False })
      PdadAdmitRaw PdadPreserveAmbiguous PdadSuppressStrongTriggers
  , threeBranchChecks "LocationFormation"
      (\i -> admitPropositionLocationFormationTriggers (PropositionLocationFormationAdmissionInput i))
      RawPropositionLocationFormationTrigger "mental_noun_guard"
      AdmittedPropositionLocationFormationTriggers (\t -> t { rplfMatched = False })
      PlfdAdmitRaw PlfdPreserveAmbiguous PlfdSuppressStrongTriggers
  , threeBranchChecks "Misunderstanding"
      (\i -> admitPropositionMisunderstandingTriggers (PropositionMisunderstandingAdmissionInput i))
      RawPropositionMisunderstandingTrigger "apology_tokens"
      AdmittedPropositionMisunderstandingTriggers (\t -> t { rpmtMatched = False })
      PmAdmitRaw PmPreserveAmbiguous PmSuppressStrongTriggers
  , threeBranchChecks "NextStep"
      (\i -> admitPropositionNextStepTriggers (PropositionNextStepAdmissionInput i))
      RawPropositionNextStepTrigger "direct_text_short"
      AdmittedPropositionNextStepTriggers (\t -> t { rpnstMatched = False })
      PnsdAdmitRaw PnsdPreserveAmbiguous PnsdSuppressStrongTriggers
  , threeBranchChecks "OperationalCause"
      (\i -> admitPropositionOperationalCauseTriggers (PropositionOperationalCauseAdmissionInput i))
      RawPropositionOperationalCauseTrigger "subject_present"
      AdmittedPropositionOperationalCauseTriggers (\t -> t { rpocMatched = False })
      PocdAdmitRaw PocdPreserveAmbiguous PocdSuppressStrongTriggers
  , threeBranchChecks "OperationalStatus"
      (\i -> admitPropositionOperationalStatusTriggers (PropositionOperationalStatusAdmissionInput i))
      RawPropositionOperationalStatusTrigger "subject_present"
      AdmittedPropositionOperationalStatusTriggers (\t -> t { rpostMatched = False })
      PosdAdmitRaw PosdPreserveAmbiguous PosdSuppressStrongTriggers
  , threeBranchChecks "Purpose"
      (\i -> admitPropositionPurposeTriggers (PropositionPurposeAdmissionInput i))
      RawPropositionPurposeTrigger "purpose_subject_guard"
      AdmittedPropositionPurposeTriggers (\t -> t { rpptMatched = False })
      PpadAdmitRaw PpadPreserveAmbiguous PpadSuppressStrongTriggers
  , threeBranchChecks "RepairDirective"
      (\i -> admitPropositionRepairDirectiveTriggers (PropositionRepairDirectiveAdmissionInput i))
      RawPropositionRepairDirectiveTrigger "confused_en"
      AdmittedPropositionRepairDirectiveTriggers (\t -> t { rprdMatched = False })
      PrdadAdmitRaw PrdadPreserveAmbiguous PrdadSuppressStrongTriggers
  , threeBranchChecks "SelfKnowledge"
      (\i -> admitPropositionSelfKnowledgeTriggers (PropositionSelfKnowledgeAdmissionInput i))
      RawPropositionSelfKnowledgeTrigger "single_thought_subject_guard"
      AdmittedPropositionSelfKnowledgeTriggers (\t -> t { rpskMatched = False })
      PskdAdmitRaw PskdPreserveAmbiguous PskdSuppressStrongTriggers
  , threeBranchChecks "SelfState"
      (\i -> admitPropositionSelfStateTriggers (PropositionSelfStateAdmissionInput i))
      RawPropositionSelfStateTrigger "guard_identity"
      AdmittedPropositionSelfStateTriggers (\t -> t { rpssMatched = False })
      PssadAdmitRaw PssadPreserveAmbiguous PssadSuppressStrongTriggers
  , threeBranchChecks "SystemLogic"
      (\i -> admitPropositionSystemLogicTriggers (PropositionSystemLogicAdmissionInput i))
      RawPropositionSystemLogicTrigger "subject_present"
      AdmittedPropositionSystemLogicTriggers (\t -> t { rpslMatched = False })
      PsldAdmitRaw PsldPreserveAmbiguous PsldSuppressStrongTriggers
  , threeBranchChecks "Contact"
      (\i -> admitPropositionContactTriggers (Contact.PropositionContactAdmissionInput i))
      Contact.RawPropositionContactTrigger "farewell"
      Contact.AdmittedPropositionContactTriggers
      (\t -> Contact.RawPropositionContactTrigger (Contact.rpctLabel t) False)
      Contact.PcadAdmitRaw Contact.PcadPreserveAmbiguous Contact.PcadSuppressStrongTriggers
  ]

-- ---------------------------------------------------------------------------
-- Confront: safe labels = ["contradiction_noun", "doubt_marker"]
-- ---------------------------------------------------------------------------

confrontTests :: [Test]
confrontTests =
  let safeMatched   = RawPropositionConfrontTrigger "contradiction_noun" True
      unsafeMatched = RawPropositionConfrontTrigger "aggressive_phrase" True
      run i ts = admitPropositionConfrontTriggers (PropositionConfrontAdmissionInput i) ts
  in
  [ TestLabel "Confront: authoritative -> AdmitRaw, triggers untouched" $ TestCase $
      assertEqual "authoritative passes raw through unchanged"
        (AdmittedPropositionConfrontTriggers [unsafeMatched] [unsafeMatched] PcondAdmitRaw)
        (run authoritative [unsafeMatched])
  , TestLabel "Confront: non-auth + all-safe -> PreserveAmbiguous, untouched" $ TestCase $
      assertEqual "all-safe under non-auth is preserved"
        (AdmittedPropositionConfrontTriggers [safeMatched] [safeMatched] PcondPreserveAmbiguous)
        (run nonAuthoritative [safeMatched])
  , TestLabel "Confront: non-auth + unsafe -> SuppressStrong, unsafe softened" $ TestCase $
      assertEqual "unsafe matched trigger is softened to Matched=False; safe preserved"
        (AdmittedPropositionConfrontTriggers
           [safeMatched, unsafeMatched]
           [safeMatched, unsafeMatched { rpconfMatched = False }]
           PcondSuppressStrongTriggers)
        (run nonAuthoritative [safeMatched, unsafeMatched])
  ]

-- ---------------------------------------------------------------------------
-- WorldCause: safe labels = ["world_noun_guard"]
-- ---------------------------------------------------------------------------

worldCauseTests :: [Test]
worldCauseTests =
  let safeMatched   = RawPropositionWorldCauseTrigger "world_noun_guard" True
      unsafeMatched = RawPropositionWorldCauseTrigger "speculative_cause" True
      run i ts = admitPropositionWorldCauseTriggers (PropositionWorldCauseAdmissionInput i) ts
  in
  [ TestLabel "WorldCause: authoritative -> AdmitRaw, triggers untouched" $ TestCase $
      assertEqual "authoritative passes raw through unchanged"
        (AdmittedPropositionWorldCauseTriggers [unsafeMatched] [unsafeMatched] PwcAdmitRaw)
        (run authoritative [unsafeMatched])
  , TestLabel "WorldCause: non-auth + all-safe -> PreserveAmbiguous, untouched" $ TestCase $
      assertEqual "all-safe under non-auth is preserved"
        (AdmittedPropositionWorldCauseTriggers [safeMatched] [safeMatched] PwcPreserveAmbiguous)
        (run nonAuthoritative [safeMatched])
  , TestLabel "WorldCause: non-auth + unsafe -> SuppressStrong, unsafe softened" $ TestCase $
      assertEqual "unsafe matched trigger is softened to Matched=False; safe preserved"
        (AdmittedPropositionWorldCauseTriggers
           [safeMatched, unsafeMatched]
           [safeMatched, unsafeMatched { rpwcMatched = False }]
           PwcSuppressStrongTriggers)
        (run nonAuthoritative [safeMatched, unsafeMatched])
  ]

-- | Two-guard batch checks: no PreserveAmbiguous branch.
twoGuardChecks :: [Test]
twoGuardChecks = concat
  [ twoBranchChecks "ComparisonPlausibility"
      (\i -> admitPropositionComparisonPlausibilityTriggers (PropositionComparisonPlausibilityAdmissionInput i))
      RawPropositionComparisonPlausibilityTrigger
      AdmittedPropositionComparisonPlausibilityTriggers (\t -> t { rpcppMatched = False })
      PcpadAdmitRaw PcpadSuppressStrongTriggers
  , twoBranchChecks "DialogueInvitation"
      (\i -> admitPropositionDialogueInvitationTriggers (PropositionDialogueInvitationAdmissionInput i))
      RawPropositionDialogueInvitationTrigger
      AdmittedPropositionDialogueInvitationTriggers (\t -> t { rpdiMatched = False })
      PpdiadAdmitRaw PpdiadSuppressStrongTriggers
  , twoBranchChecks "ExploratoryPrompt"
      (\i -> admitPropositionExploratoryPromptTriggers (PropositionExploratoryPromptAdmissionInput i))
      RawPropositionExploratoryPromptTrigger
      AdmittedPropositionExploratoryPromptTriggers (\t -> t { rpeptMatched = False })
      PpeptdAdmitRaw PpeptdSuppressStrongTriggers
  , twoBranchChecks "GenerativePrompt"
      (\i -> admitPropositionGenerativePromptTriggers (PropositionGenerativePromptAdmissionInput i))
      RawPropositionGenerativePromptTrigger
      AdmittedPropositionGenerativePromptTriggers (\t -> t { rpgpMatched = False })
      PpgpdAdmitRaw PpgpdSuppressStrongTriggers
  ]

-- ---------------------------------------------------------------------------
-- PhraseDecision: labels are PropositionFallbackType, not Text
--   safe = [PfContactSignal, PfAnchorSignal, PfClarifyQ, PfDeepenQ]
--   unsafe = any other PropositionFallbackType (e.g. PfDefinitionalQ)
-- ---------------------------------------------------------------------------

phraseDecisionTests :: [Test]
phraseDecisionTests =
  let safeMatched   = RawPropositionPhraseDecision PfContactSignal "hello" True
      unsafeMatched = RawPropositionPhraseDecision PfDefinitionalQ "what is" True
      run i ts = admitPropositionPhraseDecisions (PropositionPhraseDecisionAdmissionInput i) ts
  in
  [ TestLabel "PhraseDecision: authoritative -> AdmitRaw, untouched" $ TestCase $
      assertEqual "authoritative passes raw through unchanged"
        (AdmittedPropositionPhraseDecisions [unsafeMatched] [unsafeMatched] PpddAdmitRaw)
        (run authoritative [unsafeMatched])
  , TestLabel "PhraseDecision: non-auth + all-safe -> PreserveAmbiguous, untouched" $ TestCase $
      assertEqual "all-safe under non-auth is preserved"
        (AdmittedPropositionPhraseDecisions [safeMatched] [safeMatched] PpddPreserveAmbiguous)
        (run nonAuthoritative [safeMatched])
  , TestLabel "PhraseDecision: non-auth + unsafe -> SuppressStrong, unsafe softened" $ TestCase $
      assertEqual "unsafe matched decision is softened to Matched=False; safe preserved"
        (AdmittedPropositionPhraseDecisions
           [safeMatched, unsafeMatched]
           [safeMatched, unsafeMatched { rppdMatched = False }]
           PpddSuppressStrongDecisions)
        (run nonAuthoritative [safeMatched, unsafeMatched])
  ]

-- ---------------------------------------------------------------------------
-- RouteHint: single-item admission, 4 branches
--   in-scope: irhTag in ["self_state","opinion_question"] + pronouns
--   weak: irhConfidence <= 0.5 OR tag in ["unknown","misunderstanding",...]
-- ---------------------------------------------------------------------------

routeHintTests :: [Test]
routeHintTests =
  let strongHint = InputRouteHint RouteTypeDefine TagSelfState "" 1.0 1.0 1.0 1.0 [] 1.0
      weakHint   = InputRouteHint RouteTypeDefine TagSelfState "" 1.0 1.0 1.0 1.0 [] 0.3
      run i h = admitRouteHint (RouteHintAdmissionInput i False "я") h
  in
  [ TestLabel "RouteHint: auth + in-scope + strong -> AdmitRaw" $ TestCase $
      assertEqual "auth+scope+strong -> AdmitRaw, hint untouched"
        (AdmittedRouteHint strongHint RhdAdmitRaw)
        (run authoritative strongHint)
  , TestLabel "RouteHint: non-auth + in-scope + strong -> LowerConfidence" $ TestCase $
      assertEqual "non-auth+scope+strong -> LowerConfidence, scores clamped"
        (AdmittedRouteHint
          (InputRouteHint RouteTypeDefine TagSelfState "" 0.5 0.5 0.5 0.5
            ["route_hint_admission=non_authoritative"] 0.5)
          RhdLowerConfidence)
        (run nonAuthoritative strongHint)
  , TestLabel "RouteHint: non-auth + in-scope + weak -> PreserveAmbiguous" $ TestCase $
      assertEqual "non-auth+scope+weak -> PreserveAmbiguous, evidence tagged"
        (AdmittedRouteHint
          (InputRouteHint RouteTypeDefine TagSelfState "" 1.0 1.0 1.0 1.0
            ["route_hint_admission=non_authoritative"] 0.3)
          RhdPreserveAmbiguous)
        (run nonAuthoritative weakHint)
  ]

-- ---------------------------------------------------------------------------
-- PropositionAdmission: single-frame admission, 4 branches
--   in-scope: SelfStateQ + pronouns in rawText
--   weak: confidence <= 0.5 OR propositionType in weak list
-- ---------------------------------------------------------------------------

propositionAdmissionTests :: [Test]
propositionAdmissionTests =
  let strongFrame :: InputPropositionFrame
      strongFrame = InputPropositionFrame
        { ipfRawText = "я"
        , ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = CMGround, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 1.0, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      weakFrame = strongFrame { ipfConfidence = 0.3 }
      softFrame = strongFrame { ipfConfidence = 0.5
                              , ipfSemanticEvidence = ["proposition_admission=non_authoritative"] }
      markFrame = strongFrame { ipfConfidence = 0.3
                              , ipfSemanticEvidence = ["proposition_admission=non_authoritative"] }
      run i f = admitPropositionFrame (PropositionAdmissionInput i False) f
  in
  [ TestLabel "PropositionAdmission: auth + in-scope + strong -> AdmitRaw" $ TestCase $
      assertEqual "auth+scope+strong -> AdmitRaw, frame untouched"
        (AdmittedPropositionFrame strongFrame PadAdmitRaw)
        (run authoritative strongFrame)
  , TestLabel "PropositionAdmission: non-auth + in-scope + strong -> LowerConfidence" $ TestCase $
      assertEqual "non-auth+scope+strong -> LowerConfidence, confidence clamped"
        (AdmittedPropositionFrame softFrame PadLowerConfidence)
        (run nonAuthoritative strongFrame)
  , TestLabel "PropositionAdmission: non-auth + in-scope + weak -> PreserveAmbiguous" $ TestCase $
      assertEqual "non-auth+scope+weak -> PreserveAmbiguous, evidence tagged"
        (AdmittedPropositionFrame markFrame PadPreserveAmbiguous)
        (run nonAuthoritative weakFrame)
  ]

-- ---------------------------------------------------------------------------
-- SemanticFrameAdmission: single-frame admission, 4 branches
--   in-scope: pronouns in rawText
--   weak: confidence <= 0.5 OR ambiguity level in ["medium","high","constitution_softened"]
-- ---------------------------------------------------------------------------

semanticFrameAdmissionTests :: [Test]
semanticFrameAdmissionTests =
  let run i = admitSemanticFrameForInput (SemanticFrameAdmissionInput i False) "я"
  in
  [ TestLabel "SemanticFrameAdmission: auth + in-scope + strong -> AdmitRaw" $ TestCase $
      assertEqual "auth+scope+strong -> decision SfdAdmitRaw" SfdAdmitRaw (asfDecision $ run authoritative)
  , TestLabel "SemanticFrameAdmission: non-auth + in-scope + strong -> LowerConfidence" $ TestCase $
      assertEqual "non-auth+scope+strong -> decision SfdLowerConfidence" SfdLowerConfidence (asfDecision $ run nonAuthoritative)
  ]

-- ---------------------------------------------------------------------------
-- SenseVectorAdmission: single-vector admission, 4 branches
--   in-scope: agent /= Nothing OR target /= Nothing OR AxSelf in axes
--   weak: confidence <= 0.55 OR operators in [[OpClarify],[OpRepair],[OpGround]]
-- ---------------------------------------------------------------------------

senseVectorAdmissionTests :: [Test]
senseVectorAdmissionTests =
  let strongVec :: SenseVector
      strongVec = SenseVector
        { svAnchor = SemanticNodeId ""
        , svLexicalFamily = Nothing, svEvidenceNodes = []
        , svAxes = Map.fromList [(AxSelf, 1.0)], svOperators = [OpDefine]
        , svPolarity = SpAffirm, svAgent = Nothing, svTarget = Nothing
        , svConfidence = 1.0
        }
      weakVec = strongVec { svOperators = [OpClarify] }
      softVec = SenseVector
        { svAnchor = SemanticNodeId ""
        , svLexicalFamily = Nothing, svEvidenceNodes = []
        , svAxes = Map.fromList [(AxSelf, 1.0)], svOperators = [OpClarify]
        , svPolarity = SpAffirm, svAgent = Nothing, svTarget = Nothing
        , svConfidence = 0.55
        }
      run i v = admitSenseVector (SenseVectorAdmissionInput i False) v
  in
  [ TestLabel "SenseVectorAdmission: auth + in-scope + strong -> AdmitRaw" $ TestCase $
      assertEqual "auth+scope+strong -> AdmitRaw, vector untouched"
        (AdmittedSenseVector strongVec SvdAdmitRaw)
        (run authoritative strongVec)
  , TestLabel "SenseVectorAdmission: non-auth + in-scope + strong -> DampenClarify" $ TestCase $
      assertEqual "non-auth+scope+strong -> DampenClarify, vector softened"
        (AdmittedSenseVector softVec SvdDampenClarify)
        (run nonAuthoritative strongVec)
  , TestLabel "SenseVectorAdmission: non-auth + in-scope + weak -> PreserveAmbiguous" $ TestCase $
      assertEqual "non-auth+scope+weak -> PreserveAmbiguous, vector unchanged"
        (AdmittedSenseVector weakVec SvdPreserveAmbiguous)
        (run nonAuthoritative weakVec)
  ]

-- ---------------------------------------------------------------------------
-- Pattern C (family→CMClarify admission modules)
-- ---------------------------------------------------------------------------

earlyFamilyAdmissionTests :: [Test]
earlyFamilyAdmissionTests =
  let strongFamily = CMGround
      weakFamily   = CMClarify
      baseFrame :: InputPropositionFrame
      baseFrame = InputPropositionFrame
        { ipfRawText = "я", ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = strongFamily, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 0.5, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      outOfScopeFrame = baseFrame { ipfPropositionType = PlainAssert }
      run input family frame = admitEarlyFamilyRecommendation input family frame
  in
  [ TestLabel "EarlyFamily: out-of-scope -> EfdAdmitRaw, family unchanged" $ TestCase $
      assertEqual "out-of-scope reverts to AdmitRaw"
        (AdmittedEarlyFamily strongFamily EfdAdmitRaw)
        (run (EarlyFamilyAdmissionInput authoritative False) strongFamily outOfScopeFrame)
  , TestLabel "EarlyFamily: non-auth + in-scope + strong -> EfdCapClarify, family→CMClarify" $ TestCase $
      assertEqual "non-auth+scope+strong -> CapClarify"
        (AdmittedEarlyFamily CMClarify EfdCapClarify)
        (run (EarlyFamilyAdmissionInput nonAuthoritative False) strongFamily baseFrame)
  , TestLabel "EarlyFamily: non-auth + in-scope + weak -> EfdPreserveAmbiguous, family unchanged" $ TestCase $
      assertEqual "non-auth+scope+weak -> PreserveAmbiguous"
        (AdmittedEarlyFamily weakFamily EfdPreserveAmbiguous)
        (run (EarlyFamilyAdmissionInput nonAuthoritative False) weakFamily baseFrame)
  ]

familyAdmissionTests :: [Test]
familyAdmissionTests =
  let strongFamily = CMGround
      weakFamily   = CMClarify
      baseFrame :: InputPropositionFrame
      baseFrame = InputPropositionFrame
        { ipfRawText = "я", ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = strongFamily, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 0.5, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      outOfScopeFrame = baseFrame { ipfPropositionType = PlainAssert }
      nonConatusVerdict = SelfVerdict
        { svSalience = Salience 0.0 1.0 DrivenByDefault
        , svVerdict = PreferFormal 0.0
        }
      conatusVerdict = SelfVerdict
        { svSalience = Salience 0.0 1.0 DrivenByConatusGate
        , svVerdict = PreferFormal 0.0
        }
      run input family frame = admitFamilyCrystallization input family frame
  in
  [ TestLabel "Family: out-of-scope -> FadAdmitRaw, family unchanged" $ TestCase $
      assertEqual "out-of-scope reverts to AdmitRaw"
        (AdmittedFamily strongFamily FadAdmitRaw)
        (run (FamilyAdmissionInput authoritative nonConatusVerdict) strongFamily outOfScopeFrame)
  , TestLabel "Family: non-auth + in-scope + strong -> FadCapClarify, family→CMClarify" $ TestCase $
      assertEqual "non-auth+scope+strong -> CapClarify"
        (AdmittedFamily CMClarify FadCapClarify)
        (run (FamilyAdmissionInput nonAuthoritative nonConatusVerdict) strongFamily baseFrame)
  , TestLabel "Family: non-auth + in-scope + weak -> FadPreserveAmbiguous, family unchanged" $ TestCase $
      assertEqual "non-auth+scope+weak -> PreserveAmbiguous"
        (AdmittedFamily weakFamily FadPreserveAmbiguous)
        (run (FamilyAdmissionInput nonAuthoritative nonConatusVerdict) weakFamily baseFrame)
  , TestLabel "Family: conatus + in-scope + strong -> FadCapClarify" $ TestCase $
      assertEqual "conatus+scope+strong -> CapClarify"
        (AdmittedFamily CMClarify FadCapClarify)
        (run (FamilyAdmissionInput authoritative conatusVerdict) strongFamily baseFrame)
  ]

semanticLogicAdmissionTests :: [Test]
semanticLogicAdmissionTests =
  let baseFrame :: InputPropositionFrame
      baseFrame = InputPropositionFrame
        { ipfRawText = "я", ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = CMGround, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 0.5, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      strongRanked = (CMDeepen, 1.0)
      weakRanked   = (CMClarify, 1.0)
      run input rs = admitSemanticLogicWeighting input rs
      nonAuthInput = SemanticLogicAdmissionInput nonAuthoritative False baseFrame
  in
  [ TestLabel "SemanticLogic: empty -> SldAdmitRaw, both lists empty" $ TestCase $
      assertEqual "empty rawFamilies yields AdmitRaw"
        (AdmittedSemanticLogic [] [] SldAdmitRaw)
        (run nonAuthInput [])
  , TestLabel "SemanticLogic: non-auth + strong -> SldCapClarify, first→CMClarify" $ TestCase $
      assertEqual "non-auth+strong first -> CapClarify"
        (AdmittedSemanticLogic [strongRanked] [(CMClarify, 1.0)] SldCapClarify)
        (run nonAuthInput [strongRanked])
  , TestLabel "SemanticLogic: non-auth + weak first -> SldPreserveAmbiguous, unchanged" $ TestCase $
      assertEqual "non-auth+weak first -> PreserveAmbiguous"
        (AdmittedSemanticLogic [weakRanked] [weakRanked] SldPreserveAmbiguous)
        (run nonAuthInput [weakRanked])
  ]

semanticContributionAdmissionTests :: [Test]
semanticContributionAdmissionTests =
  let baseFrame :: InputPropositionFrame
      baseFrame = InputPropositionFrame
        { ipfRawText = "я", ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = CMGround, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 0.5, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      outOfScopeFrame = baseFrame { ipfPropositionType = PlainAssert }
      strongRanked = (CMDeepen, 1.0)
      weakRanked   = (CMClarify, 1.0)
      nonAuthInput    frame = SemanticContributionAdmissionInput nonAuthoritative False frame
      authOutOfScope         = SemanticContributionAdmissionInput authoritative False outOfScopeFrame
  in
  [ TestLabel "SemanticContribution: out-of-scope -> ScdAdmitRaw, unchanged" $ TestCase $
      assertEqual "out-of-scope -> AdmitRaw"
        (AdmittedSemanticContributions [strongRanked] [strongRanked] ScdAdmitRaw)
        (admitSemanticContributions authOutOfScope [strongRanked])
  , TestLabel "SemanticContribution: non-auth + mixed -> ScdCapClarify, strong softened" $ TestCase $
      assertEqual "non-auth+mixed -> CapClarify, strong softened"
        (AdmittedSemanticContributions [weakRanked, strongRanked] [weakRanked, (CMClarify, 1.0)] ScdCapClarify)
        (admitSemanticContributions (nonAuthInput baseFrame) [weakRanked, strongRanked])
  , TestLabel "SemanticContribution: non-auth + all weak -> ScdPreserveAmbiguous, unchanged" $ TestCase $
      assertEqual "non-auth+all weak -> PreserveAmbiguous"
        (AdmittedSemanticContributions [weakRanked] [weakRanked] ScdPreserveAmbiguous)
        (admitSemanticContributions (nonAuthInput baseFrame) [weakRanked])
  ]

interpretationAdmissionTests :: [Test]
interpretationAdmissionTests =
  let strongFamily = CMGround
      baseFrame :: InputPropositionFrame
      baseFrame = InputPropositionFrame
        { ipfRawText = "я", ipfPropositionType = SelfStateQ
        , ipfFocusEntity = "", ipfFocusNominative = ""
        , ipfSemanticSubject = "", ipfSemanticTarget = ""
        , ipfSemanticCandidates = [], ipfSemanticEvidence = []
        , ipfCanonicalFamily = strongFamily, ipfIllocutionaryForce = IFAsk
        , ipfClauseForm = Declarative, ipfSemanticLayer = ContentLayer
        , ipfKeyPhrases = [], ipfEmotionalTone = ToneNeutral
        , ipfConfidence = 0.5, ipfIsQuestion = False, ipfIsNegated = False
        , ipfRegisterHint = Neutral
        }
      highConfFrame = baseFrame { ipfConfidence = 0.8 }
      clarifyFrame family evidence =
        baseFrame { ipfCanonicalFamily = CMClarify, ipfPropositionType = ClarifyQ
                  , ipfSemanticEvidence = evidence }
      run input family frame = admitInterpretationCandidate input family frame
  in
  [ TestLabel "Interpretation: auth + high confidence -> IadAdmitRaw" $ TestCase $
      assertEqual "auth+high conf -> AdmitRaw"
        (AdmittedInterpretation strongFamily highConfFrame IadAdmitRaw)
        (run (InterpretationAdmissionInput authoritative False) strongFamily highConfFrame)
  , TestLabel "Interpretation: conatus + low conf + not weak -> IadFallbackClarify" $ TestCase $
      assertEqual "conatus+low+strong -> FallbackClarify"
        (AdmittedInterpretation CMClarify
           (clarifyFrame CMClarify ["interpretation_admission=conatus_gate"])
           IadFallbackClarify)
        (run (InterpretationAdmissionInput authoritative True) strongFamily baseFrame)
  , TestLabel "Interpretation: non-auth + low conf + not weak -> IadCapClarify" $ TestCase $
      assertEqual "non-auth+low+strong -> CapClarify"
        (AdmittedInterpretation CMClarify
           (clarifyFrame CMClarify ["interpretation_admission=non_authoritative"])
           IadCapClarify)
        (run (InterpretationAdmissionInput nonAuthoritative False) strongFamily baseFrame)
  ]

-- ---------------------------------------------------------------------------
-- Pattern D (Atom/Lexical/Structural admission modules)
-- ---------------------------------------------------------------------------

atomContributionTests :: [Test]
atomContributionTests =
  let safeAtom = MeaningAtom "s" (Exhaustion "e") V.empty
      unsafeAtom = MeaningAtom "u" (Searching "s") V.empty
      safeSet = AtomSet { asAtoms = [safeAtom], asLoad = 0.5, asRegister = Neutral }
      mixedSet = AtomSet { asAtoms = [safeAtom, unsafeAtom], asLoad = 0.5, asRegister = Neutral }
  in
  [ TestLabel "AtomContribution: auth -> AcdAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw, pass-through"
        (AdmittedAtomContributions mixedSet [safeAtom, unsafeAtom] AcdAdmitRaw)
        (admitAtomContributions (AtomContributionAdmissionInput authoritative) mixedSet)
  , TestLabel "AtomContribution: non-auth + all safe -> AcdPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedAtomContributions safeSet [safeAtom] AcdPreserveAmbiguous)
        (admitAtomContributions (AtomContributionAdmissionInput nonAuthoritative) safeSet)
  , TestLabel "AtomContribution: non-auth + mixed -> AcdCapWeakProfile" $ TestCase $
      assertEqual "mixed -> CapWeakProfile, strong filtered"
        (AdmittedAtomContributions mixedSet [safeAtom] AcdCapWeakProfile)
        (admitAtomContributions (AtomContributionAdmissionInput nonAuthoritative) mixedSet)
  ]

atomExtractionTests :: [Test]
atomExtractionTests =
  let safeAtom = MeaningAtom "s" (Exhaustion "e") V.empty
      unsafeAtom = MeaningAtom "u" (Searching "s") V.empty
      safeSet = AtomSet { asAtoms = [safeAtom], asLoad = 0.5, asRegister = Neutral }
      mixedSet = AtomSet { asAtoms = [safeAtom, unsafeAtom], asLoad = 0.5, asRegister = Neutral }
  in
  [ TestLabel "AtomExtraction: auth -> AedAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedAtomAvailability mixedSet [safeAtom, unsafeAtom] AedAdmitRaw)
        (admitAtomAvailability (AtomExtractionAdmissionInput authoritative) mixedSet)
  , TestLabel "AtomExtraction: non-auth + all safe -> AedPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedAtomAvailability safeSet [safeAtom] AedPreserveAmbiguous)
        (admitAtomAvailability (AtomExtractionAdmissionInput nonAuthoritative) safeSet)
  , TestLabel "AtomExtraction: non-auth + mixed -> AedSuppressStrongFindings" $ TestCase $
      assertEqual "mixed -> SuppressStrongFindings, unsafe filtered"
        (AdmittedAtomAvailability mixedSet [safeAtom] AedSuppressStrongFindings)
        (admitAtomAvailability (AtomExtractionAdmissionInput nonAuthoritative) mixedSet)
  ]

atomFindingTests :: [Test]
atomFindingTests =
  let safeAtom = MeaningAtom "s" (Exhaustion "e") V.empty
      unsafeAtom = MeaningAtom "u" (Searching "s") V.empty
      safeOnly = RawAtomFindings [safeAtom] [safeAtom] []
      mixed   = RawAtomFindings [safeAtom, unsafeAtom] [safeAtom, unsafeAtom] []
      expectedMixed = RawAtomFindings [safeAtom] [safeAtom] []
  in
  [ TestLabel "AtomFinding: auth -> AfdAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedAtomFindings mixed mixed AfdAdmitRaw)
        (admitAtomFindings (AtomFindingAdmissionInput authoritative) mixed)
  , TestLabel "AtomFinding: non-auth + all safe -> AfdPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedAtomFindings safeOnly safeOnly AfdPreserveAmbiguous)
        (admitAtomFindings (AtomFindingAdmissionInput nonAuthoritative) safeOnly)
  , TestLabel "AtomFinding: non-auth + mixed -> AfdSuppressStrongFindings" $ TestCase $
      assertEqual "mixed -> SuppressStrongFindings"
        (AdmittedAtomFindings mixed expectedMixed AfdSuppressStrongFindings)
        (admitAtomFindings (AtomFindingAdmissionInput nonAuthoritative) mixed)
  ]

structuralAtomTests :: [Test]
structuralAtomTests =
  -- StructuralAtom safe tags: only Verification, Anchoring, NeedContact (NOT Exhaustion!)
  let safeAtom   = MeaningAtom "v" (Verification "v") V.empty
      unsafeAtom = MeaningAtom "e" (Exhaustion "e") V.empty
      safeOnly = RawAtomFindings [] [] [safeAtom]
      mixed   = RawAtomFindings [] [] [safeAtom, unsafeAtom]
      cleared = RawAtomFindings [] [] []
  in
  [ TestLabel "StructuralAtom: auth -> SadAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedStructuralAtoms mixed mixed SadAdmitRaw)
        (admitStructuralAtoms (StructuralAtomAdmissionInput authoritative) mixed)
  , TestLabel "StructuralAtom: non-auth + all safe -> SadPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedStructuralAtoms safeOnly safeOnly SadPreserveAmbiguous)
        (admitStructuralAtoms (StructuralAtomAdmissionInput nonAuthoritative) safeOnly)
  , TestLabel "StructuralAtom: non-auth + mixed -> SadSuppressSearching" $ TestCase $
      assertEqual "mixed -> SuppressSearching, structural atoms cleared"
        (AdmittedStructuralAtoms mixed cleared SadSuppressSearching)
        (admitStructuralAtoms (StructuralAtomAdmissionInput nonAuthoritative) mixed)
  ]

lexicalClusterHitTests :: [Test]
lexicalClusterHitTests =
  let safeHit  = RawClusterHit (Exhaustion "e") ["safe"]
      unsafeHit = RawClusterHit (Searching "s") ["unsafe"]
      safeLex  = RawLexicalHit (Exhaustion "e") ["safe"]
      unsafeLex = RawLexicalHit (Searching "s") ["unsafe"]
      safeInput = RawLexicalClusterHits "" [safeHit] [safeLex]
      mixedInput = RawLexicalClusterHits "" [safeHit, unsafeHit] [safeLex, unsafeLex]
      expectedMixed = RawLexicalClusterHits "" [safeHit] [safeLex]
  in
  [ TestLabel "LexicalHit: auth -> LchdAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedLexicalClusterHits mixedInput mixedInput LchdAdmitRaw)
        (admitLexicalClusterHits (LexicalClusterHitAdmissionInput authoritative) mixedInput)
  , TestLabel "LexicalHit: non-auth + all safe -> LchdPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedLexicalClusterHits safeInput safeInput LchdPreserveAmbiguous)
        (admitLexicalClusterHits (LexicalClusterHitAdmissionInput nonAuthoritative) safeInput)
  , TestLabel "LexicalHit: non-auth + mixed -> LchdSuppressStrongHits" $ TestCase $
      assertEqual "mixed -> SuppressStrongHits"
        (AdmittedLexicalClusterHits mixedInput expectedMixed LchdSuppressStrongHits)
        (admitLexicalClusterHits (LexicalClusterHitAdmissionInput nonAuthoritative) mixedInput)
  ]

lexicalClusterMatchTests :: [Test]
lexicalClusterMatchTests =
  let safeAtom   = MeaningAtom "s" (Exhaustion "e") V.empty
      unsafeAtom = MeaningAtom "u" (Searching "s") V.empty
      safeInput = RawLexicalClusterMatches [safeAtom] [safeAtom]
      mixedInput = RawLexicalClusterMatches [safeAtom, unsafeAtom] [safeAtom, unsafeAtom]
      expectedMixed = RawLexicalClusterMatches [safeAtom] [safeAtom]
  in
  [ TestLabel "LexicalMatch: auth -> LcdAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedLexicalClusterMatches mixedInput mixedInput LcdAdmitRaw)
        (admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput authoritative) mixedInput)
  , TestLabel "LexicalMatch: non-auth + all safe -> LcdPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedLexicalClusterMatches safeInput safeInput LcdPreserveAmbiguous)
        (admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput nonAuthoritative) safeInput)
  , TestLabel "LexicalMatch: non-auth + mixed -> LcdSuppressStrongMatches" $ TestCase $
      assertEqual "mixed -> SuppressStrongMatches"
        (AdmittedLexicalClusterMatches mixedInput expectedMixed LcdSuppressStrongMatches)
        (admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput nonAuthoritative) mixedInput)
  ]

lexicalClusterPhraseTests :: [Test]
lexicalClusterPhraseTests =
  let safeLexical = RawLexicalPhraseContainment LpcExhaustion ["safe"]
      unsafeLexical = RawLexicalPhraseContainment LpcNeedMeaning ["unsafe"]
      safeInput = RawLexicalClusterPhraseContainment "" [] [safeLexical]
      mixedInput = RawLexicalClusterPhraseContainment "" [] [safeLexical, unsafeLexical]
      expectedMixed = RawLexicalClusterPhraseContainment "" [] [safeLexical]
  in
  [ TestLabel "LexicalPhrase: auth -> LpdAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedLexicalClusterPhraseContainment mixedInput mixedInput LpdAdmitRaw)
        (admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput authoritative) mixedInput)
  , TestLabel "LexicalPhrase: non-auth + all safe -> LpdPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedLexicalClusterPhraseContainment safeInput safeInput LpdPreserveAmbiguous)
        (admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput nonAuthoritative) safeInput)
  , TestLabel "LexicalPhrase: non-auth + mixed -> LpdSuppressStrongContainment" $ TestCase $
      assertEqual "mixed -> SuppressStrongContainment"
        (AdmittedLexicalClusterPhraseContainment mixedInput expectedMixed LpdSuppressStrongContainment)
        (admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput nonAuthoritative) mixedInput)
  ]

lexicalClusterPhraseDecisionTests :: [Test]
lexicalClusterPhraseDecisionTests =
  -- Safe = unmatched (matched=False) or matched with safe tag
  let safeCluster = RawClusterPhraseDecision "exhaustion" "safe" False
      unsafeCluster = RawClusterPhraseDecision "need_meaning" "unsafe" True
      safeLexical = RawLexicalPhraseDecision LpcExhaustion "safe" False
      unsafeLexical = RawLexicalPhraseDecision LpcNeedMeaning "unsafe" True
      softenedUnsafeCluster = unsafeCluster { rcpdMatched = False }
      softenedUnsafeLexical = unsafeLexical { rlpdMatched = False }
      safeInput = RawLexicalClusterPhraseDecisions "" [safeCluster] [safeLexical]
      mixedInput = RawLexicalClusterPhraseDecisions "" [safeCluster, unsafeCluster] [safeLexical, unsafeLexical]
      expectedMixed = RawLexicalClusterPhraseDecisions "" [safeCluster, softenedUnsafeCluster] [safeLexical, softenedUnsafeLexical]
  in
  [ TestLabel "LexicalPhraseDecision: auth -> LcpddAdmitRaw" $ TestCase $
      assertEqual "auth -> AdmitRaw"
        (AdmittedLexicalClusterPhraseDecisions mixedInput mixedInput LcpddAdmitRaw)
        (admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput authoritative) mixedInput)
  , TestLabel "LexicalPhraseDecision: non-auth + all safe -> LcpddPreserveAmbiguous" $ TestCase $
      assertEqual "all safe -> PreserveAmbiguous"
        (AdmittedLexicalClusterPhraseDecisions safeInput safeInput LcpddPreserveAmbiguous)
        (admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput nonAuthoritative) safeInput)
  , TestLabel "LexicalPhraseDecision: non-auth + mixed -> LcpddSuppressStrongDecisions" $ TestCase $
      assertEqual "mixed -> SuppressStrongDecisions, unsafe softened"
        (AdmittedLexicalClusterPhraseDecisions mixedInput expectedMixed LcpddSuppressStrongDecisions)
        (admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput nonAuthoritative) mixedInput)
  ]

admissionEquivalenceTests :: [Test]
admissionEquivalenceTests = confrontTests ++ worldCauseTests ++ batchChecks ++ twoGuardChecks ++ phraseDecisionTests ++ routeHintTests ++ propositionAdmissionTests ++ semanticFrameAdmissionTests ++ senseVectorAdmissionTests ++ earlyFamilyAdmissionTests ++ familyAdmissionTests ++ semanticLogicAdmissionTests ++ semanticContributionAdmissionTests ++ interpretationAdmissionTests ++ atomContributionTests ++ atomExtractionTests ++ atomFindingTests ++ structuralAtomTests ++ lexicalClusterHitTests ++ lexicalClusterMatchTests ++ lexicalClusterPhraseTests ++ lexicalClusterPhraseDecisionTests
