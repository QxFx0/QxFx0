{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Runtime-owned construction and persisted-state compatibility defaults.
module QxFx0.Runtime.StateDefaults
  ( emptySystemState
  , emptySelfState
  , defaultSelfState
  ) where

import Control.Monad (when)
import Data.Aeson
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.HashSet as HS
import qualified Data.Map.Strict as M
import qualified Data.Sequence as Seq
import qualified Data.Set as Set

import QxFx0.Learning.Calibration (emptyCalibrationLog)
import QxFx0.Learning.Guardrails (emptyGuardrailState)
import QxFx0.Learning.KnowledgeTree (emptyKnowledgeTree)
import QxFx0.Learning.Need (emptyLearningNeedState)
import QxFx0.Memory.Episodic (EpisodicStore(..), emptyIndex)
import QxFx0.Self.Conatus (defaultConatusWeights)
import QxFx0.Self.Essence (emptyEssence)
import QxFx0.Self.FamilyTargets (familyTargets)
import QxFx0.Self.Field (defaultFieldHeuristics)
import QxFx0.Self.Salience (defaultSalienceWeights)
import QxFx0.Semantic.Content.AtomStore (seedGraph)
import QxFx0.Semantic.ContentSelector.Types (emptyContentSelector)
import QxFx0.Semantic.ContentSelector.Integration (ContentSelectorState)
import QxFx0.Semantic.DialogueContext (emptyContext)
import QxFx0.Semantic.Intent.Metrics (emptyIntentClassifierMetrics)
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Network.Types (emptySemanticNetwork)
import QxFx0.Semantic.Ontology (emptyOntology)
import QxFx0.Semantic.Space.Types (emptySemanticSpace)
import QxFx0.Types.Bayesian (initialBeliefs)
import QxFx0.Types.Decision
  ( DialogueOutputMode(..)
  , dialogueOutputModeText
  , parseDialogueOutputMode
  )
import QxFx0.Types.Domain (MorphologyData(..))
import QxFx0.Types.Dream (emptyDreamState)
import QxFx0.Types.Intuition (defaultIntuitiveState)
import QxFx0.Types.Lexicon.RuntimeParadigms (emptyRuntimeParadigms)
import QxFx0.Types.Observability
  ( TruthContractStatus(..)
  , emptyObservabilityState
  )
import QxFx0.Types.Persistence (PersistenceEnvelope(..))
import QxFx0.Types.RuntimeRegime (defaultRuntimeRegime)
import QxFx0.Types.Semantic.Ontology (Ontology(..))
import QxFx0.Types.ShadowDivergence (defaultShadowVetoState)
import QxFx0.Types.State.Dialogue (DialogueState(..), emptyDialogueState)
import QxFx0.Types.State.DialogueDevelopment
  ( DialoguePhase(..)
  , emptyBeliefStore
  , emptyDialogueCommitmentLedger
  , emptyDialogueOutcomeLearningState
  , emptyDialogueThread
  , emptySpeechPolicyState
  )
import QxFx0.Types.State.Governance
  ( GovernanceProjection(..)
  , ProjectionMeta(..)
  , currentProjectionVersion
  , currentReducerVersion
  )
import QxFx0.Types.State.Identity (IdentityState(..), emptyIdentityState)
import QxFx0.Types.State.Perspective (emptyPerspectiveRegistry)
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.State.Semantic (SemanticState(..), emptySemanticState)
import QxFx0.Types.State.System (SystemState(..))
import QxFx0.Types.Vec (zeroVec)

instance ToJSON SelfState where
  toJSON selfState = object
    [ "selfSalienceWeights" .= selfSalienceWeights selfState
    , "selfFieldHeuristics" .= selfFieldHeuristics selfState
    , "selfConatusWeights" .= selfConatusWeights selfState
    , "selfFamilyTargets" .= selfFamilyTargets selfState
    , "selfPerspectiveRegistry" .= selfPerspectiveRegistry selfState
    , "selfEssence" .= selfEssence selfState
    , "selfLastFieldObservation" .= selfLastFieldObservation selfState
    , "selfLastDivergence" .= selfLastDivergence selfState
    , "selfDivergenceWindow" .= selfDivergenceWindow selfState
    ]

instance FromJSON SelfState where
  parseJSON = withObject "SelfState" $ \o -> SelfState
    <$> o .:? "selfSalienceWeights" .!= defaultSalienceWeights
    <*> o .:? "selfFieldHeuristics" .!= defaultFieldHeuristics
    <*> o .:? "selfConatusWeights" .!= defaultConatusWeights
    <*> o .:? "selfFamilyTargets" .!= familyTargets
    <*> o .:? "selfPerspectiveRegistry" .!= emptyPerspectiveRegistry
    <*> o .:? "selfEssence" .!= emptyEssence
    <*> o .:? "selfLastFieldObservation" .!= Nothing
    <*> o .:? "selfLastDivergence" .!= Nothing
    <*> o .:? "selfDivergenceWindow" .!= []

emptySelfState :: SelfState
emptySelfState = SelfState
  { selfSalienceWeights = defaultSalienceWeights
  , selfFieldHeuristics = defaultFieldHeuristics
  , selfConatusWeights = defaultConatusWeights
  , selfFamilyTargets = familyTargets
  , selfPerspectiveRegistry = emptyPerspectiveRegistry
  , selfEssence = emptyEssence
  , selfLastFieldObservation = Nothing
  , selfLastDivergence = Nothing
  , selfDivergenceWindow = []
  }

defaultSelfState :: SelfState
defaultSelfState = emptySelfState

instance ToJSON SystemState where
  toJSON ss = object
    [ "schemaVersion" .= currentSystemStateSchemaVersion
    , "history" .= dsHistory (ssDialogue ss)
    , "rawInputHistory" .= dsRawInputHistory (ssDialogue ss)
    , "turnCount" .= dsTurnCount (ssDialogue ss)
    , "lastFamily" .= dsLastFamily (ssDialogue ss)
    , "lastTopic" .= dsLastTopic (ssDialogue ss)
    , "lastForce" .= dsLastForce (ssDialogue ss)
    , "lastLayer" .= dsLastLayer (ssDialogue ss)
    , "lastEmbedding" .= dsLastEmbedding (ssDialogue ss)
    , "consecutiveReflect" .= dsConsecutiveReflect (ssDialogue ss)
    , "recentFamilies" .= dsRecentFamilies (ssDialogue ss)
    , "activeScene" .= dsActiveScene (ssDialogue ss)
    , "userState" .= dsUserState (ssDialogue ss)
    , "lastSalienceBias" .= dsLastSalienceBias (ssDialogue ss)
    , "holisticStreak" .= dsHolisticStreak (ssDialogue ss)
    , "recentNarrativeSuccess" .= dsRecentNarrativeSuccess (ssDialogue ss)
    , "ego" .= idsEgo (ssIdentity ss)
    , "identityClaims" .= idsIdentityClaims (ssIdentity ss)
    , "orbitalMemory" .= idsOrbitalMemory (ssIdentity ss)
    , "lastGuardReport" .= idsLastGuardReport (ssIdentity ss)
    , "trace" .= semTrace (ssSemantic ss)
    , "meaningGraph" .= semMeaningGraph (ssSemantic ss)
    , "kernelPulse" .= semKernelPulse (ssSemantic ss)
    , "blockedConcepts" .= semBlockedConcepts (ssSemantic ss)
    , "clusters" .= semClusters (ssSemantic ss)
    , "dreamState" .= semDreamState (ssSemantic ss)
    , "intuitionState" .= semIntuitionState (ssSemantic ss)
    , "semanticAnchor" .= semSemanticAnchor (ssSemantic ss)
    , "lastTurnDecision" .= semLastTurnDecision (ssSemantic ss)
    , "intuitConfidence" .= semIntuitConfidence (ssSemantic ss)
    , "sessionId" .= ssSessionId ss
    , "outputMode" .= dialogueOutputModeText (ssOutputMode ss)
    , "morphology" .= ssMorphology ss
    , "observability" .= ssObservability ss
    , "ssSelfState" .= ssSelfState ss
    , "shadowVetoState" .= ssShadowVetoState ss
    , "provisionalAtoms" .= ssProvisionalAtoms ss
    , "learningNeedState" .= ssLearningNeedState ss
    , "guardrailState" .= ssGuardrailState ss
    , "calibrationLog" .= ssCalibrationLog ss
    , "knowledgeTree" .= ssKnowledgeTree ss
    , "toolReliability" .= ssToolReliability ss
    , "calibrationSnapshots" .= ssCalibrationSnapshots ss
    , "adaptiveMutationLog" .= ssAdaptiveMutationLog ss
    , "dialogueOutcomeLearning" .= ssDialogueOutcomeLearning ss
    , "dialogueThread" .= ssDialogueThread ss
    , "dialogueCommitmentLedger" .= ssDialogueCommitmentLedger ss
    , "dialoguePhase" .= ssDialoguePhase ss
    , "truthContractStatus" .= ssTruthContractStatus ss
    , "speechPolicyState" .= ssSpeechPolicyState ss
    , "beliefStore" .= ssBeliefStore ss
    , "governanceHistory" .= ssGovernanceHistory ss
    , "governanceRuntimeFault" .= ssGovernanceRuntimeFault ss
    , "semanticCommitments" .= ssSemanticCommitments ss
    , "metacognition" .= ssMetacognition ss
    , "episodic" .= ssEpisodic ss
    , "userModel" .= ssUserModel ss
    , "mood" .= ssMood ss
    , "currentRegime" .= ssCurrentRegime ss
    , "runtimeParadigms" .= ssRuntimeParadigms ss
    , "semanticNetwork" .= ssSemanticNetwork ss
    , "lastActivationArtifact" .= ssLastActivationArtifact ss
    , "ontology" .= ssOntology ss
    , "semanticSpace" .= ssSemanticSpace ss
    , "contentSelector" .= ssContentSelector ss
    , "contentSelectorState" .= ssContentSelectorState ss
    , "lemmaMap" .= ssLemmaMap ss
    , "categoryMap" .= ssCategoryMap ss
    , "stances" .= ssStances ss
    , "stanceDefenses" .= ssStanceDefenses ss
    , "userStanceTrackers" .= ssUserStanceTrackers ss
    , "stanceLineages" .= ssStanceLineages ss
    , "runtimeGraph" .= ssRuntimeGraph ss
    , "definitionCorpus" .= ssDefinitionCorpus ss
    , "emittedPredicates" .= ssEmittedPredicates ss
    ]

instance FromJSON SystemState where
  parseJSON = withObject "SystemState" $ \o -> do
    schemaVersion <- o .:? "schemaVersion" .!= 1
    let required
          | schemaVersion >= currentSystemStateSchemaVersion =
              [ "morphology", "ssSelfState", "learningNeedState", "knowledgeTree"
              , "truthContractStatus", "dialogueOutcomeLearning", "dialogueThread"
              , "dialogueCommitmentLedger", "dialoguePhase", "speechPolicyState"
              , "beliefStore", "governanceHistory"
              ]
          | otherwise = ["morphology", "learningNeedState", "knowledgeTree", "truthContractStatus"]
        missing = filter (\key -> not (KM.member (AK.fromText key) o)) required
    when (not (null missing)) $ fail ("missing required top-level fields: " <> show missing)
    dialogue <- DialogueState
      <$> o .: "history" <*> o .: "rawInputHistory" <*> o .: "turnCount"
      <*> o .: "lastTopic" <*> o .: "lastFamily" <*> o .: "lastForce"
      <*> o .: "lastLayer" <*> o .: "lastEmbedding" <*> o .: "consecutiveReflect"
      <*> o .: "recentFamilies" <*> o .: "activeScene" <*> o .: "userState"
      <*> o .:? "lastSalienceBias" .!= 0.0 <*> o .:? "holisticStreak" .!= 0
      <*> o .:? "recentNarrativeSuccess" .!= [] <*> o .:? "dsContext" .!= emptyContext
    identity <- IdentityState <$> o .: "ego" <*> o .: "identityClaims"
      <*> o .: "orbitalMemory" <*> o .:? "lastGuardReport" .!= Nothing
    semantic <- SemanticState
      <$> o .: "trace" <*> o .: "meaningGraph" <*> o .: "kernelPulse"
      <*> o .: "blockedConcepts" <*> o .: "clusters"
      <*> o .:? "dreamState" .!= emptyDreamState zeroVec
      <*> o .:? "intuitionState" .!= Just defaultIntuitiveState
      <*> o .:? "semanticAnchor" .!= Nothing <*> o .:? "lastTurnDecision" .!= Nothing
      <*> o .: "intuitConfidence" <*> o .:? "semanticConfig" .!= semConfig emptySemanticState
    selfState <- (o .:? "ssSelfState") >>= \case
      Just state -> pure state
      Nothing -> SelfState
        <$> o .:? "salienceWeights" .!= defaultSalienceWeights
        <*> o .:? "fieldHeuristics" .!= defaultFieldHeuristics
        <*> pure defaultConatusWeights <*> pure familyTargets
        <*> pure emptyPerspectiveRegistry <*> o .:? "essence" .!= emptyEssence
        <*> pure Nothing <*> pure Nothing <*> pure []
    SystemState dialogue identity semantic
      <$> o .: "sessionId"
      <*> (parseDialogueOutputMode <$> o .: "outputMode")
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "morphology" else o .:? "morphology" .!= MorphologyData M.empty M.empty M.empty M.empty)
      <*> o .:? "runtimeParadigms" .!= emptyRuntimeParadigms
      <*> o .: "observability" <*> pure selfState
      <*> o .:? "shadowVetoState" .!= defaultShadowVetoState
      <*> o .:? "provisionalAtoms" .!= []
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "learningNeedState" else o .:? "learningNeedState" .!= emptyLearningNeedState)
      <*> o .:? "guardrailState" .!= emptyGuardrailState
      <*> o .:? "calibrationLog" .!= emptyCalibrationLog
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "knowledgeTree" else o .:? "knowledgeTree" .!= emptyKnowledgeTree)
      <*> o .:? "toolReliability" .!= M.empty <*> o .:? "calibrationSnapshots" .!= []
      <*> o .:? "adaptiveMutationLog" .!= []
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueOutcomeLearning" else o .:? "dialogueOutcomeLearning" .!= emptyDialogueOutcomeLearningState)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueThread" else o .:? "dialogueThread" .!= emptyDialogueThread)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueCommitmentLedger" else o .:? "dialogueCommitmentLedger" .!= emptyDialogueCommitmentLedger)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialoguePhase" else o .:? "dialoguePhase" .!= Exploring)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "truthContractStatus" else o .:? "truthContractStatus" .!= LegacyIncompleteSurface)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "speechPolicyState" else o .:? "speechPolicyState" .!= emptySpeechPolicyState)
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "beliefStore" else o .:? "beliefStore" .!= emptyBeliefStore)
      <*> pure emptyGovernanceProjection
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "governanceHistory" else o .:? "governanceHistory" .!= [])
      <*> o .:? "governanceRuntimeFault" .!= Nothing <*> o .:? "semanticCommitments" .!= Nothing
      <*> o .:? "metacognition" .!= Nothing <*> o .:? "episodic" .!= Nothing
      <*> o .:? "userModel" .!= initialBeliefs <*> o .:? "mood" .!= 0.0
      <*> o .:? "currentRegime" .!= defaultRuntimeRegime
      <*> o .:? "semanticNetwork" .!= emptySemanticNetwork
      <*> o .:? "lastActivationArtifact" .!= Nothing
      <*> o .:? "ontology" .!= emptyOntology <*> o .:? "semanticSpace" .!= emptySemanticSpace
      <*> o .:? "contentSelector" .!= emptyContentSelector
      <*> o .:? "contentSelectorState" .!= Nothing
      <*> o .:? "geometricMetrics" .!= emptyIntentClassifierMetrics
      <*> o .:? "lemmaMap" .!= M.empty <*> o .:? "categoryMap" .!= M.empty
      <*> o .:? "stances" .!= M.empty <*> o .:? "stanceDefenses" .!= M.empty
      <*> o .:? "userStanceTrackers" .!= M.empty <*> o .:? "stanceLineages" .!= M.empty
      <*> o .:? "runtimeGraph" .!= seedGraph
      <*> o .:? "definitionCorpus" .!= M.empty <*> pure Nothing
      <*> o .:? "emittedPredicates" .!= Set.empty

