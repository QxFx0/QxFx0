{-# LANGUAGE OverloadedStrings #-}

{-| Outcome-derived dialogue development.

This module keeps the next phase fail-closed: only distinguishable signals
drive strong updates. Ambiguous turns are recorded but do not mutate speech
policy or claim stance confidence.
-}
module QxFx0.Learning.DialogueDevelopment
  ( applyDialogueDevelopment
  , assessDialogueOutcome
  , updateDialogueOutcomeLearning
  , updateSpeechPolicy
  , updateBeliefStore
  , adjustRenderStyleForSpeechPolicy
  , normalizeDialogueText
  , isWeakAcknowledgementText
  ) where

import qualified Data.Foldable as F
import Data.List (sortBy)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.TurnPipeline.Types
  ( TurnArtifacts(..)
  , TurnInput(..)
  , TurnPlan(..)
  )
import QxFx0.Types
import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveDecision(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  , EvidenceStrength(..)
  )
import QxFx0.Types.State.System (appendAdaptiveMutationRecords)

maxRecentOutcomeSamples :: Int
maxRecentOutcomeSamples = 12

maxClaimEvidence :: Int
maxClaimEvidence = 8

maxClaimRevisions :: Int
maxClaimRevisions = 20

maxSpeechPatternEntries :: Int
maxSpeechPatternEntries = 8

maxClaimStanceEntries :: Int
maxClaimStanceEntries = 64

maxClaimRevisionsPerStore :: Int
maxClaimRevisionsPerStore = maxClaimRevisions

applyDialogueDevelopment
  :: SystemState  -- ^ pre-turn state, used for repeated-input evidence
  -> SystemState  -- ^ post-base-finalize state, receives persistent updates
  -> TurnInput
  -> TurnPlan
  -> TurnArtifacts
  -> SystemState
applyDialogueDevelopment previousState postState ti tp ta =
  let sample = assessDialogueOutcome previousState postState ti tp ta
      style = tdRenderStyle (taDecision ta)
      outcomeState = updateDialogueOutcomeLearning sample (ssDialogueOutcomeLearning postState)
      speechPolicy = updateSpeechPolicy sample style (ssSpeechPolicyState postState)
      beliefStore = updateBeliefStore previousState sample ti tp (ssBeliefStore postState)
      updated = postState
        { ssDialogueOutcomeLearning = outcomeState
        , ssSpeechPolicyState = speechPolicy
        , ssBeliefStore = beliefStore
        }
  in appendAdaptiveMutationRecords (adrMutationRecords (dosDecisionRecord sample)) updated

assessDialogueOutcome
  :: SystemState
  -> SystemState
  -> TurnInput
  -> TurnPlan
  -> TurnArtifacts
  -> DialogueOutcomeSample
assessDialogueOutcome previousState postState ti tp ta =
  let frame = tiFrame ti
      raw = normalizeDialogueText (ipfRawText frame)
      propositionType = ipfPropositionType frame
      previousInputs = map normalizeDialogueText (F.toList (ssRawInputHistory previousState))
      repeatedInput = not (T.null raw) && raw `elem` take 3 (reverse previousInputs)
      localRecovery = taSurfaceProv ta == FromRecovery || isJust (taLocalRecoveryCause ta)
      decisionRepair = tdFamily (taDecision ta) == CMRepair
      renderEmpty = T.null (T.strip (taFinalRendered ta))
      userRepair = propositionType `elem` ["RepairSignal", "MisunderstandingReport"]
      userClarification = propositionType `elem` ["ClarifyQ", "EpistemicQ", "RequestQ"]
      successfulContinuation = propositionType == "NextStepQ"
      userConflict = propositionType == "ConfrontQ" || containsAny raw conflictPhrases
      strongPositiveConfirmation = containsAny raw strongPositiveConfirmationPhrases
      weakAcknowledgement = isWeakAcknowledgementText raw
      (kind, strong, strength) =
        if userConflict
          then (DialogueOutcomeConflict, True, EvidenceStrong)
        else if userRepair
          then (DialogueOutcomeRepairRequested, True, EvidenceStrong)
        else if repeatedInput
          then (DialogueOutcomeRepeatedQuestion, True, EvidenceStrong)
        else if strongPositiveConfirmation
          then (DialogueOutcomeSuccess, True, EvidenceStrong)
        else if weakAcknowledgement
          then (DialogueOutcomePartialSuccess, False, EvidenceWeak)
        else if localRecovery || decisionRepair || renderEmpty
          then (DialogueOutcomeDegraded, True, EvidenceStrong)
        else if successfulContinuation || userClarification
          then (DialogueOutcomePartialSuccess, False, EvidenceModerate)
        else (DialogueOutcomeUncertain, False, EvidenceWeak)
      topic = firstNonEmpty
        [ if strongPositiveConfirmation || weakAcknowledgement then ssLastTopic previousState else ""
        , tiBestTopic ti
        , ipfSemanticSubject frame
        , rmpTopic (tpRmpAfterLegit tp)
        ]
      signals = outcomeSignals propositionType repeatedInput localRecovery decisionRepair renderEmpty userConflict strongPositiveConfirmation weakAcknowledgement successfulContinuation userClarification
      decision = adaptiveDecisionRecord (ssTurnCount postState) kind signals strong strength
  in DialogueOutcomeSample
       { dosTurn = ssTurnCount postState
       , dosKind = kind
       , dosTopic = topic
       , dosSignals = signals
       , dosEvidenceStrength = strength
       , dosStrongUpdate = strong
       , dosDecisionRecord = decision
       }

updateDialogueOutcomeLearning :: DialogueOutcomeSample -> DialogueOutcomeLearningState -> DialogueOutcomeLearningState
updateDialogueOutcomeLearning sample state0 =
  let state = state0 { dolRecentOutcomes = take maxRecentOutcomeSamples (sample : dolRecentOutcomes state0) }
  in case dosKind sample of
       DialogueOutcomeSuccess -> state { dolSuccessCount = dolSuccessCount state + 1 }
       DialogueOutcomePartialSuccess -> state { dolPartialSuccessCount = dolPartialSuccessCount state + 1 }
       DialogueOutcomeRepairRequested -> state { dolRepairRequestCount = dolRepairRequestCount state + 1 }
       DialogueOutcomeRepeatedQuestion -> state { dolRepeatedQuestionCount = dolRepeatedQuestionCount state + 1 }
       DialogueOutcomeConflict -> state { dolConflictCount = dolConflictCount state + 1 }
       DialogueOutcomeDegraded -> state { dolDegradedCount = dolDegradedCount state + 1 }
       DialogueOutcomeUncertain -> state { dolUncertainCount = dolUncertainCount state + 1 }

adaptiveDecisionRecord
  :: Int
  -> DialogueOutcomeKind
  -> [Text]
  -> Bool
  -> EvidenceStrength
  -> AdaptiveDecisionRecord
adaptiveDecisionRecord turn kind signals strong strength =
  let cause = "dialogue_outcome:" <> renderDialogueOutcomeKind kind
      confidence = evidenceConfidence strength
      boundedDelta = boundedDeltaFor kind strong
      decision = if strong then AdaptiveAccepted else AdaptiveObserved
      targets = mutationTargetsFor kind strong
  in AdaptiveDecisionRecord
       { adrTurn = turn
       , adrCause = cause
       , adrEvidence = signals
       , adrConfidence = confidence
       , adrBoundedDelta = boundedDelta
       , adrDecision = decision
       , adrTargets = targets
       , adrMutationRecords = mutationRecordsForDialogue turn cause signals strength confidence decision targets
       }

evidenceConfidence :: EvidenceStrength -> Double
evidenceConfidence strength =
  case strength of
    EvidenceObservational -> 0.10
    EvidenceWeak -> 0.25
    EvidenceModerate -> 0.50
    EvidenceStrong -> 0.80

boundedDeltaFor :: DialogueOutcomeKind -> Bool -> [Text]
boundedDeltaFor kind strong =
  [ "recent_outcomes<=12" ]
    <> if not strong
         then []
         else case kind of
           DialogueOutcomeSuccess -> ["speech_patterns<=8", "claim_stance_entries<=64"]
           DialogueOutcomeConflict -> ["speech_patterns<=8", "claim_stance_entries<=64", "claim_revisions<=20"]
           DialogueOutcomeRepairRequested -> ["speech_patterns<=8"]
           DialogueOutcomeRepeatedQuestion -> ["speech_patterns<=8"]
           DialogueOutcomeDegraded -> ["speech_patterns<=8"]
           DialogueOutcomePartialSuccess -> []
           DialogueOutcomeUncertain -> []

mutationTargetsFor :: DialogueOutcomeKind -> Bool -> [AdaptiveMutationKind]
mutationTargetsFor kind strong =
  MutDialogueOutcome :
    if not strong
      then []
      else case kind of
        DialogueOutcomeSuccess -> [MutSpeechPolicy, MutClaimStance]
        DialogueOutcomeConflict -> [MutSpeechPolicy, MutClaimStance]
        DialogueOutcomeRepairRequested -> [MutSpeechPolicy]
        DialogueOutcomeRepeatedQuestion -> [MutSpeechPolicy]
        DialogueOutcomeDegraded -> [MutSpeechPolicy]
        DialogueOutcomePartialSuccess -> []
        DialogueOutcomeUncertain -> []

mutationRecordsForDialogue
  :: Int
  -> Text
  -> [Text]
  -> EvidenceStrength
  -> Double
  -> AdaptiveDecision
  -> [AdaptiveMutationKind]
  -> [AdaptiveMutationRecord]
mutationRecordsForDialogue turn cause signals strength confidence decision targets =
  map targetRecord targets
  where
    targetRecord target = AdaptiveMutationRecord
      { amrTurnId = turn
      , amrKind = target
      , amrCause = cause
      , amrEvidence = signals
      , amrEvidenceStrength = strength
      , amrConfidence = confidence
      , amrBoundedDelta = boundedDeltaForTarget target
      , amrDecision = decision
      }

boundedDeltaForTarget :: AdaptiveMutationKind -> Maybe Double
boundedDeltaForTarget target =
  case target of
    MutDialogueOutcome -> Just (fromIntegral maxRecentOutcomeSamples)
    MutSpeechPolicy -> Just 0.12
    MutClaimStance -> Just (fromIntegral maxClaimStanceEntries)
    _ -> Nothing

decisionAllowsBoundedMutation :: DialogueOutcomeSample -> Bool
decisionAllowsBoundedMutation sample =
  case adrDecision (dosDecisionRecord sample) of
    AdaptiveAccepted -> dosStrongUpdate sample
    _ -> False

updateSpeechPolicy :: DialogueOutcomeSample -> RenderStyle -> SpeechPolicyState -> SpeechPolicyState
updateSpeechPolicy sample style state
  | not (decisionAllowsBoundedMutation sample) = state
  | otherwise =
      case dosKind sample of
        DialogueOutcomeSuccess ->
          let next = state
                { spsSuccessfulPatterns = bump styleTag (spsSuccessfulPatterns state)
                , spsRepairBias = clamp01 (spsRepairBias state - 0.05)
                , spsLastUpdatedTurn = dosTurn sample
                }
          in boundSpeechPolicy next
        DialogueOutcomePartialSuccess ->
          tune 0.04 0.04 (-0.02) 0.08 True
        DialogueOutcomeRepairRequested ->
          tune 0.12 0.12 (-0.10) 0.30 False
        DialogueOutcomeRepeatedQuestion ->
          tune 0.12 0.15 (-0.10) 0.30 False
        DialogueOutcomeConflict ->
          tune 0.05 0.03 (-0.07) 0.18 False
        DialogueOutcomeDegraded ->
          tune 0.10 0.12 (-0.12) 0.30 False
        DialogueOutcomeUncertain -> state
  where
    styleTag = renderStyleText style
    bump key = capCounterMap maxSpeechPatternEntries . M.insertWith (+) key 1
    tune directDelta compressionDelta ambiguityDelta repairDelta positive =
      let next = state
            { spsDirectness = clamp01 (spsDirectness state + directDelta)
            , spsCompression = clamp01 (spsCompression state + compressionDelta)
            , spsAmbiguityTolerance = clamp01 (spsAmbiguityTolerance state + ambiguityDelta)
            , spsRepairBias = clamp01 (spsRepairBias state + repairDelta)
            , spsSuccessfulPatterns = if positive then bump styleTag (spsSuccessfulPatterns state) else spsSuccessfulPatterns state
            , spsFailedPatterns = if positive then spsFailedPatterns state else bump styleTag (spsFailedPatterns state)
            , spsLastUpdatedTurn = dosTurn sample
            }
      in boundSpeechPolicy next

updateBeliefStore :: SystemState -> DialogueOutcomeSample -> TurnInput -> TurnPlan -> BeliefStore -> BeliefStore
updateBeliefStore previousState sample ti tp store
  | not (decisionAllowsBoundedMutation sample) = store
  | T.null claimKey = store
  | otherwise =
      case dosKind sample of
        DialogueOutcomeSuccess -> upsertPositive
        DialogueOutcomeConflict -> upsertConflict
        _ -> store
  where
    rmp = tpRmpAfterLegit tp
    priorTopic = ssLastTopic previousState
    claimText =
      if not (T.null (T.strip priorTopic))
        then priorTopic
        else firstNonEmpty [rmpPrimaryClaim rmp, tiBestTopic ti]
    claimKey = normalizeDialogueText claimText
    evidenceTag = T.concat ["turn=", T.pack (show (dosTurn sample)), ":", renderDialogueOutcomeKind (dosKind sample)]
    stancePolarity = stanceToPolarity (rmpStance rmp)
    existing = M.lookup claimKey (bsClaims store)
    basePositive = fromMaybe
      BeliefRecord
        { brClaim = claimText
        , brPolarity = stancePolarity
        , brConfidence = 0.50
        , brEvidence = []
        , brCounterEvidence = []
        , brLastUpdatedTurn = 0
        , brRevisionCount = 0
        }
      existing
    upsertPositive =
      let polarity = case brPolarity basePositive of
            BeliefContested -> BeliefTentative
            BeliefRejected -> BeliefTentative
            _ -> stancePolarity
          entry = basePositive
            { brPolarity = polarity
            , brConfidence = clamp01 (brConfidence basePositive + 0.08)
            , brEvidence = take maxClaimEvidence (evidenceTag : brEvidence basePositive)
            , brLastUpdatedTurn = dosTurn sample
            }
      in store { bsClaims = insertBoundedClaim claimKey entry (bsClaims store) }
    upsertConflict =
      let base = fromMaybe
            BeliefRecord
              { brClaim = claimText
              , brPolarity = BeliefContested
              , brConfidence = 0.45
              , brEvidence = []
              , brCounterEvidence = []
              , brLastUpdatedTurn = 0
              , brRevisionCount = 0
              }
            existing
          entry = base
            { brPolarity = BeliefContested
            , brConfidence = clamp01 (brConfidence base - 0.15)
            , brCounterEvidence = take maxClaimEvidence (evidenceTag : brCounterEvidence base)
            , brLastUpdatedTurn = dosTurn sample
            , brRevisionCount = brRevisionCount base + 1
            }
      in store
           { bsClaims = insertBoundedClaim claimKey entry (bsClaims store)
           , bsRecentRevisions = take maxClaimRevisionsPerStore (claimKey : bsRecentRevisions store)
           }

adjustRenderStyleForSpeechPolicy :: SpeechPolicyState -> RenderStyle -> RenderStyle
adjustRenderStyleForSpeechPolicy policy original
  | original == StyleRecovery = StyleRecovery
  | spsRepairBias policy >= 0.60 = StyleRecovery
  | spsDirectness policy >= 0.65 && spsCompression policy >= 0.65 = StyleDirect
  | spsAmbiguityTolerance policy <= 0.30 = StyleClinical
  | otherwise = original

outcomeSignals :: Text -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> [Text]
outcomeSignals propositionType repeatedInput localRecovery decisionRepair renderEmpty userConflict strongPositiveConfirmation weakAcknowledgement successfulContinuation userClarification =
  [ "proposition_type=" <> propositionType ]
    <> flag "repeated_question" repeatedInput
    <> flag "local_recovery" localRecovery
    <> flag "decision_repair" decisionRepair
    <> flag "empty_render" renderEmpty
    <> flag "user_conflict" userConflict
    <> flag "strong_positive_confirmation" strongPositiveConfirmation
    <> flag "weak_acknowledgement" weakAcknowledgement
    <> flag "successful_continuation" successfulContinuation
    <> flag "clarification_request" userClarification

flag :: Text -> Bool -> [Text]
flag label ok = if ok then [label] else []

containsAny :: Text -> [Text] -> Bool
containsAny text = any (`T.isInfixOf` text)

strongPositiveConfirmationPhrases :: [Text]
strongPositiveConfirmationPhrases =
  [ "стало понятно"
  , "это помогло"
  , "помогло"
  , "верно"
  , "that helps"
  , "clear now"
  ]

weakAcknowledgementPhrases :: [Text]
weakAcknowledgementPhrases =
  [ "ack"
  , "понял"
  , "поняла"
  , "ясно"
  , "спасибо"
  , "thank you"
  , "thanks"
  , "i understand"
  , "makes sense"
  ]

isWeakAcknowledgementText :: Text -> Bool
isWeakAcknowledgementText text =
  containsAny (normalizeDialogueText text) weakAcknowledgementPhrases

conflictPhrases :: [Text]
conflictPhrases =
  [ "не соглас"
  , "противореч"
  , "неверно"
  , "ошибка"
  , "wrong"
  , "not true"
  , "does not follow"
  , "contradiction"
  ]

stanceToPolarity :: StanceMarker -> BeliefPolarity
stanceToPolarity stance =
  case stance of
    Firm -> BeliefAffirmed
    Commit -> BeliefAffirmed
    Curated -> BeliefAffirmed
    HoldBack -> BeliefTentative
    Honest -> BeliefTentative
    Observe -> BeliefTentative
    Explore -> BeliefTentative
    Tentative -> BeliefTentative

boundSpeechPolicy :: SpeechPolicyState -> SpeechPolicyState
boundSpeechPolicy state =
  state
    { spsSuccessfulPatterns = capCounterMap maxSpeechPatternEntries (spsSuccessfulPatterns state)
    , spsFailedPatterns = capCounterMap maxSpeechPatternEntries (spsFailedPatterns state)
    }

capCounterMap :: Int -> M.Map Text Int -> M.Map Text Int
capCounterMap limit = M.fromList . take limit . sortBy compareEntry . M.toList
  where
    compareEntry (k1, v1) (k2, v2) = compare v2 v1 <> compare k1 k2

insertBoundedClaim :: Text -> BeliefRecord -> M.Map Text BeliefRecord -> M.Map Text BeliefRecord
insertBoundedClaim key entry claims =
  let next = M.insert key entry claims
  in if M.size next <= maxClaimStanceEntries
       then next
       else pruneClaimMap key next

pruneClaimMap :: Text -> M.Map Text BeliefRecord -> M.Map Text BeliefRecord
pruneClaimMap preservedKey claims =
  let sorted = sortBy compareRecord (M.toList claims)
      keepCount = max 0 (maxClaimStanceEntries - 1)
      kept = take keepCount (filter ((/= preservedKey) . fst) sorted)
  in M.fromList (kept <> maybeToList (fmap (\value -> (preservedKey, value)) (M.lookup preservedKey claims)))

compareRecord :: (Text, BeliefRecord) -> (Text, BeliefRecord) -> Ordering
compareRecord (k1, r1) (k2, r2) =
  compare (brLastUpdatedTurn r2) (brLastUpdatedTurn r1)
    <> compare (brRevisionCount r2) (brRevisionCount r1)
    <> compare k1 k2

maybeToList :: Maybe a -> [a]
maybeToList Nothing = []
maybeToList (Just x) = [x]

renderDialogueOutcomeKind :: DialogueOutcomeKind -> Text
renderDialogueOutcomeKind kind =
  case kind of
    DialogueOutcomeSuccess -> "success"
    DialogueOutcomePartialSuccess -> "partial_success"
    DialogueOutcomeRepairRequested -> "repair_requested"
    DialogueOutcomeRepeatedQuestion -> "repeated_question"
    DialogueOutcomeConflict -> "conflict"
    DialogueOutcomeDegraded -> "degraded"
    DialogueOutcomeUncertain -> "uncertain"

firstNonEmpty :: [Text] -> Text
firstNonEmpty = fromMaybe "" . safeHead . filter (not . T.null . T.strip)
  where
    safeHead [] = Nothing
    safeHead (x:_) = Just (T.strip x)

normalizeDialogueText :: Text -> Text
normalizeDialogueText = T.unwords . T.words . T.toLower . T.replace "ё" "е" . T.strip

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0
