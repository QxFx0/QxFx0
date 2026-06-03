{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-| Turn pipeline effect protocol and deterministic prepare-stage planning inputs. -}
module QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  , PrepareStatic(..)
  , PrepareEffectRequest(..)
  , PrepareEffectPlan(..)
  , buildPrepareEffectPlan
  ) where

import QxFx0.Types
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence
  , ShadowSnapshotId
  )
import QxFx0.Semantic.Embedding (EmbeddingResult)
import QxFx0.Semantic.MeaningAtoms
  ( buildAtomSetFromFindings
  , buildRawAtomFindingsFromMatches
  , buildRawLexicalClusterPhraseContainmentFromDecisions
  , buildRawLexicalClusterHitsFromPhraseContainment
  , buildRawLexicalClusterMatchesFromHits
  , collectRawLexicalClusterPhraseDecisions
  , collectRawLexicalClusterPhraseContainment
  , collectStructuralAtoms
  , updateTrace
  , extractObjectFromAtom
  )
import QxFx0.Semantic.Logic (runSemanticLogic)
import QxFx0.Semantic.Proposition (parsePropositionWithFrame)
import QxFx0.Semantic.SemanticInput (SemanticInput, buildSemanticInputSimple)
import QxFx0.Policy.Contracts (fallbackWord)
import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, ResponseObservation)
import QxFx0.Types.Intuition (IntuitiveFlash)
import QxFx0.Types.SemanticConfig (SemanticConfig)
import QxFx0.Semantic.DialogAtom (DialogAtoms)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Conatus (ConatusEnergy, computeConatusEnergy)
import QxFx0.Self.Field
  ( Field (..)
  , FieldHeuristics
  , emptyField
  , mkResonance
  , deriveFieldConfidence
  , computeConsolidation
  , computeCounterfactual
  , computeAtmosphere
  )
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Salience
  ( SalienceWeights
  , SelfVerdict
  , computeSelfVerdict
  , conatusGateFires
  )
import QxFx0.Self.Essence (Essence)
import QxFx0.Learning.Tool (ExternalTool)
import QxFx0.Learning.Need (LearningNeed)
import QxFx0.Types.ExternalQuery (ExternalQueryError, ExternalQueryResponse)
import QxFx0.Semantic.Input.Assemble (buildUtteranceSemanticFrame)
import QxFx0.Semantic.Input.Model (UtteranceSemanticFrame(..))
import QxFx0.Semantic.Sense (SenseVector)
import QxFx0.Semantic.Sense.Extract (extractSenseVector)
import QxFx0.Core.DialogueThread
  ( CommitmentAdmissionInput(..)
  , admitDialogueCommitmentLedger
  , deriveDialogueCommitmentCandidate
  , deriveDialoguePhase
  , deriveDialogueThread
  )
import QxFx0.Core.InterpretationAdmission
  ( InterpretationAdmissionInput(..)
  , AdmittedInterpretation(..)
  , admitInterpretationCandidate
  )
import QxFx0.Core.PropositionAdmission
  ( PropositionAdmissionInput(..)
  , AdmittedPropositionFrame(..)
  , admitPropositionFrame
  )
import QxFx0.Core.SenseVectorAdmission
  ( SenseVectorAdmissionInput(..)
  , AdmittedSenseVector(..)
  , admitSenseVector
  )
import QxFx0.Core.RouteHintAdmission
  ( RouteHintAdmissionInput(..)
  , AdmittedRouteHint(..)
  , admitRouteHint
  )
import QxFx0.Core.EarlyFamilyAdmission
  ( EarlyFamilyAdmissionInput(..)
  , AdmittedEarlyFamily(..)
  , admitEarlyFamilyRecommendation
  )
import QxFx0.Core.AtomContributionAdmission
  ( AtomContributionAdmissionInput(..)
  , AdmittedAtomContributions(..)
  , admitAtomContributions
  )
import QxFx0.Core.AtomExtractionAdmission
  ( AtomExtractionAdmissionInput(..)
  , AdmittedAtomAvailability(..)
  , admitAtomAvailability
  )
import QxFx0.Core.AtomFindingAdmission
  ( AtomFindingAdmissionInput(..)
  , AdmittedAtomFindings(..)
  , admitAtomFindings
  )
