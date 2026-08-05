{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Types.Semantic.ResponsePlan
Description : Versioned, replayable contract for grounded response generation.

This module contains data only.  It deliberately does not know how a claim is
rendered or how a selector is implemented, so the plan can be persisted and
replayed without importing runtime or rendering layers.
-}
module QxFx0.Types.Semantic.ResponsePlan
  ( responsePlanVersion
  , ResponseGoal(..)
  , ClaimMode(..)
  , ClaimEvidence(..)
  , SemanticProposition(..)
  , DialogueObligation(..)
  , DerivationRule(..)
  , PlanDerivation(..)
  , SemanticFallbackReason(..)
  , PlannedClaim(..)
  , DiscourseRelation(..)
  , DiscoursePlan(..)
  , ResponseSemanticPlan(..)
  , responsePlanIsAdmissible
  , responsePlanTags
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  , object
  , withObject
  )
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

responsePlanVersion :: Int
responsePlanVersion = 2

data ResponseGoal
  = GoalGenerateThesis
  | GoalExplain
  | GoalDefine
  | GoalCompare
  | GoalClarify
  | GoalRepair
  | GoalChallenge
  | GoalHypothesize
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ClaimMode
  = ClaimKnown
  | ClaimInterpretive
  | ClaimHypothetical
  | ClaimQuestion
  | ClaimUnknown
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ClaimEvidence
  = EvidenceCuratedPredicate
  | EvidenceSelectedPredicate
  | EvidenceUserAdmitted
  | EvidenceSyntheticResolution
  | EvidenceNone
  deriving stock (Eq, Show, Generic)
   deriving anyclass (NFData, ToJSON, FromJSON)

