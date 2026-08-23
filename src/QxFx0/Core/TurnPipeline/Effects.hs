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
import QxFx0.Types.State.SelfState (SelfState(..))
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
import QxFx0.Semantic.Intent.GeometricClassifier
  ( IntentClassifier(..)
  , buildClassifier
  , classifyIntent
  , intentToFamily
  , geometricFamilyRecommendation
  , ClassificationResult(..)
  )
import QxFx0.Semantic.Space.Types (SemanticSpace(..))
import qualified QxFx0.Semantic.Content as Content
import QxFx0.Semantic.Ontology (Ontology)
import QxFx0.Semantic.Space (tokenizePredicate)
import QxFx0.Types.PropositionType (PropositionType(..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import QxFx0.Semantic.Proposition (parsePropositionWithFrame)
import QxFx0.Semantic.SemanticInput (SemanticInput, buildSemanticInputSimple)
import QxFx0.Policy.Contracts (fallbackWord)
import QxFx0.Core.StanceClassifier (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, ResponseObservation)
import QxFx0.Types.Intuition (IntuitiveFlash)
import QxFx0.Types.SemanticConfig (SemanticConfig)
import QxFx0.Semantic.DialogAtom (DialogAtoms)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Conatus (ConatusEnergy, computeConatusEnergyWith)
import QxFx0.Self.Field
  ( Field (..)
  , FieldHeuristics
  , emptyField
  , mkResonance
  , deriveFieldConfidence
  , computeConsolidation
  , computeCounterfactual
  , computeAtmosphere
  , computeAtmosphereDecoupled
  , affectDecoupledActive
  )
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Salience
  ( SalienceWeights
  , SelfVerdict
  , computeSelfVerdict
  , conatusGateFires
  )
import QxFx0.Core.ContentCluster (computeContentSaliency)  -- WP-C (renamed from Spectral, WP-I Tier-0)
import QxFx0.Self.Essence (Essence(..), EssenceTrajectory(..), defaultEssenceModulation)
import QxFx0.Self.SelfDivergence
  ( predictSelf
  , selfConsistencyPenalty
  )
import QxFx0.Types.Self.SelfDivergence
  ( SelfPrediction
  , defaultSelfDivergenceTuning
  )
import QxFx0.Safety.CrisisGuard (decideProtocol, detectCrisisTrigger)
import QxFx0.User.R5 (encodeR5)
import QxFx0.Semantic.Ontological (classifyOntological)
import QxFx0.Semantic.MoveGraph (planOntologicalMove)
import QxFx0.Types.Safety.Crisis (ProtocolVerdict(..))
import QxFx0.Types.Semantic.OntologicalAxis (OntologicalVector)
import QxFx0.Types.Semantic.MoveGraph (OntologicalMovePlan)
import QxFx0.Types.User.R5
  ( UserR5State
  , UserR5ContourState(..)
  , defaultUserConatusWeights
  , defaultViabilityContour
  , outsideViabilityContour
  , r5Distance
  , userConatusScore
  )
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
import QxFx0.Types.Admission.PropositionAdmission
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
import QxFx0.Types.Persistence (StateVersion)
import QxFx0.Semantic.Network.Types (SemanticNetwork)
import QxFx0.Types.Semantic.ResponsePlan (ResponseSemanticPlan)

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
  | TurnReqSaveState !SystemState !Text !StateVersion !(Maybe TurnProjection)
  | TurnReqRollbackCommittedTurn !SystemState !Text !StateVersion !Int
  | TurnReqPersistFeedbackMirror !SemanticNetwork !SemanticNetwork
  | TurnReqCheckpoint !Int
  | TurnReqLinearizeClaimAst !(Maybe FilePath) !Text !ClaimAst
  | TurnReqLinearizeDialogAtoms !(Maybe FilePath) !Text !DialogAtoms
  | TurnReqLinearizeResponsePlan !(Maybe FilePath) !Text !ResponseSemanticPlan
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
  | TurnResRollbackCommittedTurn !(Either PersistenceDiagnostic ())
  | TurnResPersistFeedbackMirror
  | TurnResCheckpointCompleted
  | TurnResLinearizeClaimAst !(Either Text GfLinearizationResult)
  | TurnResLinearizeDialogAtoms !(Either Text GfLinearizationResult)
  | TurnResLinearizeResponsePlan !(Either Text GfLinearizationResult)
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
  , psGeoResult :: !(Maybe ClassificationResult)
    -- ^ Phase 2: geometric classifier result for A/B validation.
    --   Stored for metrics recording in Finalize stage.
  , psSelfPrediction :: !(Maybe SelfPrediction)
    -- ^ A-slice: deterministic prediction of this turn's Field,
    --   anchored on the previous observed Field plus the pre-turn
    --   angst level.  @Nothing@ on the first turn (no previous
    --   observation yet).  Threaded through 'tiSelfPrediction' so
    --   Finalize can measure the divergence without recomputing.
  , psSelfDivergencePenalty :: !Double
    -- ^ A-slice: the Conatus penalty share (<= 0) applied this turn
    --   from the previous turn's divergence.  @0@ when the previous
    --   turn had no measurement or divergence was below the
    --   'sdtThreshold'.  Threaded through 'tiSelfDivergencePenalty'
    --   for trace observability.
  , psUserR5 :: !UserR5State
    -- ^ Concept v3 §4: the decoded user-side R5 state (the state of
    --   the system-human, distinct from the system's own 'Field').
    --   Computed once per turn by the frozen v1 encoder
    --   ('QxFx0.User.R5.encodeR5') from the raw input and topic
    --   continuity.
  , psUserProtocol :: !ProtocolVerdict
    -- ^ Concept v3 §2: the two-protocol verdict (Protocol A
    --   everyday-ontological / Protocol B bounded crisis).  Resolved
    --   by 'QxFx0.Safety.CrisisGuard.decideProtocol': the hard
    --   lexical crisis trigger outranks every numeric estimate; a
    --   viability-contour exit is the soft backstop.
  , psUserPredictionError :: !(Maybe Double)
    -- ^ Concept v3 §6: residual audit of the /user/ transition model
    --   — @r5Distance@ between the previous turn's deterministic
    --   prediction and this turn's observed state.  @Nothing@ on the
    --   first turn.  The user-side clone of the A-slice self-divergence
    --   pattern (predict → witness → diff).
  , psOntologicalVector :: !OntologicalVector
    -- ^ Concept v3 §5: the ontological directedness of the input
    --   utterance (being/non-being, striving/denial,
    --   affirmation/destruction) from 'QxFx0.Semantic.Ontological'.
  , psOntologicalMove :: !(Maybe OntologicalMovePlan)
    -- ^ Concept v3 §6: the computed ontological transition operator
    --   (deterministic search toward S*), or Nothing when the turn
    --   carries no ontological act to answer and no drift toward
    --   the contour edge.  Protocol A only — under Protocol B the
    --   bounded surface replaces the ontological move entirely.
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

buildPrepareEffectPlan :: Bool -> SystemState -> Text -> UTCTime -> PrepareEffectPlan
buildPrepareEffectPlan repairDisabled ss input currentTime =
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
      geoClassification = if useGeometricIntent
                            then case buildGeometricClassifier (ssOntology ss) (ssLemmaMap ss) (ssSemanticSpace ss) of
                                   Just classifier ->
                                     let atomTexts = S.fromList (map maText (asAtoms logicAtomSet))
                                     in Just (classifyIntent classifier atomTexts)
                                   Nothing -> Nothing
                            else Nothing
      geoResults = case geoClassification of
                     Just (Classified intent score) ->
                       case intentToFamily intent of
                         Just fam -> [(fam, score)]
                         Nothing -> []
                     _ -> []
      mergedLogicGeo = L.sortBy (\(_, w1) (_, w2) -> compare w2 w1) (sortedLogic ++ geoResults)
      rawRecommendedFamily = case mergedLogicGeo of
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
      conatusEnergy0 = computeConatusEnergyWith
        (selfConatusWeights (ssSelfState ss)) blanket violations
      -- A-slice: apply the previous turn's measured divergence as a
      -- Conatus penalty (one-turn delayed).  The pure penalty share
      -- (<= 0) is threaded through 'psSelfDivergencePenalty' so the
      -- Finalize stage can record it on the trace without
      -- recomputing.
      (conatusEnergy, divergencePenalty) =
        case selfLastDivergence (ssSelfState ss) of
          Nothing -> (conatusEnergy0, 0.0)
          Just divE ->
            selfConsistencyPenalty
              defaultSelfDivergenceTuning divE conatusEnergy0
      -- A-slice: deterministic prediction of this turn's Field,
      -- anchored on the previous observed Field.  @Nothing@ on the
      -- first turn (no previous observation yet).
      selfPrediction =
        case selfLastFieldObservation (ssSelfState ss) of
          Nothing -> Nothing
          Just prevField ->
            let preTurnAngst = etAngstLevel (essenceTrajectoryOf (selfEssence (ssSelfState ss)))
            in Just (predictSelf defaultEssenceModulation prevField preTurnAngst)
      violationCount = length violations
      conatusGateFired = conatusGateFires conatusEnergy
      -- Concept v3 §4/§6: decode the user's R5 state from the raw
      -- signal, audit it against the previous turn's deterministic
      -- prediction, and resolve the two-protocol verdict.  The hard
      -- crisis gate runs on the raw text before any numeric estimate
      -- and cannot be suppressed.
      userR5Now = encodeR5 input (ssLastTopic ss)
      userScore = userConatusScore defaultUserConatusWeights userR5Now
      priorUserContour = ssUserR5Contour ss
      userOutsideContour = outsideViabilityContour defaultViabilityContour
                             (u5Baseline priorUserContour) userR5Now userScore
      crisisTrigger = detectCrisisTrigger input
      userProtocol = decideProtocol crisisTrigger
                       (if userOutsideContour then Just userScore else Nothing)
      userPredictionError =
        r5Distance <$> u5PredictedNext priorUserContour <*> pure userR5Now
      ontologicalVector = classifyOntological input
      -- Concept v3 §6: search for the ontological transition
      -- operator — only under Protocol A, and only when there is an
      -- act to answer (negative directedness) or a downward drift
      -- below the personalized baseline.
      ontologicalMovePlan = case userProtocol of
        ProtocolA -> planOntologicalMove
                       userR5Now ontologicalVector
                       (u5Baseline priorUserContour) userScore
        ProtocolB _ -> Nothing
      -- Phase 7: populate four of five Field components via
      -- the calibrated 'FieldHeuristics' compute functions.
      -- 'fieldConfidence' is derived below.
      fieldHeuristics = selfFieldHeuristics (ssSelfState ss)
      preparedField0 = emptyField
        { fieldResonance      = mkResonance resonance
        , fieldAtmosphere     =
            if affectDecoupledActive
              then computeAtmosphereDecoupled fieldHeuristics
                     (egoAgency (ssEgo ss))
                     (egoTension (ssEgo ss))
                     (obsLastLegitimacyScore (ssObservability ss))
                     resonance
              else computeAtmosphere fieldHeuristics
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
      contentSaliency = computeContentSaliency (ssMeaningGraph ss)  -- WP-C
      selfVerdict = computeSelfVerdict (selfSalienceWeights (ssSelfState ss)) conatusEnergy preparedField contentSaliency
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
      challengeAdjustedRecommendedFamily =
        if hasChallengeMarker input && not repairDisabled then CMConfront else recommendedFamily
      earlyFamilyAdmissionInput = EarlyFamilyAdmissionInput
        { efaiTruthContractStatus = ssTruthContractStatus ss
        , efaiConatusGateFired = conatusGateFired
        }
      admittedEarlyFamily = admitEarlyFamilyRecommendation earlyFamilyAdmissionInput challengeAdjustedRecommendedFamily admittedBaseFrame
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
       , psEssence = selfEssence (ssSelfState ss)
       , psGeoResult = geoClassification
       , psSelfPrediction = selfPrediction
       , psSelfDivergencePenalty = divergencePenalty
       , psUserR5 = userR5Now
       , psUserProtocol = userProtocol
       , psUserPredictionError = userPredictionError
       , psOntologicalVector = ontologicalVector
       , psOntologicalMove = ontologicalMovePlan
       }
  in PrepareEffectPlan
      { pepStatic = static
      , pepCapturedCurrentTime = currentTime
      , pepEmbeddingRequest = PrepareReqEmbedding input
      , pepNixGuardRequest = PrepareReqNixGuard conceptToCheck resonance atomLoad
      , pepConsciousnessRequest =
          PrepareReqConsciousness semanticInput (egoAgency (ssEgo ss)) resonance conatusEnergy (selfSalienceWeights (ssSelfState ss))
      , pepIntuitionRequest =
          PrepareReqIntuition input resonance (egoTension (ssEgo ss)) (ssTurnCount ss + 1) conatusEnergy (selfSalienceWeights (ssSelfState ss)) (ssSemanticConfig ss)
      , pepApiHealthRequest = PrepareReqApiHealth
      }
  where
    firstNonEmpty = fromMaybe "" . listToMaybe . filter (not . T.null)

    -- | Extract the trajectory from either 'Essence' constructor.
    essenceTrajectoryOf :: Essence -> EssenceTrajectory
    essenceTrajectoryOf (EssenceUncommitted traj)      = traj
    essenceTrajectoryOf (EssenceCommitted traj _)     = traj

useGeometricIntent :: Bool
useGeometricIntent = True

hasChallengeMarker :: Text -> Bool
hasChallengeMarker input =
  let lowered = T.toLower input
  in any (`T.isInfixOf` lowered)
       [ "разве", "не согласен", "не согласна", "противореч", "неверно"
       , "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь"
       , "ты говоришь", "оспариваю"
       , "это просто", "не более чем", "сводится к"
       , "всего лишь", "это лишь"
       , "контрпример", "докажи", "что если"
       ]

buildGeometricClassifier :: Ontology -> Map Text Text -> SemanticSpace -> Maybe IntentClassifier
buildGeometricClassifier ontology lemmaMap space
  | ssDimensionCount space == 0 = Nothing
  | otherwise =
    let labeled = M.fromListWith S.union
          [ (categoryToPropositionType (Content.classifyConceptCategory ontology topic), tokenizePredicate lemmaMap (Content.spRu pred))
          | topic <- Content.coveredTopics
          , Just dc <- [Content.lookupDefinitionContent topic]
          , pred <- Content.dcPredicates dc
          ]
    in if M.null labeled
         then Nothing
         else Just (buildClassifier space labeled)
  where
    categoryToPropositionType :: Content.ConceptCategory -> PropositionType
    categoryToPropositionType cat = case cat of
      Content.CategoryPhilosophical -> DefinitionalQ
      Content.CategorySocial -> PurposeQ
      Content.CategoryPsychological -> SelfKnowledgeQ
      Content.CategoryPhysical -> WorldCauseQ
      Content.CategoryGeneral -> ConceptKnowledgeQ
