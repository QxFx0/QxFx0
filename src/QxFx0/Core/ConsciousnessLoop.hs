{-# LANGUAGE DerivingStrategies, OverloadedStrings #-}
{-| Stateful consciousness loop orchestration and post-response observation updates. -}
module QxFx0.Core.ConsciousnessLoop
  ( ConsciousnessLoop(..)
  , ResponseObservation(..)
  , initialLoop
  , runConsciousnessLoop
  , runConsciousnessLoopWithSalience
  , applySalienceToNarrativeFragment
  , narrativeConfidenceThreshold
  , updateAfterResponse
  , addCoreSignal
  , computeDoubt
  , doubtLoopActive
  , doubtSuppressionThreshold
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Policy.Consciousness
  ( observeShortResponse, observeSurfacing, observeBoundary
  , observeQuestion, observeDefault
  , surfacingMarkerKeywords, boundaryMarkerKeywords
  )
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsAnyKeywordPhrase
  )
import QxFx0.Core.StanceClassifier
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
import QxFx0.Self.Salience
  ( Salience
  , SalienceDriver(..)
  , salienceConfidence
  , salienceDriver
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

-- | Salience-aware variant of 'runConsciousnessLoop'. Runs the
-- consciousness loop unchanged, then weights the resulting
-- narrative fragment under the supplied 'Salience' verdict via
-- 'applySalienceToNarrativeFragment'.
--
-- The 'ConsciousnessLoop' itself (model state, previous output,
-- current narrative, background, surfacing, turn counter) is
-- updated exactly as in 'runConsciousnessLoop' regardless of
-- salience.
-- Salience only weights the contribution of the narrative to the
-- /prompt/, never the kernel state. This keeps the consciousness
-- model's internal evolution decoupled from the controller, which
-- is the strict reading of ADR-0010 \u00a75 anti-correlation discipline
-- on this channel.
--
-- Behaviour at neutral salience ('salienceConfidence' \u2265 the
-- threshold and 'salienceDriver' /= 'DrivenByConatusGate') is
-- identity, so any call site that does not yet supply rich Field
-- signals observes no behaviour change.
runConsciousnessLoopWithSalience
  :: Salience
  -> ConsciousnessLoop
  -> SemanticInput
  -> Double
  -> Double
  -> (ConsciousnessLoop, Text)
runConsciousnessLoopWithSalience salience loop semanticInput humanTheta resonance =
  let (loop0, fragment) = runConsciousnessLoop loop semanticInput humanTheta resonance
      -- WP-D: derive a doubt score from the salience verdict and record it
      -- (previously clDoubtScore was initialised to 0.0 and never written).
      doubt  = computeDoubt salience
      loop'  = loop0 { clDoubtScore = doubt }
      -- WP-D reader: under the (default-off) doubt loop, a high doubt score
      -- suppresses the narrative fragment — the system "hesitates" when its
      -- own signals are uncertain, rather than asserting. Flag-off => identity.
      weighted
        | doubtLoopActive && doubt >= doubtSuppressionThreshold = T.empty
        | otherwise = applySalienceToNarrativeFragment salience fragment
  in (loop', weighted)

-- | WP-D: default-on promotion flag gating the doubt-driven narrative
-- suppression. Promoted to default-on (ADR-0045, 2026-06-04); registered in the
-- flag-off discipline (@scripts/check_architecture.sh@ rule [20]).
doubtLoopActive :: Bool
doubtLoopActive = True

-- | Doubt at or above which the narrative is suppressed when the loop is on.
doubtSuppressionThreshold :: Double
doubtSuppressionThreshold = 0.75

-- | WP-D: compute a doubt score in @[0,1]@ from the salience verdict. Doubt is
-- the complement of decisiveness (1 - confidence), amplified when the leading
-- driver is ambiguity (counterfactual spread) and forced high under a Conatus
-- gate (structural threat). This is the living producer of 'clDoubtScore'.
computeDoubt :: Salience -> Double
computeDoubt salience =
  let base = 1.0 - clamp01 (salienceConfidence salience)
  in clamp01 $ case salienceDriver salience of
       DrivenByConatusGate    -> max base 0.9
       DrivenByCounterfactual -> min 1.0 (base + 0.2)
       _                      -> base
  where
    clamp01 x = max 0.0 (min 1.0 x)

-- | Confidence threshold below which the narrative fragment is
-- suppressed (replaced by an empty 'Text') by
-- 'applySalienceToNarrativeFragment'.
--
-- The threshold is conservative: only configurations where the
-- salience drivers are strongly dispersed (no clear winner among
-- the five drivers) suppress the narrative. At neutral signals
-- ('emptyField' + placeholder Conatus), 'salienceConfidence' is
-- @1.0@ and the threshold is never tripped. See the doc on
-- 'QxFx0.Self.Salience.computeConfidence' for the dispersion
-- semantics.
narrativeConfidenceThreshold :: Double
narrativeConfidenceThreshold = 0.25

-- | Weight a narrative fragment by a 'Salience' verdict.
--
-- Decision rule (matches ADR-0010 \u00a74 and \u00a75):
--
--   * 'DrivenByConatusGate' (structural risk) overrides every
--     other verdict and suppresses the narrative entirely. Under
--     structural risk, the controller refuses to let the
--     consciousness narrative pollute the prompt.
--   * 'salienceConfidence' below 'narrativeConfidenceThreshold'
--     suppresses the narrative as well. The drivers disagree too
--     much for the verdict to be trusted, so the contribution is
--     dropped.
--   * Otherwise the fragment passes through unchanged. There is
--     no fractional weighting on the text \u2014 contribution is
--     binary at this layer (full or zero).
--
-- The downstream call sites already gate on @T.null fragment@
-- before adding the fragment to the prompt, so an empty fragment
-- naturally disappears from the prompt without further plumbing.
applySalienceToNarrativeFragment :: Salience -> Text -> Text
applySalienceToNarrativeFragment salience fragment =
  case salienceDriver salience of
    DrivenByConatusGate -> T.empty
    _
      | salienceConfidence salience < narrativeConfidenceThreshold -> T.empty
      | otherwise                                                   -> fragment

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
