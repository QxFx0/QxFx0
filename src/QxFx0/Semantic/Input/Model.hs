{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Semantic.Input.Model
  ( InputPartOfSpeech(..)
  , InputMorphFeature(..)
  , InputSyntacticRole(..)
  , InputSemanticClass(..)
  , InputDiscourseFunction(..)
  , InputClauseType(..)
  , InputSpeechAct(..)
  , InputPolarity(..)
  , InputRouteType(..)
  , InputRouteHint(..)
  , WordMeaningUnit(..)
  , UtteranceSemanticFrame(..)
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
import Data.Text (Text)
import GHC.Generics (Generic)

data InputPartOfSpeech
  = PosNoun
  | PosAdjective
  | PosVerb
  | PosAdverb
  | PosPronoun
  | PosNumeral
  | PosPreposition
  | PosConjunction
  | PosParticle
  | PosInterjection
  | PosUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputMorphFeature
  = FeatCaseNom
  | FeatCaseGen
  | FeatCaseDat
  | FeatCaseAcc
  | FeatCaseIns
  | FeatCaseLoc
  | FeatTensePast
  | FeatTensePres
  | FeatTenseFut
  | FeatMoodInd
  | FeatMoodImp
  | FeatPerson1
  | FeatPerson2
  | FeatPerson3
  | FeatNumberSing
  | FeatNumberPlur
  | FeatNegated
  | FeatQuestion
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputSyntacticRole
  = SynRoot
  | SynSubject
  | SynPredicate
  | SynObject
  | SynAttribute
  | SynCircumstance
  | SynMarker
  | SynUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputSemanticClass
  = SemWorldObject
  | SemPhysicalObject
  | SemWorldPhenomenon
  | SemMentalObject
  | SemAbstractConcept
  | SemQualityProperty
  | SemPurposeFunction
  | SemRelation
  | SemAction
  | SemState
  | SemCause
  | SemComparison
  | SemIdentity
  | SemKnowledge
  | SemDialogueRepair
  | SemDialogueInvitation
  | SemSelfReference
  | SemUserReference
  | SemContemplative
  | SemUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputDiscourseFunction
  = DiscNegation
  | DiscQuestion
  | DiscContrast
  | DiscCondition
  | DiscCause
  | DiscResult
  | DiscInvitation
  | DiscClarification
  | DiscEmphasis
  | DiscUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputClauseType
  = ClauseDeclarativeInput
  | ClauseInterrogativeInput
  | ClauseImperativeInput
  | ClauseFragmentInput
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputSpeechAct
  = ActAssert
  | ActAsk
  | ActRequest
  | ActInvite
  | ActReport
  | ActUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputPolarity
  = PolarityPositive
  | PolarityNegative
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputRouteType
  = RouteTypeDefine
  | RouteTypeDescribe
  | RouteTypeDeepen
  | RouteTypeGround
  | RouteTypeDistinguish
  | RouteTypeRepair
  | RouteTypeClarify
  | RouteTypeContact
  | RouteTypeUnknown
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data InputRouteHint = InputRouteHint
  { irhType :: !InputRouteType
  , irhTag :: !Text
  , irhReason :: !Text
  , irhRuleScore :: !Double
  , irhSemanticScore :: !Double
  , irhSyntacticScore :: !Double
  , irhEmbeddingScore :: !Double
  , irhEvidence :: ![Text]
  , irhConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON InputRouteHint where
  toJSON hint =
    object
      [ "irhType" .= irhType hint
      , "irhTag" .= irhTag hint
      , "irhReason" .= irhReason hint
      , "irhRuleScore" .= irhRuleScore hint
      , "irhSemanticScore" .= irhSemanticScore hint
      , "irhSyntacticScore" .= irhSyntacticScore hint
      , "irhEmbeddingScore" .= irhEmbeddingScore hint
      , "irhEvidence" .= irhEvidence hint
      , "irhConfidence" .= irhConfidence hint
      ]

instance FromJSON InputRouteHint where
  parseJSON = withObject "InputRouteHint" $ \o -> do
    hintType <- o .: "irhType"
    hintTag <- o .: "irhTag"
    hintReason <- o .: "irhReason"
    hintConfidence <- o .: "irhConfidence"
    hintRule <- o .:? "irhRuleScore" .!= hintConfidence
    hintSemantic <- o .:? "irhSemanticScore" .!= 0.0
    hintSyntactic <- o .:? "irhSyntacticScore" .!= 0.0
    hintEmbedding <- o .:? "irhEmbeddingScore" .!= 0.0
    hintEvidence <- o .:? "irhEvidence" .!= []
    pure InputRouteHint
      { irhType = hintType
      , irhTag = hintTag
      , irhReason = hintReason
      , irhRuleScore = hintRule
      , irhSemanticScore = hintSemantic
      , irhSyntacticScore = hintSyntactic
      , irhEmbeddingScore = hintEmbedding
      , irhEvidence = hintEvidence
      , irhConfidence = hintConfidence
      }

data WordMeaningUnit = WordMeaningUnit
  { wmuSurfaceForm :: !Text
  , wmuLemma :: !Text
  , wmuPartOfSpeech :: !InputPartOfSpeech
  , wmuMorphFeatures :: ![InputMorphFeature]
  , wmuSyntacticRole :: !InputSyntacticRole
  , wmuSemanticClasses :: ![InputSemanticClass]
  , wmuDiscourseFunctions :: ![InputDiscourseFunction]
  , wmuAmbiguityCandidates :: ![Text]
  , wmuConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data UtteranceSemanticFrame = UtteranceSemanticFrame
  { usfRawText :: !Text
  , usfNormalizedText :: !Text
  , usfWordUnits :: ![WordMeaningUnit]
  , usfClauseType :: !InputClauseType
  , usfSpeechAct :: !InputSpeechAct
  , usfPolarity :: !InputPolarity
  , usfTopic :: !Text
  , usfFocus :: !Text
  , usfAgent :: !(Maybe Text)
  , usfTarget :: !(Maybe Text)
  , usfSemanticCandidates :: ![Text]
  , usfAmbiguityLevel :: !Text
  , usfRouteHint :: !InputRouteHint
  , usfConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
