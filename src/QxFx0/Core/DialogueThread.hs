{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.DialogueThread
  ( CommitmentAdmissionInput(..)
  , CommitmentAdmissionDecision(..)
  , deriveDialogueCommitmentCandidate
  , admitDialogueCommitmentCandidate
  , admitDialogueCommitmentLedger
  , deriveDialogueThread
  , deriveDialogueCommitmentLedger
  , deriveDialoguePhase
  , commitmentAllowsAdvance
  ) where

import Data.List (nub)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.Input.Model
import QxFx0.Types.State.DialogueDevelopment
import QxFx0.Types.State.Dialogue
import QxFx0.Types.State.Perspective (PerspectiveScope(..))
import QxFx0.Types (TruthContractStatus)

data CommitmentAdmissionInput = CommitmentAdmissionInput
  { caiTruthContractStatus :: !TruthContractStatus
  , caiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data CommitmentAdmissionDecision
  = CadAdmitCanonical
  | CadCapUnresolved
  | CadPreserveContested
  | CadSuspendStrengthening
  deriving stock (Eq, Show)

deriveDialogueThread :: DialogueThread -> DialogueCommitmentLedger -> DialogueState -> UtteranceSemanticFrame -> DialogueThread
deriveDialogueThread previous ledger dialogue frame =
  let focus = firstNonEmpty [usfTopic frame, usfFocus frame, dsLastTopic dialogue, dtCurrentFocus previous]
      structuralScope = deriveStructuralScope previous ledger frame focus
      activeQuestion = if usfSpeechAct frame == ActAsk then Just (usfRawText frame) else dtActiveQuestion previous
      userGoal = firstNonEmptyMaybe (maybeToList (usfTarget frame) ++ [usfTopic frame] ++ maybeToList (dtUserGoal previous))
      intentHypothesis = Just (renderSpeechAct (usfSpeechAct frame))
      acceptedTerms = take 8 . nub $ dtAcceptedTerms previous ++ map wmuLemma (usfWordUnits frame)
      openLoops = take 8 . nub $ unresolvedClaims ledger ++ if usfSpeechAct frame == ActAsk then [usfRawText frame] else []
      clarifiedItems = if usfSpeechAct frame == ActAsk then dtClarifiedItems previous else take 8 . nub $ usfTopic frame : dtClarifiedItems previous
      unclarifiedItems = take 8 . nub $ openLoops ++ filter (not . T.null) [usfFocus frame]
      resistance = clamp01 (if usfPolarity frame == PolarityNegative then 0.65 else 0.25)
      topicConfidence = clamp01 (max (usfConfidence frame) (dtTopicConfidence previous * 0.8))
  in DialogueThread
      { dtCurrentFocus = focus
      , dtActiveQuestion = activeQuestion
      , dtUserGoal = userGoal
      , dtIntentHypothesis = intentHypothesis
      , dtOpenLoops = openLoops
      , dtAcceptedTerms = acceptedTerms
      , dtTopicConfidence = topicConfidence
       , dtResistance = resistance
       , dtClarifiedItems = clarifiedItems
       , dtUnclarifiedItems = unclarifiedItems
       , dtStructuralScope = structuralScope
       , dtPhaseScope = focus
       }

deriveStructuralScope :: DialogueThread -> DialogueCommitmentLedger -> UtteranceSemanticFrame -> Text -> Maybe PerspectiveScope
deriveStructuralScope previous ledger frame focus =
  case firstNonEmptyMaybe [usfTopic frame, usfFocus frame, focus] of
    Nothing -> dtStructuralScope previous
    Just scopeText ->
      case dtStructuralScope previous of
        Just priorScope
          | lockedScope && normalizeScopeKey (scopeTextOf priorScope) /= normalizeScopeKey scopeText ->
              Just priorScope
        _ -> Just (ScopeTopic scopeText)
  where
    lockedScope =
      any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) (dclItems ledger)
        || usfSpeechAct frame == ActAsk

    scopeTextOf :: PerspectiveScope -> Text
    scopeTextOf scope =
      case scope of
        ScopeTopic topic -> topic
        ScopeTheme theme -> theme
        ScopeCluster cluster -> cluster

    normalizeScopeKey :: Text -> Text
    normalizeScopeKey = T.unwords . T.words . T.toLower . T.strip

deriveDialogueCommitmentLedger :: DialogueCommitmentLedger -> UtteranceSemanticFrame -> DialogueCommitmentLedger
deriveDialogueCommitmentLedger existing frame =
  mergeDialogueCommitmentCandidate existing (deriveDialogueCommitmentCandidate frame)

deriveDialogueCommitmentCandidate :: UtteranceSemanticFrame -> Maybe DialogueCommitment
deriveDialogueCommitmentCandidate frame =
  -- This stage builds a semantic commitment candidate from local dialogue
  -- content only. Constitutional contours (truth contract, conatus gate,
  -- recovery/non-authoritative state, route legality, and post-turn
  -- admissibility) still govern whether that candidate later strengthens,
  -- stays unresolved, is contested, or is suspended inside canonical
  -- commitment state.
  let currentClaim = firstNonEmpty [usfTopic frame, usfFocus frame, usfRawText frame]
  in if T.null currentClaim
       then Nothing
       else if usfSpeechAct frame == ActAsk
         then Just (DialogueCommitment currentClaim CsUnresolved 0)
         else if usfPolarity frame == PolarityNegative
           then Just (DialogueCommitment currentClaim CsContested 0)
           else Just (DialogueCommitment currentClaim CsAccepted 0)

mergeDialogueCommitmentCandidate :: DialogueCommitmentLedger -> Maybe DialogueCommitment -> DialogueCommitmentLedger
mergeDialogueCommitmentCandidate (DialogueCommitmentLedger existing) mCandidate =
  DialogueCommitmentLedger (take 16 (existing ++ maybe [] pure mCandidate))

admitDialogueCommitmentCandidate :: CommitmentAdmissionInput -> DialogueCommitment -> (DialogueCommitment, CommitmentAdmissionDecision)
admitDialogueCommitmentCandidate input candidate
  | caiConatusGateFired input =
      case dcStatus candidate of
        CsAccepted -> (candidate { dcStatus = CsSuspended }, CadSuspendStrengthening)
        CsContested -> (candidate { dcStatus = CsSuspended }, CadSuspendStrengthening)
        CsSuspended -> (candidate, CadSuspendStrengthening)
        CsUnresolved -> (candidate, CadCapUnresolved)
  | not (truthContractIsAuthoritative (caiTruthContractStatus input)) =
      case dcStatus candidate of
        CsAccepted -> (candidate { dcStatus = CsUnresolved }, CadCapUnresolved)
        CsContested -> (candidate, CadPreserveContested)
        CsSuspended -> (candidate, CadSuspendStrengthening)
        CsUnresolved -> (candidate, CadCapUnresolved)
  | otherwise = (candidate, CadAdmitCanonical)

admitDialogueCommitmentLedger :: CommitmentAdmissionInput -> DialogueCommitmentLedger -> Maybe DialogueCommitment -> DialogueCommitmentLedger
admitDialogueCommitmentLedger input priorLedger mCandidate =
  mergeDialogueCommitmentCandidate priorLedger (fmap (fst . admitDialogueCommitmentCandidate input) mCandidate)

deriveDialoguePhase :: DialogueThread -> DialogueCommitmentLedger -> UtteranceSemanticFrame -> DialoguePhase
deriveDialoguePhase thread ledger frame
  | hasContested ledger = Contesting
  | hasRepairNeed thread frame = Repairing
  | hasUnresolved ledger = Clarifying
  | usfSpeechAct frame == ActAsk = Exploring
  | commitmentAllowsAdvance ledger = Advancing
  | otherwise = Grounding

commitmentAllowsAdvance :: DialogueCommitmentLedger -> Bool
commitmentAllowsAdvance (DialogueCommitmentLedger items) =
  not (any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) items)

