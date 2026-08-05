{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Leaf atom/relation graph contracts. Corpus seeding and traversal live in Semantic.
module QxFx0.Types.Semantic.AtomGraph
  ( Atom(..)
  , AtomId(..)
  , AtomCategory(..)
  , RelationType(..)
  , Relation(..)
  , ObjectCase(..)
  , RelationSource(..)
  , PathProof(..)
  , AtomGraph(..)
  , GeneratedSurface(..)
  , emptyAtomGraph
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)

newtype AtomId = AtomId Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON, ToJSONKey, FromJSONKey)

data AtomCategory = CatTopic | CatConcept | CatProperty | CatProcess | CatDiscovered | CatDomain
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Atom = Atom
  { atomId :: !AtomId
  , atomSurface :: !Text
  , atomDisplay :: !Text
  , atomHead :: !Text
  , atomCategory :: !AtomCategory
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data RelationType
  = RelPresupposes | RelLimitedBy | RelRequires | RelClaims | RelVerifiedBy
  | RelSignals | RelTransformsInto | RelExpresses | RelDiffersFrom | RelRelatedTo
  | RelDirectedAt | RelPreserves | RelOrientsToward | RelPrescribes | RelBuiltThrough
  | RelDenotes | RelStructures | RelDetermines | RelTransforms | RelGives | RelReveals
  | RelRecognizes | RelUnifies | RelConnects | RelPrecedes | RelDependsOn | RelIncludes
  | RelNecessaryFor | RelEvokes | RelMeans | RelSays | RelNegates | RelContrastsWith
  | RelNotReducibleTo | RelIsNot | RelCapableOf | RelCreatedFrom | RelReliesOn | RelCanBe
  | RelDestroys | RelPointsTo | RelMakes | RelIsA | RelReconstructs | RelSupports
  | RelSets | RelNotJustCopies | RelEnables | RelCauses | RelInfluences | RelPartOf
  | RelOpposes
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic, Read)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ObjectCase = CaseNominative | CaseAccusative | CaseGenitive | CaseInstrumental
  | CaseDative | CasePrepositional | CaseSpecial
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data RelationSource = SeedFromPredicate | Curated | PromotedSubstrate | SubstrateExtractedRaw
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Relation = Relation
  { relFrom :: !AtomId
  , relTo :: !AtomId
  , relType :: !RelationType
  , relObjectCase :: !ObjectCase
  , relObjectText :: !Text
  , relVerbText :: !(Maybe Text)
  , relRuOriginal :: !Text
  , relEnOriginal :: !Text
  , relSource :: !RelationSource
  , relTopic :: !Text
  , relRationale :: !(Maybe Text)
  , relCounter :: !(Maybe Text)
  , relSynthesis :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data PathProof = PathProof
  { ppEdges :: ![Relation]
  , ppTopic :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data AtomGraph = AtomGraph
  { agRelations :: ![Relation]
  , agByFrom :: !(Map AtomId [Relation])
  , agVersion :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON)

instance FromJSON AtomGraph where
  parseJSON = withObject "AtomGraph" $ \o -> do
    rels <- o .: "agRelations"
    mIdx <- o .:? "agByFrom" .!= M.empty
    ver <- o .:? "agVersion" .!= "legacy"
    let idx = if M.null mIdx && not (null rels) then buildIndex rels else mIdx
    pure (AtomGraph rels idx ver)

data GeneratedSurface = GeneratedSurface
  { gsText :: !Text
  , gsPaths :: ![PathProof]
  , gsProvenance :: ![RelationSource]
  , gsDepthScore :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptyAtomGraph :: AtomGraph
emptyAtomGraph = AtomGraph [] M.empty "empty"

buildIndex :: [Relation] -> Map AtomId [Relation]
buildIndex = foldl' (\acc relation -> M.insertWith (++) (relFrom relation) [relation] acc) M.empty
