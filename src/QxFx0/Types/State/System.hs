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
  , ssKernelPulse
  , ssBlockedConcepts
  , ssClusters
  , ssSemanticAnchor
  , ssLastTurnDecision
  , ssIntuitConfidence
  , ssDreamState
  , ssIntuitionState
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

data SystemState = SystemState
  { ssDialogue :: !DialogueState
  , ssIdentity :: !IdentityState
  , ssSemantic :: !SemanticState
  , ssSessionId :: !Text
  , ssOutputMode :: !DialogueOutputMode
  , ssMorphology :: !MorphologyData
  , ssObservability :: !ObservabilityState
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

ssDreamState :: SystemState -> DreamState
ssDreamState = semDreamState . ssSemantic

ssIntuitionState :: SystemState -> Maybe IntuitiveState
ssIntuitionState = semIntuitionState . ssSemantic

emptySystemState :: SystemState
emptySystemState = SystemState
  { ssDialogue = emptyDialogueState
  , ssIdentity = emptyIdentityState
  , ssSemantic = emptySemanticState
  , ssSessionId = ""
  , ssOutputMode = DialogueOutput
  , ssMorphology = MorphologyData M.empty M.empty M.empty M.empty
  , ssObservability = emptyObservabilityState
  }
