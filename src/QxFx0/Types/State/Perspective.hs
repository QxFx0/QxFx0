{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Canonical persisted perspective registry and runtime-safe projection DTOs. -}
module QxFx0.Types.State.Perspective
  ( PerspectiveId(..)
  , PerspectiveVersionId(..)
  , NormativeProfileId(..)
  , PerspectiveScope(..)
  , EvidenceRef(..)
  , ClaimStanceRef(..)
  , CounterargumentRef(..)
  , IdentitySlice(..)
  , ConatusSlice(..)
  , NormativeProfile(..)
  , PerspectiveInputBundle(..)
  , PerspectiveCandidate(..)
  , PerspectiveAdmissibility(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveStatus(..)
  , PerspectiveRevisionRecord(..)
  , EndorsedPerspective(..)
  , PerspectiveProjection(..)
  , PerspectiveThread(..)
  , PerspectiveRegistry(..)
  , defaultNormativeProfileId
  , defaultNormativeProfile
  , defaultPerspectiveRegistry
  , emptyPerspectiveRegistry
  , renderPerspectiveScope
  , renderPerspectiveId
  , renderPerspectiveStatus
  , latestEndorsedPerspective
  , activeEndorsedPerspective
  , activePerspectiveProjectionScope
  , activePerspectiveProjectionScopes
  ) where

import Control.Applicative (empty)
import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:?)
  , (.!=)
  , (.=)
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)
import Data.List (sortOn)
import Data.Ord (Down(..))

