{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Narrative/intuition modulation hints that influence family preference and plans. -}
module QxFx0.Core.TurnModulation.Narrative
  ( modulateRMPWithNarrative
  , modulateRCPWithFlash
  , narrativeFamilyHint
  , intuitionFamilyHint
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.Consciousness (ConsciousnessNarrative(..))
import QxFx0.Core.Policy.Consciousness
  ( narrativeSkillAnalyzeName
  , narrativeSkillHoldName
  , narrativeSkillListenName
  , narrativeSkillPresenceName
  , narrativeSkillResistName
  , narrativeSkillResonateName
  , narrativeSkillSilenceName
  , narrativeSkillTeachName
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( containsKeywordPhrase
  , tokenizeKeywordText
  )
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( narrativeDeepCharsThreshold
  , narrativeIntuitionFamilyHintThreshold
  )

modulateRMPWithNarrative :: Maybe Text -> ResponseMeaningPlan -> ResponseMeaningPlan
modulateRMPWithNarrative narrativeFragment meaningPlan =
  case narrativeFragment of
    Just fragment | not (T.null fragment) ->
      meaningPlan
        { rmpDepthMode =
            if T.length fragment > narrativeDeepCharsThreshold
              then DeepDepth
              else rmpDepthMode meaningPlan
        , rmpTopic =
            if T.null (rmpTopic meaningPlan)
              then T.take 40 fragment
              else rmpTopic meaningPlan
        }
    _ -> meaningPlan

modulateRCPWithFlash :: Bool -> ResponseContentPlan -> ResponseContentPlan
modulateRCPWithFlash overridesAll contentPlan =
  if overridesAll
    then contentPlan {rcpStyle = StyleDirect}
    else contentPlan

narrativeFamilyHint :: ConsciousnessNarrative -> Maybe CanonicalMoveFamily
narrativeFamilyHint narrative =
  let skill = cnSkillInPlay narrative
      skillTokens = tokenizeKeywordText skill
      conflict = cnConflict narrative
   in if containsKeywordPhrase skillTokens narrativeSkillSilenceName
        then Just CMAnchor
        else
          if not (T.null conflict)
            then Just CMReflect
            else
              if containsKeywordPhrase skillTokens narrativeSkillListenName
                then Just CMContact
                else
                  if containsKeywordPhrase skillTokens narrativeSkillPresenceName
                    then Just CMContact
                    else
                      if containsKeywordPhrase skillTokens narrativeSkillResonateName
                        then Just CMContact
                        else
                          if containsKeywordPhrase skillTokens narrativeSkillTeachName
                            then Just CMClarify
                            else
                              if containsKeywordPhrase skillTokens narrativeSkillAnalyzeName
                                then Just CMDeepen
                                else
                                  if containsKeywordPhrase skillTokens narrativeSkillResistName
                                    then Just CMGround
                                    else
                                      if containsKeywordPhrase skillTokens narrativeSkillHoldName
                                        then Just CMAnchor
                                        else Nothing

intuitionFamilyHint :: Double -> Maybe CanonicalMoveFamily
intuitionFamilyHint posterior
  | posterior > narrativeIntuitionFamilyHintThreshold = Just CMDeepen
  | otherwise = Nothing