import QxFx0.Core.StructuralAtomAdmission
  ( StructuralAtomAdmissionInput(..)
  , AdmittedStructuralAtoms(..)
  , admitStructuralAtoms
  )
import QxFx0.Core.LexicalClusterPhraseDecisionAdmission
  ( LexicalClusterPhraseDecisionAdmissionInput(..)
  , AdmittedLexicalClusterPhraseDecisions(..)
  , admitLexicalClusterPhraseDecisions
  )
import QxFx0.Core.LexicalClusterPhraseAdmission
  ( LexicalClusterPhraseAdmissionInput(..)
  , AdmittedLexicalClusterPhraseContainment(..)
  , admitLexicalClusterPhraseContainment
  )
import QxFx0.Core.LexicalClusterHitAdmission
  ( LexicalClusterHitAdmissionInput(..)
  , AdmittedLexicalClusterHits(..)
  , admitLexicalClusterHits
  )
import QxFx0.Core.LexicalClusterMatchAdmission
  ( LexicalClusterMatchAdmissionInput(..)
  , AdmittedLexicalClusterMatches(..)
  , admitLexicalClusterMatches
  )
import QxFx0.Core.SemanticContributionAdmission
  ( SemanticContributionAdmissionInput(..)
  , AdmittedSemanticContributions(..)
  , admitSemanticContributions
  )
import QxFx0.Core.SemanticLogicAdmission
  ( SemanticLogicAdmissionInput(..)
  , AdmittedSemanticLogic(..)
  , admitSemanticLogicWeighting
  )
import QxFx0.Core.SemanticFrameAdmission
  ( SemanticFrameAdmissionInput(..)
  , AdmittedSemanticFrame(..)
  , admitSemanticFrame
  )
import QxFx0.Types.State.DialogueDevelopment (DialogueCommitmentLedger, DialoguePhase, DialogueThread, emptyDialogueCommitmentLedger, emptyDialogueThread)

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time.Clock (UTCTime)

data TurnEffectRequest
  = TurnReqEmbedding !Text
  | TurnReqNixGuard !Text !Double !Double
  | TurnReqConsciousness !SemanticInput !Double !Double !ConatusEnergy !SalienceWeights
  | TurnReqIntuition !Text !Double !Double !Int !ConatusEnergy !SalienceWeights !SemanticConfig
  | TurnReqApiHealth
  | TurnReqShadow !CanonicalMoveFamily !IllocutionaryForce ![AtomTag]
  | TurnReqAgdaVerify
  | TurnReqCurrentTime
  | TurnReqRequestId
  | TurnReqReadEnv !Text
  | TurnReqTestMarkOnceFile !Text
  | TurnReqSemanticIntrospectionEnv
  | TurnReqCommitRuntimeState !ConsciousnessLoop !IntuitiveState !ResponseObservation
  | TurnReqSaveState !SystemState !Text !Int !(Maybe TurnProjection)
  | TurnReqRollbackTurnProjections !Text !Int
  | TurnReqCheckpoint !Int
  | TurnReqLinearizeClaimAst !(Maybe FilePath) !Text !ClaimAst
  | TurnReqLinearizeDialogAtoms !(Maybe FilePath) !Text !DialogAtoms
  | TurnReqExternalQuery !ExternalTool !LearningNeed !Text
    -- ^ Phase 8: query an external tool (LLM, mentor, script).
  deriving stock (Show)

data TurnEffectResult
  = TurnResEmbedding !EmbeddingResult
  | TurnResNixGuard !NixGuardStatus
  | TurnResConsciousness !ConsciousnessLoop !(Maybe ConsciousnessNarrative) !(Maybe Text)
  | TurnResIntuition !(Maybe IntuitiveFlash) !Double !IntuitiveState
  | TurnResApiHealth !Bool
  | TurnResShadow !(Maybe (CanonicalMoveFamily, IllocutionaryForce)) !ShadowStatus !ShadowDivergence !ShadowSnapshotId ![Text]
  | TurnResAgdaVerify !AgdaVerificationStatus
  | TurnResCurrentTime !UTCTime
  | TurnResRequestId !Text
  | TurnResReadEnv !(Maybe Text)
  | TurnResTestMarkOnceFile !Bool
  | TurnResSemanticIntrospectionEnv !Bool
  | TurnResCommitRuntimeState
  | TurnResSaveState !(Either PersistenceDiagnostic SystemState)
  | TurnResRollbackTurnProjections !(Either PersistenceDiagnostic ())
  | TurnResCheckpointCompleted
  | TurnResLinearizeClaimAst !(Either Text GfLinearizationResult)
  | TurnResLinearizeDialogAtoms !(Either Text GfLinearizationResult)
  | TurnResExternalQuery !(Either ExternalQueryError ExternalQueryResponse)
    -- ^ Phase 8: response envelope from external tool query.