newtype PerspectiveId = PerspectiveId { unPerspectiveId :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype PerspectiveVersionId = PerspectiveVersionId { unPerspectiveVersionId :: Int }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype NormativeProfileId = NormativeProfileId { unNormativeProfileId :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveScope
  = ScopeTopic Text
  | ScopeTheme Text
  | ScopeCluster Text
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype EvidenceRef = EvidenceRef { unEvidenceRef :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype ClaimStanceRef = ClaimStanceRef { unClaimStanceRef :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype CounterargumentRef = CounterargumentRef { unCounterargumentRef :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data IdentitySlice = IdentitySlice
  { isSessionId :: !Text
  , isIdentityClaims :: ![Text]
  , isIdentityClaimCount :: !Int
  , isTurnCount :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data ConatusSlice = ConatusSlice
  { csEnergy :: !Double
  , csGateFired :: !Bool
  , csFieldConfidence :: !Double
  , csStability :: !Double
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data NormativeProfile = NormativeProfile
  { npId :: !NormativeProfileId
  , npVersionId :: !Int
  , npPriorities :: !(Map Text Double)
  , npConflictPolicy :: !Text
  , npActivationScope :: !(Maybe PerspectiveScope)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveInputBundle = PerspectiveInputBundle
  { pibScope :: !PerspectiveScope
  , pibEvidence :: ![EvidenceRef]
  , pibStanceSlice :: ![ClaimStanceRef]
  , pibIdentitySlice :: !IdentitySlice
  , pibConatusSlice :: !ConatusSlice
  , pibNormativeProfile :: !NormativeProfile
  , pibCounterarguments :: ![CounterargumentRef]
  , pibRevisionLineage :: ![PerspectiveRevisionRecord]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveCandidate = PerspectiveCandidate
  { pcScope :: !PerspectiveScope
  , pcThesis :: !Text
  , pcOrientation :: !Text
  , pcConfidence :: !Double
  , pcSupportingClaims :: ![Text]
  , pcCounterargumentPressure :: !Double
  , pcNormativeAlignment :: !Double
  , pcInternalTension :: !Double
  , pcBaseVersion :: !(Maybe PerspectiveVersionId)
  , pcNormativeProfileVersion :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveAdmissibility
  = PerspectiveInadmissible Text
  | PerspectiveAdmissibleObserved
  | PerspectiveAdmissibleQuarantined
  | PerspectiveAdmissibleAccepted
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectivePromotionDecision
  = PpdObserveOnly
  | PpdQuarantine
  | PpdAcceptBounded
  | PpdPromoteEndorsed
  | PpdReviseActive
  | PpdSuspendActive
  | PpdRollbackPrior
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveStatus
  = PerspectiveActive
  | PerspectiveContested
  | PerspectiveSuspended
  | PerspectiveRevised
  | PerspectiveWithdrawn
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveRevisionRecord = PerspectiveRevisionRecord
  { prrFromVersion :: !(Maybe PerspectiveVersionId)
  , prrToVersion :: !PerspectiveVersionId
  , prrTrigger :: !Text
  , prrEvidenceDelta :: !Double
  , prrCounterargumentDelta :: !Double
  , prrConfidenceDelta :: !Double
  , prrNormativeDelta :: !Double
  , prrNormativeProfileVersion :: !Int
  , prrDecision :: !PerspectivePromotionDecision
  , prrRollbackOf :: !(Maybe PerspectiveVersionId)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data EndorsedPerspective = EndorsedPerspective
  { epId :: !PerspectiveId
  , epVersion :: !PerspectiveVersionId
  , epScope :: !PerspectiveScope
  , epThesis :: !Text
  , epOrientation :: !Text
  , epConfidence :: !Double
  , epNormativeProfileId :: !NormativeProfileId
  , epNormativeProfileVersion :: !Int
  , epStatus :: !PerspectiveStatus
  , epCreatedTurn :: !Int
  , epEndorsedTurn :: !(Maybe Int)
  , epSupportingClaims :: ![Text]
  , epCounterarguments :: ![Text]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveProjection = PerspectiveProjection
  { ppScope :: !PerspectiveScope
  , ppSummary :: !Text
  , ppOrientation :: !Text
  , ppConfidenceBand :: !Text
  , ppCautionLevel :: !Text
  , ppContested :: !Bool
  , ppPerspectiveVersion :: !PerspectiveVersionId
  , ppNormativeProfileId :: !NormativeProfileId
  , ppNormativeProfileVersion :: !Int
  , ppEvidenceCount :: !Int
  , ppCounterargumentCount :: !Int
  , ppExplanationHandle :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveThread = PerspectiveThread
  { ptPerspectiveId :: !PerspectiveId
  , ptScope :: !PerspectiveScope
  , ptActiveVersion :: !(Maybe PerspectiveVersionId)
  , ptVersions :: ![EndorsedPerspective]
  , ptRevisionHistory :: ![PerspectiveRevisionRecord]
  , ptStatus :: !PerspectiveStatus
  , ptLastUpdatedTurn :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectiveRegistry = PerspectiveRegistry
  { prThreads :: !(Map PerspectiveScope PerspectiveThread)
  , prNormativeProfiles :: !(Map NormativeProfileId NormativeProfile)
  , prActiveNormativeProfileId :: !NormativeProfileId
  , prNextPerspectiveOrdinal :: !Int
  , prNextVersionOrdinal :: !Int
  , prMaxActivePerspectives :: !Int
  , prMaxActivePerScope :: !Int
  , prMaxRevisionsPerScope :: !Int
  , prMaxInactiveVersions :: !Int
  , prMaxLineageSlice :: !Int
  , prLastUpdatedTurn :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

instance ToJSON PerspectiveRegistry where
  toJSON registry = object
    [ "threads" .= M.elems (prThreads registry)
    , "normativeProfiles" .= M.elems (prNormativeProfiles registry)
    , "activeNormativeProfileId" .= prActiveNormativeProfileId registry
    , "nextPerspectiveOrdinal" .= prNextPerspectiveOrdinal registry
    , "nextVersionOrdinal" .= prNextVersionOrdinal registry
    , "maxActivePerspectives" .= prMaxActivePerspectives registry
    , "maxActivePerScope" .= prMaxActivePerScope registry
    , "maxRevisionsPerScope" .= prMaxRevisionsPerScope registry
    , "maxInactiveVersions" .= prMaxInactiveVersions registry
    , "maxLineageSlice" .= prMaxLineageSlice registry
    , "lastUpdatedTurn" .= prLastUpdatedTurn registry
    ]

instance FromJSON PerspectiveRegistry where
  parseJSON = withObject "PerspectiveRegistry" $ \o -> do
    threads <- o .:? "threads" .!= []
    profiles <- o .:? "normativeProfiles" .!= [defaultNormativeProfile]
    if hasDuplicateKeys (map ptScope threads) || hasDuplicateKeys (map npId profiles)
      then empty
      else pure ()
    activeProfileId <- o .:? "activeNormativeProfileId" .!= defaultNormativeProfileId
    PerspectiveRegistry
      <$> pure (M.fromList [(ptScope thread, thread) | thread <- threads])
      <*> pure (M.fromList [(npId profile, profile) | profile <- profiles])
      <*> pure activeProfileId
      <*> o .:? "nextPerspectiveOrdinal" .!= 1
      <*> o .:? "nextVersionOrdinal" .!= 1
      <*> o .:? "maxActivePerspectives" .!= 16
      <*> o .:? "maxActivePerScope" .!= 1
      <*> o .:? "maxRevisionsPerScope" .!= 12
      <*> o .:? "maxInactiveVersions" .!= 8
      <*> o .:? "maxLineageSlice" .!= 8
      <*> o .:? "lastUpdatedTurn" .!= 0

defaultNormativeProfileId :: NormativeProfileId
defaultNormativeProfileId = NormativeProfileId "default"

defaultNormativeProfile :: NormativeProfile
defaultNormativeProfile = NormativeProfile
  { npId = defaultNormativeProfileId
  , npVersionId = 1
  , npPriorities = M.fromList
      [ ("safety", 1.0)
      , ("stability", 0.9)
      , ("revision", 0.8)
      , ("counterargument", 0.7)
      ]
  , npConflictPolicy = "conservative"
  , npActivationScope = Nothing
  }

defaultPerspectiveRegistry :: PerspectiveRegistry
defaultPerspectiveRegistry = PerspectiveRegistry
  { prThreads = M.empty
  , prNormativeProfiles = M.singleton defaultNormativeProfileId defaultNormativeProfile
  , prActiveNormativeProfileId = defaultNormativeProfileId
  , prNextPerspectiveOrdinal = 1
  , prNextVersionOrdinal = 1
  , prMaxActivePerspectives = 16
  , prMaxActivePerScope = 1
  , prMaxRevisionsPerScope = 12
  , prMaxInactiveVersions = 8
  , prMaxLineageSlice = 8
  , prLastUpdatedTurn = 0
  }

emptyPerspectiveRegistry :: PerspectiveRegistry
emptyPerspectiveRegistry = defaultPerspectiveRegistry

renderPerspectiveScope :: PerspectiveScope -> Text
renderPerspectiveScope scope =
  case scope of
    ScopeTopic topic -> "topic:" <> topic
    ScopeTheme theme -> "theme:" <> theme
    ScopeCluster cluster -> "cluster:" <> cluster

renderPerspectiveId :: PerspectiveId -> Text
renderPerspectiveId (PerspectiveId value) = value

renderPerspectiveStatus :: PerspectiveStatus -> Text
renderPerspectiveStatus status =
  case status of
    PerspectiveActive -> "active"
    PerspectiveContested -> "contested"
    PerspectiveSuspended -> "suspended"
    PerspectiveRevised -> "revised"
    PerspectiveWithdrawn -> "withdrawn"

latestEndorsedPerspective :: PerspectiveThread -> Maybe EndorsedPerspective
latestEndorsedPerspective thread = case ptVersions thread of
  [] -> Nothing
  x:_ -> Just x

activeEndorsedPerspective :: PerspectiveThread -> Maybe EndorsedPerspective
activeEndorsedPerspective thread =
  case ptActiveVersion thread of
    Nothing -> Nothing
    Just versionId ->
      case filter (isActiveVersion versionId) (ptVersions thread) of
        (entry:_) -> Just entry
        [] -> Nothing
  where
    isActiveVersion versionId entry =
      epVersion entry == versionId && epStatus entry == PerspectiveActive

activePerspectiveProjectionScope :: PerspectiveRegistry -> Maybe PerspectiveScope
activePerspectiveProjectionScope registry =
  case activePerspectiveProjectionScopes registry of
    scope:_ -> Just scope
    [] -> Nothing

activePerspectiveProjectionScopes :: PerspectiveRegistry -> [PerspectiveScope]
activePerspectiveProjectionScopes registry =
  map ptScope
    . take (prMaxActivePerspectives registry)
    . sortOn (Down . ptLastUpdatedTurn)
    . filter hasProjection
    $ M.elems (prThreads registry)
  where
    hasProjection thread = activeEndorsedPerspective thread /= Nothing

hasDuplicateKeys :: Ord a => [a] -> Bool
hasDuplicateKeys values =
  M.size (M.fromList [(value, ()) | value <- values]) /= length values
