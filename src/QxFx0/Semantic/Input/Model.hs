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
  , SemanticTag(..)
  , semanticTagText
  , parseSemanticTagText
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
  , withText
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  , Value(String)
  )
import Data.Text (Text)
import qualified Data.Text as T
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

data SemanticTag
  = TagMisunderstanding
  | TagBoundaryCommand
  | TagApologyRepair
  | TagFarewellContact
  | TagGratitudeContact
  | TagAffectiveHelp
  | TagDisagreementConfront
  | TagAgreementAnchor
  | TagOpinionQuestion
  | TagSystemLogic
  | TagSelfKnowledge
  | TagGreetingSmalltalk
  | TagDialogueInvitation
  | TagShortDialogueProbe
  | TagConceptKnowledge
  | TagPurposeFunction
  | TagComparisonRelation
  | TagSelfState
  | TagGenerativePrompt
  | TagOperationalCause
  | TagWorldCause
  | TagLocationFormation
  | TagNextStep
  | TagEverydayEvent
  | TagContemplativeTopic
  | TagUnknown
  | TagCustom !Text
    -- ^ Non-standard tag for regression tests, rule identifiers, and extensibility.
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

instance FromJSON SemanticTag where
  parseJSON = withText "SemanticTag" $ \t ->
    case parseSemanticTagText t of
      Just tag -> pure tag
      Nothing  -> fail ("Unknown SemanticTag: " ++ T.unpack t)

instance ToJSON SemanticTag where
  toJSON tag = String (semanticTagText tag)

semanticTagText :: SemanticTag -> Text
semanticTagText TagMisunderstanding      = "misunderstanding"
semanticTagText TagBoundaryCommand       = "boundary_command"
semanticTagText TagApologyRepair         = "apology_repair"
semanticTagText TagFarewellContact       = "farewell_contact"
semanticTagText TagGratitudeContact      = "gratitude_contact"
semanticTagText TagAffectiveHelp        = "affective_help"
semanticTagText TagDisagreementConfront  = "disagreement_confront"
semanticTagText TagAgreementAnchor       = "agreement_anchor"
semanticTagText TagOpinionQuestion       = "opinion_question"
semanticTagText TagSystemLogic           = "system_logic"
semanticTagText TagSelfKnowledge         = "self_knowledge"
semanticTagText TagGreetingSmalltalk     = "greeting_smalltalk"
semanticTagText TagDialogueInvitation    = "dialogue_invitation"
semanticTagText TagShortDialogueProbe    = "short_dialogue_probe"
semanticTagText TagConceptKnowledge      = "concept_knowledge"
semanticTagText TagPurposeFunction       = "purpose_function"
semanticTagText TagComparisonRelation    = "comparison_relation"
semanticTagText TagSelfState            = "self_state"
semanticTagText TagGenerativePrompt      = "generative_prompt"
semanticTagText TagOperationalCause      = "operational_cause"
semanticTagText TagWorldCause            = "world_cause"
semanticTagText TagLocationFormation     = "location_formation"
semanticTagText TagNextStep              = "next_step"
semanticTagText TagEverydayEvent         = "everyday_event"
semanticTagText TagContemplativeTopic    = "contemplative_topic"
semanticTagText TagUnknown               = "unknown"
semanticTagText (TagCustom t)            = t

parseSemanticTagText :: Text -> Maybe SemanticTag
parseSemanticTagText t = case t of
  "misunderstanding"      -> Just TagMisunderstanding
  "boundary_command"      -> Just TagBoundaryCommand
  "apology_repair"        -> Just TagApologyRepair
  "farewell_contact"      -> Just TagFarewellContact
  "gratitude_contact"     -> Just TagGratitudeContact
  "affective_help"        -> Just TagAffectiveHelp
  "disagreement_confront" -> Just TagDisagreementConfront
  "agreement_anchor"      -> Just TagAgreementAnchor
  "opinion_question"      -> Just TagOpinionQuestion
  "system_logic"          -> Just TagSystemLogic
  "self_knowledge"        -> Just TagSelfKnowledge
  "greeting_smalltalk"    -> Just TagGreetingSmalltalk
  "dialogue_invitation"   -> Just TagDialogueInvitation
  "short_dialogue_probe"  -> Just TagShortDialogueProbe
  "concept_knowledge"     -> Just TagConceptKnowledge
  "purpose_function"      -> Just TagPurposeFunction
  "comparison_relation"   -> Just TagComparisonRelation
  "self_state"            -> Just TagSelfState
  "generative_prompt"     -> Just TagGenerativePrompt
  "operational_cause"     -> Just TagOperationalCause
  "world_cause"           -> Just TagWorldCause
  "location_formation"    -> Just TagLocationFormation
  "next_step"             -> Just TagNextStep
  "everyday_event"        -> Just TagEverydayEvent
  "contemplative_topic"   -> Just TagContemplativeTopic
  "unknown"               -> Just TagUnknown
  _                       -> Just (TagCustom t)

data InputRouteHint = InputRouteHint
  { irhType :: !InputRouteType
  , irhTag :: !SemanticTag
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