data PrepareStatic = PrepareStatic
  { psInputText :: !Text
  , psAtomSet :: !AtomSet
  , psNewTrace :: !AtomTrace
  , psNextUserState :: !UserState
  , psRecommendedFamily :: !CanonicalMoveFamily
    -- ^ Constitution-admitted interpretation family used downstream for route
    --   crystallization. The raw semantic recommendation is formed earlier in
    --   prepare but may be narrowed before becoming `TurnInput`.
  , psFrame :: !InputPropositionFrame
    -- ^ Constitution-admitted proposition frame used downstream. Raw parser
    --   output remains intact locally during prepare; this field carries the
    --   admitted interpretation surface after the bounded CTS-02 seam.
  , psConceptToCheck :: !Text
  , psBestTopic :: !Text
  , psResonance :: !Double
  , psAtomLoad :: !Double
  , psConatusEnergy :: !ConatusEnergy
    -- ^ Phase 2.5 (M2d): the runtime Conatus energy computed
    --   from the current 'SelfBlanket' and its 'BlanketViolation's.
    --   Stored once per turn so downstream recovery-decision call
    --   sites (e.g. 'buildLocalRecoveryPlan' in
    --   'QxFx0.Core.TurnPipeline.Route.Render') can priority-check
    --   the Conatus gate without recomputing from 'SystemState'.
  , psBlanketViolationCount :: !Int
    -- ^ Phase 6 (M6): the count of 'BlanketViolation's reported
    --   by 'checkInitialBlanket' on the current 'SelfBlanket'.
    --   Stored alongside 'psConatusEnergy' so the recovery-plan
    --   evidence line @"blanket_violations=N"@ at the
    --   render-stage call site can be reconstructed without a
    --   second 'computeSelfBlanket' + 'checkInitialBlanket' pass.
  , psConatusGateFired :: !Bool
    -- ^ Phase 6 addendum (M6.1): single-source-of-truth flag for
    --   the Conatus gate.  Computed once in 'buildPrepareEffectPlan'
    --   by 'conatusGateFires', then read by both the salience
    --   controller and the recovery-decision site in
    --   'buildLocalRecoveryPlan'.  Eliminates the previous
    --   duplicate call to 'conatusGateFires'.
  , psField :: !Field
    -- ^ Per-turn 'QxFx0.Self.Field.Field' snapshot.  All five
    --   components are populated from runtime signals:
    --
    --     * 'fieldResonance'      — atom-trace current load
    --       ('psResonance').
    --     * 'fieldAtmosphere'     — valence = (ego agency −
    --       ego tension) modulated by legitimacy; arousal =
    --       ego tension.
    --     * 'fieldConsolidation'  — sliding-window narrative
    --       success rate, optionally floored by topic stability.
    --     * 'fieldCounterfactual' — normalised entropy of
    --       candidate family weights, boosted by holistic streak.
    --     * 'fieldConfidence'     — derived by
    --       'deriveFieldConfidence' from the four above.
    --
    --   Threaded through 'tiField' so all routing and salience-
    --   decision call sites share one canonical pre-turn Field.
  , psFieldHeuristics :: !FieldHeuristics
    -- ^ Phase 6.7: heuristics used to build 'psField'.
    --   Threaded through 'TurnInput' so downstream stages
    --   (e.g. salience computation) can read the same record.
  , psSelfVerdict :: !SelfVerdict
    -- ^ Canonical aggregated self-layer verdict for the pre-turn state.
    --   Computed once from the same 'ConatusEnergy' and 'Field' carried
    --   in this record so route/finalize stages do not recompute salience
    --   and its discrete dispatch classification independently.
  , psCurrentTime :: !UTCTime
    -- ^ Phase C: deterministic time injection point.
    --   Captured at prepare-stage entry so 'buildTurnInput' can
    --   set 'tiStartTime' without relying on the resolved timeline.
    --   Enables deterministic unit tests with a fixed time source.
  , psSenseVector :: !SenseVector
    -- ^ Canonical sense bridge extracted from the same utterance-level
    --   semantic interpretation used to derive 'psFrame'.
  , psDialogueThread :: !DialogueThread
  , psDialogueCommitmentLedger :: !DialogueCommitmentLedger
  , psDialoguePhase :: !DialoguePhase
  , psTruthContractStatus :: !TruthContractStatus
  , psEssence :: !Essence
    -- ^ Phase 9: pre-turn essence carrier from 'ssEssence'.
    --   Threaded through 'tiEssence' so witness ingestion in
    --   'buildNextSystemState' sees the canonical trajectory.
  } deriving stock (Eq, Show)