hasUnresolved :: DialogueCommitmentLedger -> Bool
hasUnresolved (DialogueCommitmentLedger items) = any ((== CsUnresolved) . dcStatus) items

hasContested :: DialogueCommitmentLedger -> Bool
hasContested (DialogueCommitmentLedger items) = any ((== CsContested) . dcStatus) items

hasRepairNeed :: DialogueThread -> UtteranceSemanticFrame -> Bool
hasRepairNeed thread frame =
  dtResistance thread > 0.6 || any isRepairClass (concatMap wmuSemanticClasses (usfWordUnits frame))
  where
    isRepairClass SemDialogueRepair = True
    isRepairClass _ = False

unresolvedClaims :: DialogueCommitmentLedger -> [Text]
unresolvedClaims (DialogueCommitmentLedger items) = [dcClaim item | item <- items, dcStatus item == CsUnresolved]

renderSpeechAct :: InputSpeechAct -> Text
renderSpeechAct act = case act of
  ActAssert -> "assert"
  ActAsk -> "ask"
  ActRequest -> "request"
  ActInvite -> "invite"
  ActReport -> "report"
  ActUnknown -> "unknown"

firstNonEmpty :: [Text] -> Text
firstNonEmpty = fromMaybe "" . firstNonEmptyMaybe

firstNonEmptyMaybe :: [Text] -> Maybe Text
firstNonEmptyMaybe = go
  where
    go [] = Nothing
    go (x:xs)
      | T.null (T.strip x) = go xs
      | otherwise = Just x

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0

maybeToList :: Maybe Text -> [Text]
maybeToList (Just value) = [value]
maybeToList Nothing = []
