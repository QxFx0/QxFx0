{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Decision.Model
  ( ClaimAst(..)
  , GfModifier(..)
  , GfVP(..)
  , GfNP(..)
  , GfRelation(..)
  , GfMechanism(..)
  , GfNumber(..)
  , GfActTopic(..)
  , ResponseMeaningPlan(..)
  , ResponseContentPlan(..)
  , InputPropositionFrame(..)
  , emptyInputPropositionFrame
  , SemanticAnchor(..)
  , IdentitySignalSnapshot(..)
  , TurnDecision(..)
  , LegitimacyOutcome(..)
  , classifyLegitimacyOutcome
  , SubjectState(..)
  , IsLegit(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import Data.Aeson.Types (Parser, parseFail)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Config.Decision (defaultInputPropositionConfidence)
import QxFx0.Types.ClaimAst
  ( ClaimAst(..)
  , GfModifier(..)
  , GfVP(..)
  , GfNP(..)
  , GfRelation(..)
  , GfMechanism(..)
  , GfNumber(..)
  , GfActTopic(..)
  )
import QxFx0.Types.Decision.Enums
import QxFx0.Types.Domain
  ( CanonicalMoveFamily(..)
  , ClauseForm(..)
  , IllocutionaryForce(..)
  , NixGuardStatus
  , Register(..)
  , SemanticLayer(..)
  , WarrantedMoveMode(..)
  )
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Types.Observability (ContractProvenance, ResponseStrategy, TruthContractStatus(..))
import QxFx0.Types.Orbital
  ( DirectiveMoveBias
  , EncounterMode
  , OrbitalPhase
  )
import QxFx0.Types.Thresholds (DepthMode, LegitimacyStatus(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..))
import QxFx0.Types.Sense (MicroPlan, ResponseSensePlan, RhetoricalMove(..), FallbackPolicy(..), ImplicationDirection(..), emptyMicroPlan, emptyResponseSensePlan)
import QxFx0.Types.State.Perspective (PerspectiveScope)
import QxFx0.Types.PropositionType (PropositionType(..), propositionTypeFromText)

data ResponseMeaningPlan = ResponseMeaningPlan
  { rmpFamily :: !CanonicalMoveFamily
  , rmpForce :: !IllocutionaryForce
  , rmpSpeechAct :: !SpeechAct
  , rmpRelation :: !SemanticRelation
  , rmpStrategy :: !AnswerStrategy
  , rmpStance :: !StanceMarker
  , rmpEpistemic :: !EpistemicStatus
  , rmpTopic :: !Text
  , rmpPrimaryClaim :: !Text
  , rmpPrimaryClaimAst :: !(Maybe ClaimAst)
  , rmpScope :: !(Maybe PerspectiveScope)
  , rmpContrastAxis :: !Text
  , rmpImplicationDirection :: !ImplicationDirection
  , rmpProvenance :: !ContractProvenance
  , rmpTruthContractStatus :: !TruthContractStatus
  , rmpCommitmentStrength :: !Double
  , rmpDepthMode :: !DepthMode
  , rmpSensePlan :: !ResponseSensePlan
  , rmpMicroPlan :: !MicroPlan
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON ResponseMeaningPlan where
  toJSON rmp = object
    [ "rmpFamily" .= rmpFamily rmp
    , "rmpForce" .= rmpForce rmp
    , "rmpSpeechAct" .= rmpSpeechAct rmp
    , "rmpRelation" .= rmpRelation rmp
    , "rmpStrategy" .= rmpStrategy rmp
    , "rmpStance" .= rmpStance rmp
    , "rmpEpistemic" .= rmpEpistemic rmp
    , "rmpTopic" .= rmpTopic rmp
    , "rmpPrimaryClaim" .= rmpPrimaryClaim rmp
    , "rmpPrimaryClaimAst" .= rmpPrimaryClaimAst rmp
    , "rmpScope" .= rmpScope rmp
    , "rmpContrastAxis" .= rmpContrastAxis rmp
    , "rmpImplicationDirection" .= rmpImplicationDirection rmp
    , "rmpProvenance" .= rmpProvenance rmp
    , "rmpTruthContractStatus" .= rmpTruthContractStatus rmp
    , "rmpCommitmentStrength" .= rmpCommitmentStrength rmp
    , "rmpDepthMode" .= rmpDepthMode rmp
    , "rmpSensePlan" .= rmpSensePlan rmp
    , "rmpMicroPlan" .= rmpMicroPlan rmp
    ]

instance FromJSON ResponseMeaningPlan where
  parseJSON = withObject "ResponseMeaningPlan" $ \o ->
    ResponseMeaningPlan
      <$> o .: "rmpFamily"
      <*> o .: "rmpForce"
      <*> o .: "rmpSpeechAct"
      <*> o .: "rmpRelation"
      <*> o .: "rmpStrategy"
      <*> o .: "rmpStance"
      <*> o .: "rmpEpistemic"
      <*> o .: "rmpTopic"
      <*> o .: "rmpPrimaryClaim"
      <*> o .:? "rmpPrimaryClaimAst"
      <*> o .:? "rmpScope"
      <*> o .: "rmpContrastAxis"
      <*> o .: "rmpImplicationDirection"
      <*> o .: "rmpProvenance"
      <*> o .:? "rmpTruthContractStatus" .!= LegacyIncompleteSurface
      <*> o .: "rmpCommitmentStrength"
      <*> o .: "rmpDepthMode"
      <*> o .:? "rmpSensePlan" .!= emptyResponseSensePlan
      <*> o .:? "rmpMicroPlan" .!= emptyMicroPlan

data ResponseContentPlan = ResponseContentPlan
  { rcpFamily :: !CanonicalMoveFamily
  , rcpOpening :: !ContentMove
  , rcpCore :: !ContentMove
  , rcpLimit :: !ContentMove
  , rcpContinuation :: !ContentMove
  , rcpStyle :: !RenderStyle
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON ResponseContentPlan where
  toJSON responseContentPlan = object
    [ "family" .= rcpFamily responseContentPlan
    , "opening" .= rcpOpening responseContentPlan
    , "core" .= rcpCore responseContentPlan
    , "limit" .= rcpLimit responseContentPlan
    , "continuation" .= rcpContinuation responseContentPlan
    , "style" .= renderStyleText (rcpStyle responseContentPlan)
    ]

instance FromJSON ResponseContentPlan where
  parseJSON = withObject "ResponseContentPlan" $ \objectValue ->
    ResponseContentPlan
      <$> objectValue .: "family"
      <*> objectValue .: "opening"
      <*> objectValue .: "core"
      <*> objectValue .: "limit"
      <*> objectValue .: "continuation"
      <*> (parseRenderStyle <$> objectValue .: "style")

data InputPropositionFrame = InputPropositionFrame
  { ipfRawText :: !Text
  , ipfPropositionType :: !PropositionType
  , ipfFocusEntity :: !Text
  , ipfFocusNominative :: !Text
  , ipfSemanticSubject :: !Text
  , ipfSemanticTarget :: !Text
  , ipfSemanticCandidates :: ![Text]
  , ipfSemanticEvidence :: ![Text]
  , ipfCanonicalFamily :: !CanonicalMoveFamily
  , ipfIllocutionaryForce :: !IllocutionaryForce
  , ipfClauseForm :: !ClauseForm
  , ipfSemanticLayer :: !SemanticLayer
  , ipfKeyPhrases :: ![Text]
  , ipfEmotionalTone :: !EmotionalTone
  , ipfConfidence :: !Double
  , ipfIsQuestion :: !Bool
  , ipfIsNegated :: !Bool
  , ipfRegisterHint :: !Register
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON InputPropositionFrame where
  toJSON frame = object
    [ "ipfRawText" .= ipfRawText frame
    , "ipfPropositionType" .= propositionTypeText (ipfPropositionType frame)
    , "ipfFocusEntity" .= ipfFocusEntity frame
    , "ipfFocusNominative" .= ipfFocusNominative frame
    , "ipfSemanticSubject" .= ipfSemanticSubject frame
    , "ipfSemanticTarget" .= ipfSemanticTarget frame
    , "ipfSemanticCandidates" .= ipfSemanticCandidates frame
    , "ipfSemanticEvidence" .= ipfSemanticEvidence frame
    , "ipfCanonicalFamily" .= ipfCanonicalFamily frame
    , "ipfIllocutionaryForce" .= ipfIllocutionaryForce frame
    , "ipfClauseForm" .= ipfClauseForm frame
    , "ipfSemanticLayer" .= ipfSemanticLayer frame
    , "ipfKeyPhrases" .= ipfKeyPhrases frame
    , "ipfEmotionalTone" .= ipfEmotionalTone frame
    , "ipfConfidence" .= ipfConfidence frame
    , "ipfIsQuestion" .= ipfIsQuestion frame
    , "ipfIsNegated" .= ipfIsNegated frame
    , "ipfRegisterHint" .= ipfRegisterHint frame
    ]

instance FromJSON InputPropositionFrame where
  parseJSON = withObject "InputPropositionFrame" $ \o ->
    InputPropositionFrame
      <$> o .: "ipfRawText"
      <*> (o .: "ipfPropositionType" >>= parsePropositionTypeText)
      <*> o .: "ipfFocusEntity"
      <*> o .: "ipfFocusNominative"
      <*> o .: "ipfSemanticSubject"
      <*> o .: "ipfSemanticTarget"
      <*> o .: "ipfSemanticCandidates"
      <*> o .: "ipfSemanticEvidence"
      <*> o .: "ipfCanonicalFamily"
      <*> o .: "ipfIllocutionaryForce"
      <*> o .: "ipfClauseForm"
      <*> o .: "ipfSemanticLayer"
      <*> o .: "ipfKeyPhrases"
      <*> o .: "ipfEmotionalTone"
      <*> o .: "ipfConfidence"
      <*> o .: "ipfIsQuestion"
      <*> o .: "ipfIsNegated"
      <*> o .: "ipfRegisterHint"

propositionTypeText :: PropositionType -> Text
propositionTypeText = T.pack . show

parsePropositionTypeText :: Text -> Parser PropositionType
parsePropositionTypeText t =
  case propositionTypeFromText t of
    Just pt -> pure pt
    Nothing -> parseFail ("Unknown PropositionType: " ++ T.unpack t)

emptyInputPropositionFrame :: InputPropositionFrame
emptyInputPropositionFrame = InputPropositionFrame
  { ipfRawText = ""
  , ipfPropositionType = PlainAssert
  , ipfFocusEntity = ""
  , ipfFocusNominative = ""
  , ipfSemanticSubject = ""
  , ipfSemanticTarget = ""
  , ipfSemanticCandidates = []
  , ipfSemanticEvidence = []
  , ipfCanonicalFamily = CMGround
  , ipfIllocutionaryForce = IFAssert
  , ipfClauseForm = Declarative
  , ipfSemanticLayer = ContentLayer
  , ipfKeyPhrases = []
  , ipfEmotionalTone = ToneNeutral
  , ipfConfidence = defaultInputPropositionConfidence
  , ipfIsQuestion = False
  , ipfIsNegated = False
  , ipfRegisterHint = Neutral
  }

data SemanticAnchor = SemanticAnchor
  { saDominantChannel :: !DominantChannel
  , saSecondaryChannel :: !(Maybe Text)
  , saEstablishedAtTurn :: !Int
  , saStrength :: !Double
  , saStability :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticAnchor where toJSON = genericToJSON defaultOptions
instance FromJSON SemanticAnchor where parseJSON = genericParseJSON defaultOptions

data IdentitySignalSnapshot = IdentitySignalSnapshot
  { issOrbitalPhase :: !OrbitalPhase
  , issEncounterMode :: !EncounterMode
  , issContactStrength :: !Double
  , issBoundaryStrength :: !Double
  , issAbstractionBudget :: !Int
  , issMoveBias :: !DirectiveMoveBias
  , issRegister :: !Register
  , issNeedLayer :: !SemanticLayer
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON IdentitySignalSnapshot where toJSON = genericToJSON defaultOptions
instance FromJSON IdentitySignalSnapshot where parseJSON = genericParseJSON defaultOptions

data TurnDecision = TurnDecision
  { tdFamily :: !CanonicalMoveFamily
  , tdForce :: !IllocutionaryForce
  , tdRenderStrategy :: !ResponseStrategy
  , tdRenderStyle :: !RenderStyle
  , tdGuardStatus :: !NixGuardStatus
  , tdGuardReport :: !IdentityGuardReport
  , tdLegitimacy :: !Double
  , tdIdentity :: !IdentitySignalSnapshot
  , tdSemanticAnchor :: !(Maybe SemanticAnchor)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON TurnDecision where toJSON = genericToJSON defaultOptions
instance FromJSON TurnDecision where parseJSON = genericParseJSON defaultOptions

data LegitimacyOutcome = LegitimacyOutcome
  { loDisposition :: !DecisionDisposition
  , loStatus :: !LegitimacyStatus
  , loReason :: !LegitimacyReason
  , loWarrantedMode :: !WarrantedMoveMode
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON LegitimacyOutcome where toJSON = genericToJSON defaultOptions
instance FromJSON LegitimacyOutcome where parseJSON = genericParseJSON defaultOptions

classifyLegitimacyOutcome :: LegitimacyStatus -> LegitimacyReason -> WarrantedMoveMode -> ShadowStatus -> ShadowDivergenceSeverity -> LegitimacyOutcome
classifyLegitimacyOutcome status reason warrantedMode shadowStatus shadowSeverity =
  LegitimacyOutcome
    { loDisposition = disposition
    , loStatus = status
    , loReason = reason
    , loWarrantedMode = warrantedMode
    }
  where
    disposition
      | warrantedMode == NeverWarranted = DispositionDeny
      | shadowStatus == ShadowDiverged && shadowSeverity /= ShadowSeverityAdvisory = DispositionRepair
      | status == LegitimacyRecovery = DispositionRepair
      | reason == ReasonShadowDivergence = DispositionRepair
      | reason == ReasonShadowUnavailable = DispositionAdvisory
      | reason == ReasonLowParserConfidence = DispositionAdvisory
      | otherwise = DispositionPermit

data SubjectState = SubjectState
  { ssAgency :: !Double
  , ssTension :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SubjectState where toJSON = genericToJSON defaultOptions
instance FromJSON SubjectState where parseJSON = genericParseJSON defaultOptions

data IsLegit a
  = LegitAcknowledge a
  | LegitClarify a
  | LegitInsight a
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

instance ToJSON a => ToJSON (IsLegit a) where toJSON = genericToJSON defaultOptions
instance FromJSON a => FromJSON (IsLegit a) where parseJSON = genericParseJSON defaultOptions
