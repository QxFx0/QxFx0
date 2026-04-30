{-# LANGUAGE DerivingStrategies #-}
module QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , propositionToFamily
  , propositionTypeFromText
  , diagnosticPropositionFamily
  ) where

import QxFx0.Types (CanonicalMoveFamily(..))
import Data.Text (Text)
import qualified Data.Text as T
import Text.Read (readMaybe)

data PropositionType
  = DefinitionalQ
  | DistinctionQ
  | GroundQ
  | ReflectiveQ
  | SelfDescQ
  | PurposeQ
  | HypotheticalQ
  | RepairSignal
  | ContactSignal
  | AnchorSignal
  | ClarifyQ
  | DeepenQ
  | ConfrontQ
  | NextStepQ
  | PlainAssert
  | AffectiveQ
  | EpistemicQ
  | RequestQ
  | EvaluationQ
  | NarrativeQ
  | OperationalStatusQ
  | OperationalCauseQ
  | SystemLogicQ
  | SelfKnowledgeQ
  | DialogueInvitationQ
  | ConceptKnowledgeQ
  | WorldCauseQ
  | LocationFormationQ
  | SelfStateQ
  | ComparisonPlausibilityQ
  | MisunderstandingReport
  | GenerativePrompt
  | ContemplativeTopic
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

propositionToFamily :: PropositionType -> CanonicalMoveFamily
propositionToFamily DefinitionalQ  = CMDefine
propositionToFamily DistinctionQ   = CMDistinguish
propositionToFamily GroundQ        = CMGround
propositionToFamily ReflectiveQ    = CMReflect
propositionToFamily SelfDescQ      = CMDescribe
propositionToFamily PurposeQ       = CMPurpose
propositionToFamily HypotheticalQ  = CMHypothesis
propositionToFamily RepairSignal   = CMRepair
propositionToFamily ContactSignal  = CMContact
propositionToFamily AnchorSignal   = CMAnchor
propositionToFamily ClarifyQ       = CMClarify
propositionToFamily DeepenQ        = CMDeepen
propositionToFamily ConfrontQ      = CMConfront
propositionToFamily NextStepQ      = CMNextStep
propositionToFamily PlainAssert    = CMGround
propositionToFamily AffectiveQ     = CMContact
propositionToFamily EpistemicQ     = CMClarify
propositionToFamily RequestQ       = CMClarify
propositionToFamily EvaluationQ    = CMDistinguish
propositionToFamily NarrativeQ     = CMDescribe
propositionToFamily OperationalStatusQ = CMClarify
propositionToFamily OperationalCauseQ = CMGround
propositionToFamily SystemLogicQ   = CMDescribe
propositionToFamily SelfKnowledgeQ = CMDescribe
propositionToFamily DialogueInvitationQ = CMDeepen
propositionToFamily ConceptKnowledgeQ = CMDefine
propositionToFamily WorldCauseQ    = CMGround
propositionToFamily LocationFormationQ = CMGround
propositionToFamily SelfStateQ = CMDescribe
propositionToFamily ComparisonPlausibilityQ = CMDistinguish
propositionToFamily MisunderstandingReport = CMRepair
propositionToFamily GenerativePrompt = CMDescribe
propositionToFamily ContemplativeTopic = CMDeepen

propositionTypeFromText :: Text -> Maybe PropositionType
propositionTypeFromText = readMaybe . T.unpack

diagnosticPropositionFamily :: Text -> Maybe CanonicalMoveFamily
diagnosticPropositionFamily rawType =
  case propositionTypeFromText rawType of
    Just OperationalStatusQ -> Just CMClarify
    Just OperationalCauseQ -> Just CMGround
    Just SystemLogicQ -> Just CMDescribe
    Just SelfKnowledgeQ -> Just CMDescribe
    Just DialogueInvitationQ -> Just CMDeepen
    Just ConceptKnowledgeQ -> Just CMDefine
    Just WorldCauseQ -> Just CMGround
    Just LocationFormationQ -> Just CMGround
    Just SelfStateQ -> Just CMDescribe
    Just ComparisonPlausibilityQ -> Just CMDistinguish
    Just MisunderstandingReport -> Just CMRepair
    Just GenerativePrompt -> Just CMDescribe
    Just ContemplativeTopic -> Just CMDeepen
    _ -> Nothing
