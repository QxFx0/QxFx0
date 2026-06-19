{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Intent.GeometricClassifier
  ( ClusterId(..)
  , IntentCluster(..)
  , IntentClassifier(..)
  , ClassificationResult(..)
  , buildClassifier
  , classifyIntent
  , kNearest
  , assignToBestCluster
  , geometricFamilyRecommendation
  , intentToFamily
  , recordABValidation
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (ToJSONKey, FromJSONKey)
import Data.Hashable (hash)
import Data.List (sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Ord (comparing, Down(..))
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import QxFx0.Semantic.Space.Types (SemanticSpace(..), AtomVector(..))
import QxFx0.Semantic.Space (cosineSimilarity, projectAtoms)
import QxFx0.Types.PropositionType (PropositionType(..), propositionTypeText)
import QxFx0.Types (CanonicalMoveFamily(..))
import QxFx0.Semantic.Intent.Metrics (IntentClassifierMetrics(..))

newtype ClusterId = ClusterId Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (NFData, ToJSONKey, FromJSONKey)

data IntentCluster = IntentCluster
  { icClusterId :: !ClusterId
  , icIntent    :: !PropositionType
  , icCentroid  :: !AtomVector
  , icMembers   :: ![(Text, AtomVector)]
  , icRadius    :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data IntentClassifier = IntentClassifier
  { icSpace         :: !SemanticSpace
  , icClusters      :: !(Map ClusterId IntentCluster)
  , icMinSimilarity :: !Double
  , icK             :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data ClassificationResult
  = Classified !PropositionType !Double
  | Unclassified
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

recordABValidation :: IntentClassifierMetrics -> ClassificationResult -> CanonicalMoveFamily -> IntentClassifierMetrics
recordABValidation metrics geoResult logicFamily =
  let total' = icmTotalClassifications metrics + 1
      classified' = case geoResult of
        Classified _ _ -> icmClassifiedCount metrics + 1
        Unclassified   -> icmUnclassifiedCount metrics
      unclassified' = case geoResult of
        Classified _ _ -> icmUnclassifiedCount metrics
        Unclassified   -> icmUnclassifiedCount metrics + 1
      (agree', disagree') = case geoResult of
        Classified intent _ ->
          case intentToFamily intent of
            Just geoFamily | geoFamily == logicFamily ->
              (icmAgreementCount metrics + 1, icmDisagreementCount metrics)
            _ ->
              (icmAgreementCount metrics, icmDisagreementCount metrics + 1)
        Unclassified ->
          (icmAgreementCount metrics, icmDisagreementCount metrics)
  in IntentClassifierMetrics
    { icmTotalClassifications = total'
    , icmClassifiedCount = classified'
    , icmUnclassifiedCount = unclassified'
    , icmAgreementCount = agree'
    , icmDisagreementCount = disagree'
    }

buildClassifier :: SemanticSpace -> Map PropositionType (Set Text) -> IntentClassifier
buildClassifier space labeledFacts =
  let clusters = M.fromList
        [ (ClusterId (hash (propositionTypeText intent)), buildCluster space intent atomSet)
        | (intent, atomSet) <- M.toList labeledFacts
        ]
  in IntentClassifier
    { icSpace = space
    , icClusters = clusters
    , icMinSimilarity = 0.15
    , icK = 3
    }

buildCluster :: SemanticSpace -> PropositionType -> Set Text -> IntentCluster
buildCluster space intent atomSet =
  let vec = projectAtoms atomSet space
      cid = ClusterId (hash (propositionTypeText intent))
  in IntentCluster
    { icClusterId = cid
    , icIntent = intent
    , icCentroid = vec
    , icMembers = [(T.pack (show intent), vec)]
    , icRadius = 0.0
    }

classifyIntent :: IntentClassifier -> Set Text -> ClassificationResult
classifyIntent classifier atoms =
  let queryVec = projectAtoms atoms (icSpace classifier)
      neighbors = kNearest queryVec (icClusters classifier) (icK classifier)
      bestCluster = assignToBestCluster neighbors (icClusters classifier)
  in case bestCluster of
    Just (cluster, sim) | sim >= icMinSimilarity classifier ->
      Classified (icIntent cluster) sim
    _ -> Unclassified

kNearest :: AtomVector -> Map ClusterId IntentCluster -> Int -> [(ClusterId, Double)]
kNearest query clusters k =
  let sims = [ (cid, cosineSimilarity query (icCentroid cluster))
             | (cid, cluster) <- M.toList clusters
             ]
      sorted = sortBy (comparing (Down . snd)) sims
  in take k sorted

assignToBestCluster :: [(ClusterId, Double)] -> Map ClusterId IntentCluster -> Maybe (IntentCluster, Double)
assignToBestCluster [] _ = Nothing
assignToBestCluster ((cid, sim):_) clusters =
  case M.lookup cid clusters of
    Just cluster -> Just (cluster, sim)
    Nothing -> Nothing

geometricFamilyRecommendation :: IntentClassifier -> Set Text -> [(CanonicalMoveFamily, Double)]
geometricFamilyRecommendation classifier atoms =
  case classifyIntent classifier atoms of
    Classified intent sim ->
      case intentToFamily intent of
        Just fam -> [(fam, sim)]
        Nothing -> []
    Unclassified -> []

intentToFamily :: PropositionType -> Maybe CanonicalMoveFamily
intentToFamily DefinitionalQ      = Just CMDefine
intentToFamily ConceptKnowledgeQ  = Just CMDefine
intentToFamily SelfKnowledgeQ     = Just CMReflect
intentToFamily DistinctionQ       = Just CMDistinguish
intentToFamily ConfrontQ          = Just CMConfront
intentToFamily GroundQ            = Just CMGround
intentToFamily RepairSignal       = Just CMRepair
intentToFamily ContactSignal      = Just CMContact
intentToFamily PurposeQ           = Just CMPurpose
intentToFamily WorldCauseQ        = Just CMHypothesis
intentToFamily DeepenQ            = Just CMDeepen
intentToFamily NextStepQ          = Just CMNextStep
intentToFamily _                  = Nothing
