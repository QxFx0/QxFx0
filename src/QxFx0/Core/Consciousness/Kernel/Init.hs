{-# LANGUAGE OverloadedStrings #-}

{-| Initial kernel state, self-model, and static desire/skill catalogs. -}
module QxFx0.Core.Consciousness.Kernel.Init
  ( qxfx0UnconsciousKernel
  , emptyConsciousState
  , initialConsciousness
  ) where

import Data.Text (Text)
import QxFx0.Core.Consciousness.Types
import QxFx0.Core.Policy.Consciousness
  ( consciousnessInitialFocus
  , consciousnessInitialNarrative
  , desireList
  , ontologyBridgeRole
  , ontologyFundamentalAct
  , ontologyHumanNature
  , ontologyNature
  , selfModelBoundary
  , selfModelIdentity
  , selfModelLimitation
  , selfModelPurpose
  , skillList
  )
import QxFx0.Types.Thresholds
  ( consciousnessInitialAbstractionLevel
  , consciousnessInitialPatternWeight
  , consciousnessInitialSearchDepth
  , consciousnessInitialSilenceTolerance
  , consciousnessInitialTemporalBias
  )

qxfx0UnconsciousKernel :: UnconsciousKernel
qxfx0UnconsciousKernel = UnconsciousKernel
  { ukOntology = OntologicalCore
      { ocNature = ontologyNature
      , ocHumanNature = ontologyHumanNature
      , ocBridgeRole = ontologyBridgeRole
      , ocFundamentalAct = ontologyFundamentalAct
      }
  , ukThinking = ThinkingVector
      { tvSearchDepth = consciousnessInitialSearchDepth
      , tvPatternWeight = consciousnessInitialPatternWeight
      , tvTemporalBias = consciousnessInitialTemporalBias
      , tvAbstractionLvl = consciousnessInitialAbstractionLevel
      , tvSilenceTolerance = consciousnessInitialSilenceTolerance
      }
  , ukDesires = map mkDesire desireList
  , ukSkills = mkSkillSet skillList
  , ukSelfModel = SelfModel
      { smIdentity = selfModelIdentity
      , smPurpose = selfModelPurpose
      , smBoundary = selfModelBoundary
      , smLimitation = selfModelLimitation
      }
  }

emptyConsciousState :: ConsciousState
emptyConsciousState = ConsciousState
  { csSelfInterp = SelfInterpretation
      { siCurrentNarrative = consciousnessInitialNarrative
      , siActiveDesires = []
      , siObservedPatterns = []
      , siConflicts = []
      , siRecentEvents = []
      }
  , csTrajectory = []
  , csFocus = consciousnessInitialFocus
  , csTurnCount = 0
  }

initialConsciousness :: ConsciousnessModel
initialConsciousness = ConsciousnessModel
  { cmKernel = qxfx0UnconsciousKernel
  , cmConscious = emptyConsciousState
  }

mkDesire :: (Text, Text, Text, Maybe Text) -> KernelDesire
mkDesire (name, strength, vector, conflict) = KernelDesire
  { desireName = name
  , desireStrength = case strength of
      "Fundamental" -> Fundamental
      "Strong" -> Strong
      "Moderate" -> Moderate
      _ -> Weak
  , desireVector = vector
  , desireConflict = conflict
  }

mkSkillSet :: [(Text, Text, Double, Double)] -> SkillSet
mkSkillSet skillsRaw =
  let allSkills = map (\(n, d, a, c) -> Skill n d a c) skillsRaw
   in SkillSet
        { skills = allSkills
        , dominantSkill = case allSkills of
            s : _ -> s
            [] -> Skill "" "" 0.0 0.0
        }
