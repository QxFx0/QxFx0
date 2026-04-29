{-# LANGUAGE OverloadedStrings #-}

{-| Per-turn consciousness pulse heuristics, selection, and focus derivation. -}
module QxFx0.Core.Consciousness.Kernel.Pulse
  ( kernelPulse
  ) where

import Data.List (sortBy)
import Data.Ord (Down(..), comparing)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Core.Consciousness.Types
import QxFx0.Core.Policy.Consciousness
  ( abstractKeywords
  , concreteKeywords
  , deepContentGeneralizationKeywords
  , deepContentMinimizationKeywords
  , deepContentNarrowingKeywords
  , deepContentUncertaintyKeywords
  , desireConflictSeparator
  , desirePresenceName
  , desirePreserveName
  , desireUnderstandName
  , focusHumanPrefix
  , focusSpace
  , focusStability
  , skillListenName
  , skillNameName
  , skillResistName
  , skillSilenceName
  , temporalFuture
  , temporalFutureKeywords
  , temporalPast
  , temporalPastKeywords
  , temporalPresent
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( containsAnyKeywordPhrase
  , countKeywordPhraseHits
  , tokenizeKeywordText
  )
import QxFx0.Core.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Types
  ( CanonicalMoveFamily(..)
  , ClauseForm(..)
  , EmotionalTone(..)
  , InputPropositionFrame(..)
  , Register(..)
  , SemanticLayer(..)
  )
import QxFx0.Types.Thresholds
  ( consciousnessAbstractionEpsilon
  , consciousnessDeepSearchThreshold
  , consciousnessDesirePresenceThreshold
  , consciousnessDesirePreserveThreshold
  , consciousnessFragmentLengthThreshold
  , consciousnessHighResonanceReturnThreshold
  , consciousnessListenContextBonus
  , consciousnessListenOntologyBonus
  , consciousnessLowConfidenceThreshold
  , consciousnessLowResonanceReturnThreshold
  , consciousnessLowResonanceThreshold
  , consciousnessNameOntologyBonus
  , consciousnessResistContextBonus
  , consciousnessShallowSearchThreshold
  , consciousnessSilenceContextBonus
  , consciousnessSilenceOntologyBonus
  )

kernelPulse :: UnconsciousKernel -> SemanticInput -> Double -> Double -> Int -> KernelOutput
kernelPulse kernel semanticInput humanTheta resonance _turn =
  let tv = ukThinking kernel
      inputText = siRawInput semanticInput
      frame = siPropositionFrame semanticInput
      recommendedFamily = siRecommendedFamily semanticInput
      ontQ = applyOntologicalCore (ukOntology kernel) frame recommendedFamily resonance
      activeDesires = activateDesires (ukDesires kernel) humanTheta resonance frame
      selectedSkill = selectSkillWithOntology (ukSkills kernel) activeDesires frame recommendedFamily ontQ
      thinkResult = applyThinkingVectorWithOntology tv inputText frame recommendedFamily ontQ
      conflicts = findDesireConflicts activeDesires
      narrativeDrive = deriveNarrativeDrive activeDesires frame recommendedFamily selectedSkill
      focusHint = focusForDrive narrativeDrive frame inputText
   in KernelOutput
        { koActiveDesires = map desireName activeDesires
        , koSelectedSkill = skillName selectedSkill
        , koSearchResult = thinkResult
        , koConflicts = conflicts
        , koOntologicalQuestion = ontQ
        , koNarrativeDrive = narrativeDrive
        , koFocusHint = focusHint
        }

selectSkillWithOntology :: SkillSet -> [KernelDesire] -> InputPropositionFrame -> CanonicalMoveFamily -> OntologicalQuestion -> Skill
selectSkillWithOntology skillSet _desires frame recommendedFamily ontQ =
  let allSkills = skills skillSet
      ontBonus skill = case (skillName skill, oqForm ontQ, oqMeaning ontQ) of
        (n, FormExperience, _) | n == skillSilenceName -> consciousnessSilenceOntologyBonus
        (n, FormReasoning, MeaningFragmentMode) | n == skillListenName -> consciousnessListenOntologyBonus
        (n, FormCause, _) | n == skillNameName -> consciousnessNameOntologyBonus
        _ -> 0.0
      scored = map (\skill -> (skill, skillAffinity skill + ontBonus skill + skillContextBonus skill frame recommendedFamily)) allSkills
   in case sortBy (comparing (Down . snd)) scored of
        (skill, _) : _ -> skill
        [] -> dominantSkill skillSet
  where
    skillContextBonus skill propositionFrame family
      | skillName skill == skillSilenceName
          && (ipfEmotionalTone propositionFrame == ToneDistress
                || family `elem` [CMContact, CMRepair, CMAnchor]) =
          consciousnessSilenceContextBonus
      | skillName skill == skillListenName
          && (ipfIsQuestion propositionFrame
                || ipfRegisterHint propositionFrame == Search
                || family `elem` [CMClarify, CMDeepen]) =
          consciousnessListenContextBonus
      | skillName skill == skillResistName
          && (ipfEmotionalTone propositionFrame == ToneConfrontational
                || family == CMConfront
                || ipfIsNegated propositionFrame) =
          consciousnessResistContextBonus
      | otherwise = 0.0

applyThinkingVectorWithOntology :: ThinkingVector -> Text -> InputPropositionFrame -> CanonicalMoveFamily -> OntologicalQuestion -> ThinkingResult
applyThinkingVectorWithOntology tv txt frame recommendedFamily ontQ =
  let base = applyThinkingVector tv txt frame recommendedFamily
   in base {trDeepContent = renderMeaningMode (oqMeaning ontQ)}

applyThinkingVector :: ThinkingVector -> Text -> InputPropositionFrame -> CanonicalMoveFamily -> ThinkingResult
applyThinkingVector tv txt frame recommendedFamily =
  let tokens = tokenizeKeywordText txt
      surface = T.take 100 txt
      deepMode
        | tvSearchDepth tv > consciousnessDeepSearchThreshold = findDeepContent frame recommendedFamily tokens
        | tvSearchDepth tv > consciousnessShallowSearchThreshold = MeaningLowConfidenceMode
        | otherwise = MeaningExtendedMode
      deep = renderMeaningMode deepMode
      temporal = detectTemporalFocus tokens
      humanAbstrLvl = estimateAbstractionLevel tokens
      abstractionGap = humanAbstrLvl - tvAbstractionLvl tv
   in ThinkingResult surface deep temporal abstractionGap

findDeepContent :: InputPropositionFrame -> CanonicalMoveFamily -> [Text] -> MeaningMode
findDeepContent frame recommendedFamily tokens
  | ipfConfidence frame < consciousnessLowConfidenceThreshold = MeaningLowConfidenceMode
  | ipfEmotionalTone frame == ToneDistress || ipfIsNegated frame = MeaningUncertaintyMode
  | recommendedFamily `elem` [CMDefine, CMDistinguish, CMPurpose, CMHypothesis, CMReflect] = MeaningGeneralizationMode
  | recommendedFamily `elem` [CMClarify, CMDeepen, CMNextStep] = MeaningNarrowingMode
  | recommendedFamily `elem` [CMContact, CMRepair, CMAnchor] = MeaningExperienceMode
  | containsAnyKeywordPhrase tokens deepContentMinimizationKeywords = MeaningExperienceMode
  | containsAnyKeywordPhrase tokens deepContentGeneralizationKeywords = MeaningGeneralizationMode
  | containsAnyKeywordPhrase tokens deepContentNarrowingKeywords = MeaningNarrowingMode
  | containsAnyKeywordPhrase tokens deepContentUncertaintyKeywords = MeaningUncertaintyMode
  | otherwise = MeaningExtendedMode

detectTemporalFocus :: [Text] -> Text
detectTemporalFocus tokens
  | containsAnyKeywordPhrase tokens temporalPastKeywords = temporalPast
  | containsAnyKeywordPhrase tokens temporalFutureKeywords = temporalFuture
  | otherwise = temporalPresent

estimateAbstractionLevel :: [Text] -> Double
estimateAbstractionLevel tokens =
  let aScore = fromIntegral (countKeywordPhraseHits tokens abstractKeywords)
      cScore = fromIntegral (countKeywordPhraseHits tokens concreteKeywords)
      total = aScore + cScore + consciousnessAbstractionEpsilon
   in aScore / total

activateDesires :: [KernelDesire] -> Double -> Double -> InputPropositionFrame -> [KernelDesire]
activateDesires desires _theta resonance frame =
  let fundamental = filter (\desire -> desireStrength desire == Fundamental) desires
      contextual =
        filter (isActivated frame resonance) $
          filter (\desire -> desireStrength desire /= Fundamental) desires
   in fundamental ++ contextual

isActivated :: InputPropositionFrame -> Double -> KernelDesire -> Bool
isActivated frame resonance desire =
  case desireName desire of
    name | name == desirePresenceName -> resonance > consciousnessDesirePresenceThreshold
    name | name == desireUnderstandName ->
      ipfIsQuestion frame || ipfRegisterHint frame == Search || ipfSemanticLayer frame == MetaLayer
    name | name == desirePreserveName -> resonance > consciousnessDesirePreserveThreshold
    _ -> False

findDesireConflicts :: [KernelDesire] -> [Text]
findDesireConflicts desires =
  [ desireName desire <> desireConflictSeparator <> conflict
  | desire <- desires
  , Just conflict <- [desireConflict desire]
  ]

applyOntologicalCore :: OntologicalCore -> InputPropositionFrame -> CanonicalMoveFamily -> Double -> OntologicalQuestion
applyOntologicalCore _core frame recommendedFamily resonance =
  let form = classifyForm frame recommendedFamily
      meaning = deriveMeaning resonance form frame recommendedFamily
      returnForm = selectReturnForm form frame resonance
   in OntologicalQuestion form meaning returnForm

classifyForm :: InputPropositionFrame -> CanonicalMoveFamily -> ConsciousForm
classifyForm frame recommendedFamily
  | ipfSemanticLayer frame == ContactLayer = FormExperience
  | recommendedFamily `elem` [CMContact, CMRepair, CMAnchor, CMDescribe] = FormExperience
  | ipfClauseForm frame == Imperative || recommendedFamily `elem` [CMNextStep, CMConfront] = FormAction
  | recommendedFamily `elem` [CMDefine, CMPurpose, CMGround] = FormCause
  | recommendedFamily `elem` [CMDistinguish, CMReflect, CMHypothesis, CMClarify, CMDeepen] = FormReasoning
  | T.length (ipfRawText frame) < consciousnessFragmentLengthThreshold = FormFragment
  | otherwise = FormExtended

deriveMeaning :: Double -> ConsciousForm -> InputPropositionFrame -> CanonicalMoveFamily -> MeaningMode
deriveMeaning resonance form frame recommendedFamily
  | ipfConfidence frame < consciousnessLowConfidenceThreshold = MeaningLowConfidenceMode
  | ipfEmotionalTone frame == ToneDistress || ipfIsNegated frame = MeaningUncertaintyMode
  | recommendedFamily `elem` [CMDefine, CMPurpose, CMGround] || form == FormCause = MeaningCauseMode
  | recommendedFamily `elem` [CMDistinguish, CMReflect, CMHypothesis] = MeaningGeneralizationMode
  | recommendedFamily `elem` [CMClarify, CMDeepen, CMNextStep] = MeaningNarrowingMode
  | recommendedFamily `elem` [CMContact, CMDescribe, CMRepair, CMAnchor] || form == FormExperience = MeaningExperienceMode
  | form == FormAction && resonance < consciousnessLowResonanceThreshold = MeaningActionLowResonanceMode
  | form == FormAction = MeaningActionHighResonanceMode
  | form == FormFragment = MeaningFragmentMode
  | otherwise = MeaningExtendedMode

selectReturnForm :: ConsciousForm -> InputPropositionFrame -> Double -> ReturnMode
selectReturnForm form frame resonance
  | form == FormExperience || ipfSemanticLayer frame == ContactLayer = ReturnExperienceMode
  | resonance > consciousnessHighResonanceReturnThreshold = ReturnDirectHighResonanceMode
  | resonance < consciousnessLowResonanceReturnThreshold || ipfConfidence frame < consciousnessLowConfidenceThreshold = ReturnStructuredLowResonanceMode
  | otherwise = ReturnMixedMode

deriveNarrativeDrive :: [KernelDesire] -> InputPropositionFrame -> CanonicalMoveFamily -> Skill -> NarrativeDrive
deriveNarrativeDrive activeDesires frame recommendedFamily selectedSkill
  | any ((== desirePreserveName) . desireName) activeDesires = DriveStability
  | recommendedFamily == CMRepair = DriveRepair
  | ipfSemanticLayer frame == ContactLayer || recommendedFamily == CMContact = DriveContact
  | recommendedFamily `elem` [CMDefine, CMDistinguish] = DriveDefinition
  | ipfIsQuestion frame || ipfRegisterHint frame == Search || recommendedFamily `elem` [CMClarify, CMDeepen, CMHypothesis] = DriveInquiry
  | recommendedFamily `elem` [CMNextStep, CMConfront] = DriveAction
  | skillName selectedSkill == skillSilenceName = DriveSpace
  | otherwise = DrivePresence

focusForDrive :: NarrativeDrive -> InputPropositionFrame -> Text -> Text
focusForDrive drive frame inputText =
  let focusEntity =
        if T.null (ipfFocusNominative frame)
          then ipfFocusEntity frame
          else ipfFocusNominative frame
      humanFocus = if T.null focusEntity then T.take 30 inputText else focusEntity
   in case drive of
        DriveStability -> focusStability
        DriveSpace -> focusSpace
        DriveInquiry -> focusHumanPrefix <> humanFocus
        DriveDefinition -> humanFocus
        DriveContact -> focusHumanPrefix <> humanFocus
        DriveAction -> humanFocus
        DriveRepair -> focusHumanPrefix <> humanFocus
        DrivePresence -> focusHumanPrefix <> humanFocus