-- | A compact proposition algebra used by the planner before surface
-- realization. Text remains only at grounded leaves supplied by predicates.
data SemanticProposition
  = PropositionPredicate !Text !Text !Text
  | PropositionConditional !SemanticProposition !SemanticProposition
  | PropositionConjunction !SemanticProposition !SemanticProposition
  | PropositionContrast !SemanticProposition !SemanticProposition
  | PropositionQuestion !SemanticProposition
  | PropositionQualification !SemanticProposition !SemanticProposition
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | The next dialogue move is an explicit semantic obligation rather than an
-- untyped instruction string.
data DialogueObligation
  = ObligationClarify !Text
  | ObligationCheck !SemanticProposition
  | ObligationContrast !SemanticProposition
  | ObligationContinue !Text
  | ObligationClose !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data DerivationRule
  = DeriveSelectedPredicate
  | DeriveElaboration
  | DeriveContrast
  | DeriveQualification
  | DeriveConsequence
  | DeriveQuestion
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Replayable explanation of why a bounded composer selected one fragment
-- and declined its alternatives.
data PlanDerivation = PlanDerivation
  { pdFragmentId :: !Text
  , pdPredicateRefs :: ![Text]
  , pdRule :: !DerivationRule
  , pdReason :: !Text
  , pdRejectedAlternatives :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticFallbackReason
  = NoTopicProvided
  | TopicNotCovered
  | NoAdmissiblePredicate
  | ConflictingEvidence
  | PlanQualityRejected
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data PlannedClaim = PlannedClaim
  { pcId :: !Text
  , pcMode :: !ClaimMode
  , pcText :: !Text
  , pcPredicateRefs :: ![Text]
  , pcEvidence :: !ClaimEvidence
  , pcConfidence :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data DiscourseRelation
  = DiscourseNone
  | DiscourseElaboration
  | DiscourseContrast
  | DiscourseQualification
  | DiscourseConsequence
  | DiscourseCounterpoint
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data DiscoursePlan = DiscoursePlan
  { dpRelation :: !DiscourseRelation
  , dpMarker :: !(Maybe Text)
  , dpMaxSentences :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data ResponseSemanticPlan = ResponseSemanticPlan
  { rspVersion :: !Int
  , rspGoal :: !ResponseGoal
  , rspTopic :: !(Maybe Text)
  , rspClaims :: ![PlannedClaim]
  , rspPropositions :: ![SemanticProposition]
  , rspCounterpoint :: !(Maybe PlannedClaim)
  , rspObligation :: !(Maybe DialogueObligation)
  , rspNextMove :: !(Maybe Text)
  , rspDerivation :: ![PlanDerivation]
  , rspFallbackReason :: !(Maybe SemanticFallbackReason)
  , rspDiscourse :: !DiscoursePlan
  } deriving stock (Eq, Show, Generic)
    deriving anyclass NFData

instance ToJSON ResponseSemanticPlan where
  toJSON plan = object
    [ "rspVersion" .= rspVersion plan
    , "rspGoal" .= rspGoal plan
    , "rspTopic" .= rspTopic plan
    , "rspClaims" .= rspClaims plan
    , "rspPropositions" .= rspPropositions plan
    , "rspCounterpoint" .= rspCounterpoint plan
    , "rspObligation" .= rspObligation plan
    , "rspNextMove" .= rspNextMove plan
    , "rspDerivation" .= rspDerivation plan
    , "rspFallbackReason" .= rspFallbackReason plan
    , "rspDiscourse" .= rspDiscourse plan
    ]

instance FromJSON ResponseSemanticPlan where
  parseJSON = withObject "ResponseSemanticPlan" $ \o ->
    ResponseSemanticPlan
      <$> o .: "rspVersion"
      <*> o .: "rspGoal"
      <*> o .:? "rspTopic"
      <*> o .: "rspClaims"
      <*> o .:? "rspPropositions" .!= []
      <*> o .:? "rspCounterpoint"
      <*> o .:? "rspObligation"
      <*> o .:? "rspNextMove"
      <*> o .:? "rspDerivation" .!= []
      <*> o .:? "rspFallbackReason"
      <*> o .: "rspDiscourse"

responsePlanIsAdmissible :: ResponseSemanticPlan -> Bool
responsePlanIsAdmissible plan =
  case rspFallbackReason plan of
    Just _ -> null (rspClaims plan)
    Nothing ->
      not (null (rspClaims plan))
        && all claimAdmissible (rspClaims plan)
        && maybe True claimAdmissible (rspCounterpoint plan)
        && length (rspClaims plan) <= 3
        && length (rspPropositions plan) <= 8
        && length (rspDerivation plan) <= 8
        && obligationAdmissible (rspObligation plan)
        && dpMaxSentences (rspDiscourse plan) >= 1
        && dpMaxSentences (rspDiscourse plan) <= 3
  where
    claimAdmissible claim =
      not (T.null (pcText claim))
        && (pcMode claim == ClaimUnknown || not (null (pcPredicateRefs claim)))
        && pcConfidence claim >= 0
        && pcConfidence claim <= 1
    obligationAdmissible Nothing = True
    obligationAdmissible (Just obligation) = not (T.null (obligationText obligation))

responsePlanTags :: ResponseSemanticPlan -> [Text]
responsePlanTags plan =
  [ "response_plan=v" <> showText (rspVersion plan)
  , "response_goal=" <> showText (rspGoal plan)
  , "response_claim_mode=" <> claimModeTag
   , "response_discourse=" <> showText (dpRelation (rspDiscourse plan))
   ]
  <> maybe [] (pure . ("response_obligation=" <>) . obligationTag) (rspObligation plan)
  <> ["response_derivation=present" | not (null (rspDerivation plan))]
  <> ["response_counterpoint=present" | rspCounterpoint plan /= Nothing]
  <> ["response_next_move=present" | rspNextMove plan /= Nothing]
  <> maybe [] (pure . ("response_fallback=" <>) . showText) (rspFallbackReason plan)
  where
    claimModeTag = case rspClaims plan of
      claim:_ -> showText (pcMode claim)
      [] -> "none"

showText :: Show a => a -> Text
showText = fromString . show

fromString :: String -> Text
fromString = T.pack

obligationTag :: DialogueObligation -> Text
obligationTag obligation = case obligation of
  ObligationClarify _ -> "clarify"
  ObligationCheck _ -> "check"
  ObligationContrast _ -> "contrast"
  ObligationContinue _ -> "continue"
  ObligationClose _ -> "close"

obligationText :: DialogueObligation -> Text
obligationText obligation = case obligation of
  ObligationClarify text -> text
  ObligationCheck proposition -> propositionText proposition
  ObligationContrast proposition -> propositionText proposition
  ObligationContinue text -> text
  ObligationClose text -> text

propositionText :: SemanticProposition -> Text
propositionText proposition = case proposition of
  PropositionPredicate subject relation object ->
    T.unwords (filter (not . T.null) [subject, relation, object])
  PropositionConditional premise conclusion -> propositionText premise <> " -> " <> propositionText conclusion
  PropositionConjunction left right -> propositionText left <> " + " <> propositionText right
  PropositionContrast thesis counter -> propositionText thesis <> " / " <> propositionText counter
  PropositionQuestion inner -> propositionText inner
  PropositionQualification inner condition -> propositionText inner <> " @ " <> propositionText condition
