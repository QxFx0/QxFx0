{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Canonical top-level persisted system state plus compatibility accessors. -}
module QxFx0.Types.State.System
  ( SystemState(..)
  , ssHistory
  , ssRawInputHistory
  , ssTurnCount
  , ssLastFamily
  , ssLastTopic
  , ssLastForce
  , ssLastLayer
  , ssLastEmbedding
  , ssConsecutiveReflect
  , ssRecentFamilies
  , ssActiveScene
  , ssUserState
  , ssEgo
  , ssIdentityClaims
  , ssOrbitalMemory
  , ssLastGuardReport
  , ssTrace
  , ssMeaningGraph
  , ssDiscourse
  , ssSemanticConfig
  , ssKernelPulse
  , ssBlockedConcepts
  , ssClusters
  , ssSemanticAnchor
  , ssLastTurnDecision
  , ssIntuitConfidence
  , ssDreamState
  , ssDreamAxiom
  , ssIntuitionState
  , ssLastSalienceBias
  , ssHolisticStreak
  , ssRecentNarrativeSuccess
  , ssSalienceWeights
  , ssFieldHeuristics
  , emptySystemState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Decision (DialogueOutputMode(..), dialogueOutputModeText, parseDialogueOutputMode, SemanticAnchor, TurnDecision)
import QxFx0.Types.Domain
  ( AtomTrace
  , CanonicalMoveFamily
  , ClusterDef
  , Embedding
  , IdentityClaimRef
  , IllocutionaryForce
  , MorphologyData(..)
  , SemanticLayer
  , SemanticScene
  , UserState
  )
import QxFx0.Types.Dream (DreamState)
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Types.Intuition (IntuitiveState, defaultIntuitiveState)
import QxFx0.Types.Observability
  ( KernelPulse
  , MeaningGraph
  , ObservabilityState
  , emptyObservabilityState
  )
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Types.State.Dialogue
  ( DialogueState(..)
  , emptyDialogueState
  )
import QxFx0.Types.State.Discourse
  ( DiscourseState
  , emptyDiscourseState
  )
import QxFx0.Types.SemanticConfig
  ( SemanticConfig
  , defaultSemanticConfig
  )
import QxFx0.Types.State.Identity
  ( EgoState
  , IdentityState(..)
  , emptyIdentityState
  )
import QxFx0.Types.State.Semantic
  ( SemanticState(..)
  , emptySemanticState
  )
import QxFx0.Types.Vec (zeroVec)
import QxFx0.Types.Dream (emptyDreamState)
import QxFx0.Self.Essence (Essence, emptyEssence)
import QxFx0.Self.Salience (SalienceWeights, defaultSalienceWeights)
import QxFx0.Self.Field (FieldHeuristics, defaultFieldHeuristics)
import QxFx0.Types.Domain.Atoms (ProvisionalAtom)
import QxFx0.Types.ShadowDivergence (ShadowVetoState, defaultShadowVetoState)

data SystemState = SystemState
  { ssDialogue :: !DialogueState
  , ssIdentity :: !IdentityState
  , ssSemantic :: !SemanticState
  , ssSessionId :: !Text
  , ssOutputMode :: !DialogueOutputMode
  , ssMorphology :: !MorphologyData
  , ssObservability :: !ObservabilityState
  , ssEssence :: !Essence
    -- ^ Phase 9: essence-selection trajectory accumulator.
    --   Carries the uncommitted (or committed) 'Essence' across
    --   turns.  Initialised to 'emptyEssence'.
  , ssSalienceWeights :: !SalienceWeights
    -- ^ Phase B: mutable salience weights for post-commitment
    --   bounded self-tuning.  Initialised to 'defaultSalienceWeights'.
  , ssFieldHeuristics :: !FieldHeuristics
    -- ^ Phase B: mutable field heuristics for post-commitment
    --   bounded self-tuning.  Initialised to 'defaultFieldHeuristics'.
  , ssShadowVetoState :: !ShadowVetoState
    -- ^ WP2 (GAP2): bounded shadow-veto counter and window anchor.
    --   Tracks gate-trigger count within a sliding window to prevent
    --   infinite shadow-verdict loops.  Initialised to
  , ssProvisionalAtoms :: ![ProvisionalAtom]
    -- ^ WP3 (GAP3): provisional-atom quarantine for ontology accretion.
    --   Atoms observed from user input that do not yet match canonical
    --   clusters are held here until they meet promotion criteria or
    --   decay.  Initialised to '[]'.
    --   'defaultShadowVetoState'.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SystemState where
  toJSON ss = object
    [ "history" .= dsHistory (ssDialogue ss)
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
    , "observability" .= ssObservability ss
    , "essence" .= ssEssence ss
    , "salienceWeights" .= ssSalienceWeights ss
    , "fieldHeuristics" .= ssFieldHeuristics ss
    , "shadowVetoState" .= ssShadowVetoState ss
    , "provisionalAtoms" .= ssProvisionalAtoms ss
    ]

instance FromJSON SystemState where
  parseJSON = withObject "SystemState" $ \o -> do
    ds <- DialogueState
      <$> o .: "history"
      <*> o .: "rawInputHistory"
      <*> o .: "turnCount"
      <*> o .: "lastTopic"
      <*> o .: "lastFamily"
      <*> o .: "lastForce"
      <*> o .: "lastLayer"
      <*> o .: "lastEmbedding"
      <*> o .: "consecutiveReflect"
      <*> o .: "recentFamilies"
      <*> o .: "activeScene"
      <*> o .: "userState"
      <*> o .:? "lastSalienceBias" .!= 0.0
      <*> o .:? "holisticStreak" .!= 0
      <*> o .:? "recentNarrativeSuccess" .!= []
    ids <- IdentityState
      <$> o .: "ego"
      <*> o .: "identityClaims"
      <*> o .: "orbitalMemory"
      <*> o .:? "lastGuardReport" .!= Nothing
    sem <- SemanticState
      <$> o .: "trace"
      <*> o .: "meaningGraph"
      <*> o .: "kernelPulse"
      <*> o .: "blockedConcepts"
      <*> o .: "clusters"
      <*> o .:? "dreamState" .!= emptyDreamState zeroVec
      <*> o .:? "intuitionState" .!= Just defaultIntuitiveState
      <*> o .:? "semanticAnchor" .!= Nothing
      <*> o .:? "lastTurnDecision" .!= Nothing
      <*> o .: "intuitConfidence"
    SystemState ds ids sem
      <$> o .: "sessionId"
      <*> (parseDialogueOutputMode <$> o .: "outputMode")
      <*> o .:? "morphology" .!= MorphologyData M.empty M.empty M.empty M.empty
      <*> o .: "observability"
      <*> o .:? "essence" .!= emptyEssence
      <*> o .:? "salienceWeights" .!= defaultSalienceWeights
      <*> o .:? "fieldHeuristics" .!= defaultFieldHeuristics
      <*> o .:? "shadowVetoState" .!= defaultShadowVetoState
      <*> o .:? "provisionalAtoms" .!= []

ssHistory :: SystemState -> Seq Text
ssHistory = dsHistory . ssDialogue

ssRawInputHistory :: SystemState -> Seq Text
ssRawInputHistory = dsRawInputHistory . ssDialogue

ssTurnCount :: SystemState -> Int
ssTurnCount = dsTurnCount . ssDialogue

ssLastFamily :: SystemState -> CanonicalMoveFamily
ssLastFamily = dsLastFamily . ssDialogue

ssLastTopic :: SystemState -> Text
ssLastTopic = dsLastTopic . ssDialogue

ssLastForce :: SystemState -> IllocutionaryForce
ssLastForce = dsLastForce . ssDialogue

ssLastLayer :: SystemState -> SemanticLayer
ssLastLayer = dsLastLayer . ssDialogue

ssLastEmbedding :: SystemState -> Maybe Embedding
ssLastEmbedding = dsLastEmbedding . ssDialogue

ssConsecutiveReflect :: SystemState -> Int
ssConsecutiveReflect = dsConsecutiveReflect . ssDialogue

ssRecentFamilies :: SystemState -> [CanonicalMoveFamily]
ssRecentFamilies = dsRecentFamilies . ssDialogue

ssActiveScene :: SystemState -> SemanticScene
ssActiveScene = dsActiveScene . ssDialogue

ssUserState :: SystemState -> UserState
ssUserState = dsUserState . ssDialogue

ssEgo :: SystemState -> EgoState
ssEgo = idsEgo . ssIdentity

ssIdentityClaims :: SystemState -> [IdentityClaimRef]
ssIdentityClaims = idsIdentityClaims . ssIdentity

ssOrbitalMemory :: SystemState -> OrbitalMemory
ssOrbitalMemory = idsOrbitalMemory . ssIdentity

ssLastGuardReport :: SystemState -> Maybe IdentityGuardReport
ssLastGuardReport = idsLastGuardReport . ssIdentity

ssTrace :: SystemState -> AtomTrace
ssTrace = semTrace . ssSemantic

ssMeaningGraph :: SystemState -> MeaningGraph
ssMeaningGraph = semMeaningGraph . ssSemantic

ssDiscourse :: SystemState -> DiscourseState
ssDiscourse _ = emptyDiscourseState

ssSemanticConfig :: SystemState -> SemanticConfig
ssSemanticConfig _ = defaultSemanticConfig

ssKernelPulse :: SystemState -> KernelPulse
ssKernelPulse = semKernelPulse . ssSemantic

ssBlockedConcepts :: SystemState -> [Text]
ssBlockedConcepts = semBlockedConcepts . ssSemantic

ssClusters :: SystemState -> [ClusterDef]
ssClusters = semClusters . ssSemantic

ssSemanticAnchor :: SystemState -> Maybe SemanticAnchor
ssSemanticAnchor = semSemanticAnchor . ssSemantic

ssLastTurnDecision :: SystemState -> Maybe TurnDecision
ssLastTurnDecision = semLastTurnDecision . ssSemantic

ssIntuitConfidence :: SystemState -> Double
ssIntuitConfidence = semIntuitConfidence . ssSemantic

ssDreamAxiom :: SystemState -> Text
-- COMPAT GLUE: Source v2 had ssDreamAxiom field; target does not.
-- Returning empty text preserves old callers without adding persistent state.
ssDreamAxiom _ = ""

ssDreamState :: SystemState -> DreamState
ssDreamState = semDreamState . ssSemantic

ssIntuitionState :: SystemState -> Maybe IntuitiveState
ssIntuitionState = semIntuitionState . ssSemantic

ssLastSalienceBias :: SystemState -> Double
ssLastSalienceBias = dsLastSalienceBias . ssDialogue

ssHolisticStreak :: SystemState -> Int
ssHolisticStreak = dsHolisticStreak . ssDialogue

ssRecentNarrativeSuccess :: SystemState -> [Bool]
ssRecentNarrativeSuccess = dsRecentNarrativeSuccess . ssDialogue

emptySystemState :: SystemState
emptySystemState = SystemState
  { ssDialogue = emptyDialogueState
  , ssIdentity = emptyIdentityState
  , ssSemantic = emptySemanticState
  , ssSessionId = ""
  , ssOutputMode = DialogueOutput
  , ssMorphology = MorphologyData M.empty M.empty M.empty M.empty
  , ssObservability = emptyObservabilityState
  , ssEssence = emptyEssence
  , ssSalienceWeights = defaultSalienceWeights
  , ssFieldHeuristics = defaultFieldHeuristics
  , ssShadowVetoState = defaultShadowVetoState
  , ssProvisionalAtoms = []
  }