instance ToJSON PersistenceEnvelope where
  toJSON envelope = object
    [ "persistenceEnvelopeVersion" .= peVersion envelope
    , "state" .= peState envelope
    ]

instance FromJSON PersistenceEnvelope where
  parseJSON = withObject "PersistenceEnvelope" $ \o ->
    PersistenceEnvelope
      <$> o .: "persistenceEnvelopeVersion"
      <*> o .: "state"

emptySystemState :: SystemState
emptySystemState = SystemState
  { ssDialogue = emptyDialogueState
  , ssIdentity = emptyIdentityState
  , ssSemantic = emptySemanticState
  , ssSessionId = ""
  , ssOutputMode = DialogueOutput
  , ssMorphology = MorphologyData M.empty M.empty M.empty M.empty
  , ssRuntimeParadigms = emptyRuntimeParadigms
  , ssObservability = emptyObservabilityState
  , ssSelfState = defaultSelfState
  , ssShadowVetoState = defaultShadowVetoState
  , ssProvisionalAtoms = []
  , ssLearningNeedState = emptyLearningNeedState
  , ssGuardrailState = emptyGuardrailState
  , ssCalibrationLog = emptyCalibrationLog
  , ssKnowledgeTree = emptyKnowledgeTree
  , ssToolReliability = M.empty
  , ssCalibrationSnapshots = []
  , ssAdaptiveMutationLog = []
  , ssDialogueOutcomeLearning = emptyDialogueOutcomeLearningState
  , ssDialogueThread = emptyDialogueThread
  , ssDialogueCommitmentLedger = emptyDialogueCommitmentLedger
  , ssDialoguePhase = Exploring
  , ssTruthContractStatus = LegacyIncompleteSurface
  , ssSpeechPolicyState = emptySpeechPolicyState
  , ssBeliefStore = emptyBeliefStore
  , ssGovernanceProjection = emptyGovernanceProjection
  , ssGovernanceHistory = []
  , ssGovernanceRuntimeFault = Nothing
  , ssSemanticCommitments = Nothing
  , ssMetacognition = Nothing
  , ssEpisodic = Just (EpisodicStore Seq.empty emptyIndex HS.empty 0)
  , ssUserModel = initialBeliefs
  , ssMood = 0.0
  , ssCurrentRegime = defaultRuntimeRegime
  , ssSemanticNetwork = seedFromCorpus M.empty
  , ssLastActivationArtifact = Nothing
  , ssOntology = emptyOntology
  , ssSemanticSpace = emptySemanticSpace
  , ssContentSelector = emptyContentSelector
  , ssContentSelectorState = Nothing
  , ssGeometricMetrics = emptyIntentClassifierMetrics
  , ssLemmaMap = M.empty
  , ssCategoryMap = M.empty
  , ssStances = M.empty
  , ssStanceDefenses = M.empty
  , ssUserStanceTrackers = M.empty
  , ssStanceLineages = M.empty
  , ssRuntimeGraph = seedGraph
  , ssDefinitionCorpus = M.empty
  , ssCuratedOverlay = Nothing
  , ssEmittedPredicates = Set.empty
  }

currentSystemStateSchemaVersion :: Int
currentSystemStateSchemaVersion = 2

emptyGovernanceProjection :: GovernanceProjection
emptyGovernanceProjection = GovernanceProjection
  { gpMeta = ProjectionMeta currentProjectionVersion currentReducerVersion (Just 0)
  , gpPerspectiveRegistry = emptyPerspectiveRegistry
  , gpActivePerspectiveProjections = []
  , gpGovernedRefs = []
  , gpProjectionChecksum = "governance_projection_empty"
  }
