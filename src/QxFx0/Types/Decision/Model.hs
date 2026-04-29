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
  , (.=)
  )
import Data.Text (Text)
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
import QxFx0.Types.Observability (ContractProvenance, ResponseStrategy)
import QxFx0.Types.Orbital
  ( DirectiveMoveBias
  , EncounterMode
  , OrbitalPhase
  )
import QxFx0.Types.Thresholds (DepthMode, LegitimacyStatus(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..))

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
  , rmpContrastAxis :: !Text
  , rmpImplicationDirection :: !Text
  , rmpProvenance :: !ContractProvenance
  , rmpCommitmentStrength :: !Double
  , rmpDepthMode :: !DepthMode
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
    , "rmpContrastAxis" .= rmpContrastAxis rmp
    , "rmpImplicationDirection" .= rmpImplicationDirection rmp
    , "rmpProvenance" .= rmpProvenance rmp
    , "rmpCommitmentStrength" .= rmpCommitmentStrength rmp
    , "rmpDepthMode" .= rmpDepthMode rmp
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
      <*> o .: "rmpContrastAxis"
      <*> o .: "rmpImplicationDirection"
      <*> o .: "rmpProvenance"
      <*> o .: "rmpCommitmentStrength"
      <*> o .: "rmpDepthMode"

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
  , ipfPropositionType :: !Text
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

instance ToJSON InputPropositionFrame where toJSON = genericToJSON defaultOptions
instance FromJSON InputPropositionFrame where parseJSON = genericParseJSON defaultOptions

emptyInputPropositionFrame :: InputPropositionFrame
emptyInputPropositionFrame = InputPropositionFrame
  { ipfRawText = ""
  , ipfPropositionType = "Unknown"
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
