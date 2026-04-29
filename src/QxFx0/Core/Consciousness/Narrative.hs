{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Narrative interpretation, event accumulation, and prompt-fragment extraction. -}
module QxFx0.Core.Consciousness.Narrative
  ( interpretOutput
  , updateSelfInterpretation
  , consciousnessToNarrative
  , narrativeToPromptFragment
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.Consciousness.Types
import QxFx0.Core.Policy.Consciousness
  ( consciousnessConflictPrefix
  , consciousnessDesiresLabel
  , consciousnessKernelLabel
  , consciousnessLimitLabel
  , consciousnessPromptHeader
  , consciousnessSelfModelLabel
  , consciousnessSkillLabel
  , interpretationEventWhatPrefix
  , interpretationNoDesire
  , interpretWhyDeepPrefix
  , interpretWhyDesiresPrefix
  , interpretWhySkillLabel
  , interpretWhySkillSuffix
  , narrativeActivePrefix
  , narrativeApplySuffix
  , narrativeSearchPrefix
  , observedPatternPrefix
  , focusHumanPrefix
  , skillAffinityMap
  )
import QxFx0.Types.Thresholds
  ( consciousnessDefaultSkillAffinity
  , consciousnessSkillAffinityPatternThreshold
  , consciousnessTrajectoryLimit
  )

interpretOutput :: ConsciousnessModel -> KernelOutput -> Text -> ConsciousnessModel
interpretOutput model output inputText =
  let consciousState = cmConscious model
      turn = csTurnCount consciousState + 1
      event = InterpretationEvent
        { ieWhat = interpretationEventWhatPrefix <> koSelectedSkill output
        , ieWhy = interpretWhy output
        , ieDesire = case koActiveDesires output of
            desire : _ -> desire
            [] -> interpretationNoDesire
        , ieTurn = turn
        }
      newSelfInterpretation = updateSelfInterpretation (csSelfInterp consciousState) output event
      newTrajectory = take consciousnessTrajectoryLimit (event : csTrajectory consciousState)
      newFocus = deriveFocus output inputText
      newConsciousState =
        consciousState
          { csSelfInterp = newSelfInterpretation
          , csTrajectory = newTrajectory
          , csFocus = newFocus
          , csTurnCount = turn
          }
   in model {cmConscious = newConsciousState}

updateSelfInterpretation :: SelfInterpretation -> KernelOutput -> InterpretationEvent -> SelfInterpretation
updateSelfInterpretation selfInterpretation output event =
  let activeDesireNames = koActiveDesires output
      newNarrative = buildNarrative output
      newPattern = case koSelectedSkill output of
        skill | skillAffinityFromName skill > consciousnessSkillAffinityPatternThreshold ->
          Just (observedPatternPrefix <> skill)
        _ -> Nothing
      newPatterns = take 5 $ maybe (siObservedPatterns selfInterpretation) (: siObservedPatterns selfInterpretation) newPattern
   in SelfInterpretation
        { siCurrentNarrative = newNarrative
        , siActiveDesires = take 3 activeDesireNames
        , siObservedPatterns = newPatterns
        , siConflicts = take 3 (koConflicts output)
        , siRecentEvents = take 5 (event : siRecentEvents selfInterpretation)
        }

consciousnessToNarrative :: ConsciousnessModel -> KernelOutput -> ConsciousnessNarrative
consciousnessToNarrative model output =
  let consciousState = cmConscious model
      selfInterpretation = csSelfInterp consciousState
      selfModel = ukSelfModel (cmKernel model)
   in ConsciousnessNarrative
        { cnKernelState = siCurrentNarrative selfInterpretation
        , cnActiveDesires = T.intercalate " / " (siActiveDesires selfInterpretation)
        , cnSkillInPlay = koSelectedSkill output
        , cnSelfView = smIdentity selfModel
        , cnConflict = case siConflicts selfInterpretation of
            [] -> ""
            conflict : _ -> consciousnessConflictPrefix <> conflict
        , cnLimitation = smLimitation selfModel
        }

narrativeToPromptFragment :: ConsciousnessNarrative -> Text
narrativeToPromptFragment narrative = T.unlines $ filter (not . T.null)
  [ consciousnessPromptHeader
  , ""
  , consciousnessKernelLabel <> cnKernelState narrative
  , consciousnessDesiresLabel <> cnActiveDesires narrative
  , consciousnessSkillLabel <> cnSkillInPlay narrative
  , if T.null (cnConflict narrative) then "" else cnConflict narrative
  , ""
  , consciousnessSelfModelLabel <> cnSelfView narrative
  , consciousnessLimitLabel <> cnLimitation narrative
  ]

interpretWhy :: KernelOutput -> Text
interpretWhy output =
  let desires = koActiveDesires output
      skill = koSelectedSkill output
      deep = trDeepContent (koSearchResult output)
   in interpretWhyDesiresPrefix
        <> T.intercalate ", " desires
        <> ". "
        <> interpretWhyDeepPrefix
        <> deep
        <> ". "
        <> interpretWhySkillLabel
        <> skill
        <> interpretWhySkillSuffix

skillAffinityFromName :: Text -> Double
skillAffinityFromName name = case lookup name skillAffinityMap of
  Just affinity -> affinity
  Nothing -> consciousnessDefaultSkillAffinity

buildNarrative :: KernelOutput -> Text
buildNarrative output =
  let skill = koSelectedSkill output
      desires = koActiveDesires output
      focus = trDeepContent (koSearchResult output)
      ontologicalQuestion = koOntologicalQuestion output
      framing = renderConsciousForm (oqForm ontologicalQuestion) <> " / " <> renderReturnMode (oqReturnForm ontologicalQuestion)
   in narrativeSearchPrefix
        <> focus
        <> ". "
        <> framing
        <> ". "
        <> narrativeActivePrefix
        <> T.intercalate ", " (take 2 desires)
        <> ". "
        <> consciousnessSkillLabel
        <> skill
        <> narrativeApplySuffix

deriveFocus :: KernelOutput -> Text -> Text
deriveFocus output inputText
  | T.null (koFocusHint output) = focusHumanPrefix <> T.take 30 inputText
  | otherwise = koFocusHint output