data PrepareEffectRequest
  = PrepareReqEmbedding !Text
  | PrepareReqNixGuard !Text !Double !Double
  | PrepareReqConsciousness !SemanticInput !Double !Double !ConatusEnergy !SalienceWeights
  | PrepareReqIntuition !Text !Double !Double !Int !ConatusEnergy !SalienceWeights !SemanticConfig
  | PrepareReqApiHealth
  deriving stock (Eq, Show)

data PrepareEffectPlan = PrepareEffectPlan
  { pepStatic :: !PrepareStatic
  , pepCapturedCurrentTime :: !UTCTime
  , pepEmbeddingRequest :: !PrepareEffectRequest
  , pepNixGuardRequest :: !PrepareEffectRequest
  , pepConsciousnessRequest :: !PrepareEffectRequest
  , pepIntuitionRequest :: !PrepareEffectRequest
  , pepApiHealthRequest :: !PrepareEffectRequest
  } deriving stock (Eq, Show)

buildPrepareEffectPlan :: SystemState -> Text -> UTCTime -> PrepareEffectPlan
buildPrepareEffectPlan ss input currentTime =
  let rawPhraseDecisions = collectRawLexicalClusterPhraseDecisions input (ssClusters ss)
      admittedPhraseDecisions = admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput (ssTruthContractStatus ss)) rawPhraseDecisions
      rawPhraseContainment = buildRawLexicalClusterPhraseContainmentFromDecisions (alcpdDecisions admittedPhraseDecisions)
      admittedPhraseContainment = admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput (ssTruthContractStatus ss)) rawPhraseContainment
      rawHits = buildRawLexicalClusterHitsFromPhraseContainment (alcpContainment admittedPhraseContainment)
      admittedHits = admitLexicalClusterHits (LexicalClusterHitAdmissionInput (ssTruthContractStatus ss)) rawHits
      rawMatches = buildRawLexicalClusterMatchesFromHits (alchHits admittedHits)
      admittedMatches = admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput (ssTruthContractStatus ss)) rawMatches
      rawFindings = buildRawAtomFindingsFromMatches (alcmMatches admittedMatches) (collectStructuralAtoms input)
      admittedStructural = admitStructuralAtoms (StructuralAtomAdmissionInput (ssTruthContractStatus ss)) rawFindings
      admittedFindings = admitAtomFindings (AtomFindingAdmissionInput (ssTruthContractStatus ss)) (asaFindings admittedStructural)
      atomSet = buildAtomSetFromFindings (aafFindings admittedFindings)
      newTrace = updateTrace (ssTrace ss) (ssTurnCount ss) atomSet
      nextUserState = inferUserState (ssClusters ss) input
      admittedAtomExtraction = admitAtomAvailability (AtomExtractionAdmissionInput (ssTruthContractStatus ss)) atomSet
      semanticAtomSet = atomSet { asAtoms = aaaAtoms admittedAtomExtraction }
      admittedAtomInput = AtomContributionAdmissionInput
        { acaiTruthContractStatus = ssTruthContractStatus ss
        }
      admittedAtomContributions = admitAtomContributions admittedAtomInput semanticAtomSet
      logicAtomSet = semanticAtomSet { asAtoms = aacAtoms admittedAtomContributions }
      logicResults = runSemanticLogic logicAtomSet
      sortedLogic = L.sortBy (\(_, w1) (_, w2) -> compare w2 w1) logicResults
      rawRecommendedFamily = case sortedLogic of
        ((fam, _):_) -> fam
        [] -> CMGround
      rawSemanticFrame = buildUtteranceSemanticFrame input
      rawSenseVector = extractSenseVector rawSemanticFrame
      rawCommitmentCandidate = deriveDialogueCommitmentCandidate rawSemanticFrame
      atomFocus = case asAtoms atomSet of
        (a:_) -> extractObjectFromAtom a
        [] -> ""
      conceptToCheck =
        firstNonEmpty
          [ ipfFocusNominative frame
          , ipfFocusEntity frame
          , atomFocus
          , fromMaybe fallbackWord (listToMaybe (T.words input))
          ]
      focus = firstNonEmpty [ipfFocusNominative frame, ipfFocusEntity frame, atomFocus, ssLastTopic ss]
      bestTopic = if T.null focus then ssLastTopic ss else focus
      resonance = atCurrentLoad newTrace
      atomLoad = asLoad atomSet
      blanket = computeSelfBlanket ss
      violations = checkInitialBlanket blanket
      conatusEnergy = computeConatusEnergy blanket violations
      violationCount = length violations
      conatusGateFired = conatusGateFires conatusEnergy
      -- Phase 7: populate four of five Field components via
      -- the calibrated 'FieldHeuristics' compute functions.
      -- 'fieldConfidence' is derived below.
      fieldHeuristics = ssFieldHeuristics ss
      preparedField0 = emptyField
        { fieldResonance      = mkResonance resonance
        , fieldAtmosphere     = computeAtmosphere fieldHeuristics
                                  (egoAgency (ssEgo ss))
                                  (egoTension (ssEgo ss))
                                  (obsLastLegitimacyScore (ssObservability ss))
        , fieldConsolidation  = computeConsolidation fieldHeuristics
                                  (ssRecentNarrativeSuccess ss)
                                  (not (T.null bestTopic) && bestTopic == ssLastTopic ss)
        , fieldCounterfactual = computeCounterfactual fieldHeuristics
                                  (map snd sortedLogic)
                                  (ssHolisticStreak ss)
        }
      preparedField = preparedField0
        { fieldConfidence = deriveFieldConfidence preparedField0
        }
      selfVerdict = computeSelfVerdict (ssSalienceWeights ss) conatusEnergy preparedField
      commitmentAdmissionInput = CommitmentAdmissionInput
        { caiTruthContractStatus = ssTruthContractStatus ss
        , caiConatusGateFired = conatusGateFired
        }
      semanticFrameAdmissionInput = SemanticFrameAdmissionInput
        { sfaiTruthContractStatus = ssTruthContractStatus ss
        , sfaiConatusGateFired = conatusGateFired
        }
      admittedSemantic = admitSemanticFrame semanticFrameAdmissionInput rawSemanticFrame
      admittedSemanticFrame = asfFrame admittedSemantic
      routeHintAdmissionInput = RouteHintAdmissionInput
        { rhaiTruthContractStatus = ssTruthContractStatus ss
        , rhaiConatusGateFired = conatusGateFired
        , rhaiRawText = input
        }
      admittedRouteHint = admitRouteHint routeHintAdmissionInput (usfRouteHint admittedSemanticFrame)
      routeHintAdmittedSemanticFrame = admittedSemanticFrame { usfRouteHint = arhHint admittedRouteHint }
      frame = parsePropositionWithFrame input routeHintAdmittedSemanticFrame
      propositionAdmissionInput = PropositionAdmissionInput
        { paiTruthContractStatus = ssTruthContractStatus ss
        , paiConatusGateFired = conatusGateFired
        }
      admittedProposition = admitPropositionFrame propositionAdmissionInput frame
      admittedBaseFrame = apfFrame admittedProposition
      semanticContributionAdmissionInput = SemanticContributionAdmissionInput
        { scaiTruthContractStatus = ssTruthContractStatus ss
        , scaiConatusGateFired = conatusGateFired
        , scaiFrame = admittedBaseFrame
        }
      admittedSemanticContributions = admitSemanticContributions semanticContributionAdmissionInput logicResults
      admittedLogicResults = ascFamilies admittedSemanticContributions
      admittedSortedLogic = L.sortBy (\(_, w1) (_, w2) -> compare w2 w1) admittedLogicResults
      semanticLogicAdmissionInput = SemanticLogicAdmissionInput
        { slaiTruthContractStatus = ssTruthContractStatus ss
        , slaiConatusGateFired = conatusGateFired
        , slaiFrame = admittedBaseFrame
        }
      admittedSemanticLogic = admitSemanticLogicWeighting semanticLogicAdmissionInput admittedSortedLogic
      admittedLogicFamilies = aslFamilies admittedSemanticLogic
      recommendedFamily = case admittedLogicFamilies of
        ((fam, _):_) -> fam
        [] -> CMGround
      earlyFamilyAdmissionInput = EarlyFamilyAdmissionInput
        { efaiTruthContractStatus = ssTruthContractStatus ss
        , efaiConatusGateFired = conatusGateFired
        }
      admittedEarlyFamily = admitEarlyFamilyRecommendation earlyFamilyAdmissionInput recommendedFamily admittedBaseFrame
      admittedRecommendedFamily = aefFamily admittedEarlyFamily
      interpretationAdmissionInput = InterpretationAdmissionInput
        { iaiTruthContractStatus = ssTruthContractStatus ss
        , iaiConatusGateFired = conatusGateFired
        }
      admittedInterpretation = admitInterpretationCandidate interpretationAdmissionInput admittedRecommendedFamily admittedBaseFrame
      admittedFamily = aiRecommendedFamily admittedInterpretation
      admittedFrame = aiFrame admittedInterpretation
      senseVectorAdmissionInput = SenseVectorAdmissionInput
        { svaiTruthContractStatus = ssTruthContractStatus ss
        , svaiConatusGateFired = conatusGateFired
        }
      admittedSense = admitSenseVector senseVectorAdmissionInput rawSenseVector
      admittedSenseVector = asvVector admittedSense
      semanticInput =
        buildSemanticInputSimple
          input
          atomSet
          frame
          admittedRecommendedFamily
          (ipfRegisterHint frame)
          (ipfSemanticLayer frame)
      dialogueLedger = admitDialogueCommitmentLedger commitmentAdmissionInput (ssDialogueCommitmentLedger ss) rawCommitmentCandidate
      dialogueThread = deriveDialogueThread (ssDialogueThread ss) dialogueLedger (ssDialogue ss) rawSemanticFrame
      dialoguePhase = deriveDialoguePhase dialogueThread dialogueLedger rawSemanticFrame
      static = PrepareStatic
        { psInputText = input
        , psAtomSet = atomSet
        , psNewTrace = newTrace
        , psNextUserState = nextUserState
        , psRecommendedFamily = admittedFamily
        , psFrame = admittedFrame
        , psConceptToCheck = conceptToCheck
        , psBestTopic = bestTopic
        , psResonance = resonance
        , psAtomLoad = atomLoad
        , psConatusEnergy = conatusEnergy
        , psBlanketViolationCount = violationCount
      , psConatusGateFired = conatusGateFired
      , psField = preparedField
      , psFieldHeuristics = fieldHeuristics
        -- ^ Phase 6.7: heuristics used to build 'psField'.
        --   Threaded through 'TurnInput' so downstream stages
        --   (e.g. salience computation) can read the same record.
       , psSelfVerdict = selfVerdict
       , psCurrentTime = currentTime
       , psSenseVector = admittedSenseVector
      , psDialogueThread = dialogueThread
       , psDialogueCommitmentLedger = dialogueLedger
      , psDialoguePhase = dialoguePhase
      , psTruthContractStatus = ssTruthContractStatus ss
      , psEssence = ssEssence ss
      }
  in PrepareEffectPlan
      { pepStatic = static
      , pepCapturedCurrentTime = currentTime
      , pepEmbeddingRequest = PrepareReqEmbedding input
      , pepNixGuardRequest = PrepareReqNixGuard conceptToCheck resonance atomLoad
      , pepConsciousnessRequest =
          PrepareReqConsciousness semanticInput (egoAgency (ssEgo ss)) resonance conatusEnergy (ssSalienceWeights ss)
      , pepIntuitionRequest =
          PrepareReqIntuition input resonance (egoTension (ssEgo ss)) (ssTurnCount ss + 1) conatusEnergy (ssSalienceWeights ss) (ssSemanticConfig ss)
      , pepApiHealthRequest = PrepareReqApiHealth
      }
  where
    firstNonEmpty = fromMaybe "" . listToMaybe . filter (not . T.null)
