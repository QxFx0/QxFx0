{-# LANGUAGE DerivingStrategies, OverloadedStrings #-}
{-| Stateful consciousness loop orchestration and post-response observation updates. -}
module QxFx0.Core.ConsciousnessLoop
  ( ConsciousnessLoop(..)
  , ResponseObservation(..)
  , initialLoop
  , runConsciousnessLoop
  , updateAfterResponse
  , addCoreSignal
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Core.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Core.Policy.Consciousness
  ( observeShortResponse, observeSurfacing, observeBoundary
  , observeQuestion, observeDefault
  , surfacingMarkerKeywords, boundaryMarkerKeywords
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsAnyKeywordPhrase
  )
import QxFx0.Core.Consciousness
  ( ConsciousnessModel(..)
  , ConsciousState(..), SelfInterpretation(..)
  , KernelOutput(..), ConsciousnessNarrative(..)
  , initialConsciousness
    , kernelPulse, interpretOutput
    , consciousnessToNarrative
    , narrativeToPromptFragment
  )
import QxFx0.Core.BackgroundProcess
  ( BackgroundState(..), SurfacingEvent(..)
  , initialBackground, runBackgroundCycle
  )

data CoreRegime = MonolithicMajority | BalancedSymmetry | ChildDominant
  deriving stock (Show, Read, Eq, Enum, Bounded)

data ConsciousnessLoop = ConsciousnessLoop
  { clModel         :: ConsciousnessModel
  , clLastOutput    :: Maybe KernelOutput
  , clLastNarrative :: Maybe ConsciousnessNarrative
  , clBackground    :: BackgroundState
  , clLastSurfacing :: Maybe SurfacingEvent
  , clDialogueTurn  :: Int
  , clRegime        :: CoreRegime
  , clDoubtScore    :: Double
  } deriving stock (Show)

initialLoop :: ConsciousnessLoop
initialLoop = ConsciousnessLoop
  { clModel         = initialConsciousness
  , clLastOutput    = Nothing
  , clLastNarrative = Nothing
  , clBackground    = initialBackground
  , clLastSurfacing = Nothing
  , clDialogueTurn  = 0
  , clRegime        = MonolithicMajority
    , clDoubtScore    = 0.0
    }

data ResponseObservation = ResponseObservation
  { roSurfaceText :: !Text
  , roQuestionLike :: !Bool
  } deriving stock (Show, Read, Eq)

runConsciousnessLoop :: ConsciousnessLoop -> SemanticInput -> Double -> Double -> (ConsciousnessLoop, Text)
runConsciousnessLoop loop semanticInput humanTheta resonance =
  let model = clModel loop
      turn  = clDialogueTurn loop + 1
      inputText = siRawInput semanticInput
      output = kernelPulse (cmKernel model) semanticInput humanTheta resonance turn
      skillN = koSelectedSkill output
      desireNs = koActiveDesires output
      conflicts = koConflicts output
      (newBg, mSurfacing) = runBackgroundCycle (clBackground loop) skillN desireNs conflicts
      model' = interpretOutput model output inputText
      narrative = consciousnessToNarrative model' output
      loop' = loop
        { clModel         = model'
        , clLastOutput    = Just output
        , clLastNarrative = Just narrative
        , clBackground    = newBg
        , clLastSurfacing = mSurfacing
        , clDialogueTurn  = turn
        }
      fragment = narrativeToPromptFragment narrative
  in (loop', fragment)

updateAfterResponse :: ConsciousnessLoop -> ResponseObservation -> ConsciousnessLoop
updateAfterResponse loop observation =
  let model = clModel loop
      cs = cmConscious model
      si = csSelfInterp cs
      obs = observeOwnResponse observation
      newSI = si { siObservedPatterns = take 5 (obs : siObservedPatterns si) }
      model' = model { cmConscious = cs { csSelfInterp = newSI } }
  in loop { clModel = model' }

addCoreSignal :: Text -> ConsciousnessLoop -> ConsciousnessLoop
addCoreSignal sig loop =
  let model = clModel loop
      cs = cmConscious model
      si = csSelfInterp cs
      newSI = si { siObservedPatterns = take 5 (sig : siObservedPatterns si) }
  in loop { clModel = model { cmConscious = cs { csSelfInterp = newSI } } }

observeOwnResponse :: ResponseObservation -> Text
observeOwnResponse observation =
  let response = roSurfaceText observation
      tokens = tokenizeKeywordText response
      wc = length (T.words response)
  in if wc <= 8 then observeShortResponse
     else if containsAnyKeywordPhrase tokens surfacingMarkerKeywords then observeSurfacing
     else if containsAnyKeywordPhrase tokens boundaryMarkerKeywords then observeBoundary
     else if roQuestionLike observation then observeQuestion
     else observeDefault
