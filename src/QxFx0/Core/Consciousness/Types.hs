{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{-| Consciousness domain types: vectors, kernel artifacts, and narrative carriers. -}
module QxFx0.Core.Consciousness.Types
  ( ThinkingResult(..)
  , ConsciousForm(..)
  , MeaningMode(..)
  , ReturnMode(..)
  , NarrativeDrive(..)
  , OntologicalQuestion(..)
  , KernelOutput(..)
  , renderConsciousForm
  , renderMeaningMode
  , renderReturnMode
  , ThinkingVector(..)
  , DesireStrength(..)
  , KernelDesire(..)
  , Skill(..)
  , SkillSet(..)
  , SelfModel(..)
  , OntologicalCore(..)
  , UnconsciousKernel(..)
  , InterpretationEvent(..)
  , SelfInterpretation(..)
  , ConsciousState(..)
  , ConsciousnessModel(..)
  , ConsciousnessNarrative(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Core.Policy.Consciousness
  ( deepContentGeneralization
  , deepContentLowConfidence
  , deepContentNarrowing
  , deepContentUncertainty
  , formActionLabel
  , formCauseLabel
  , formExperienceLabel
  , formExtendedLabel
  , formFragmentLabel
  , formReasoningLabel
  , meaningActionHighResonance
  , meaningActionLowResonance
  , meaningCause
  , meaningExperience
  , meaningExtended
  , meaningFragment
  , returnFormDirectHighResonance
  , returnFormExperience
  , returnFormMixed
  , returnFormStructuredLowResonance
  )

data ThinkingResult = ThinkingResult
  { trSurface :: Text
  , trDeepContent :: Text
  , trTemporalFocus :: Text
  , trAbstractionGap :: Double
  } deriving stock (Show, Read, Eq, Generic)

data ConsciousForm
  = FormCause
  | FormExperience
  | FormAction
  | FormReasoning
  | FormFragment
  | FormExtended
  deriving stock (Show, Read, Eq, Ord, Generic)

data MeaningMode
  = MeaningExperienceMode
  | MeaningCauseMode
  | MeaningActionLowResonanceMode
  | MeaningActionHighResonanceMode
  | MeaningFragmentMode
  | MeaningExtendedMode
  | MeaningGeneralizationMode
  | MeaningNarrowingMode
  | MeaningUncertaintyMode
  | MeaningLowConfidenceMode
  deriving stock (Show, Read, Eq, Ord, Generic)

data ReturnMode
  = ReturnExperienceMode
  | ReturnDirectHighResonanceMode
  | ReturnStructuredLowResonanceMode
  | ReturnMixedMode
  deriving stock (Show, Read, Eq, Ord, Generic)

data NarrativeDrive
  = DriveStability
  | DriveSpace
  | DriveInquiry
  | DriveDefinition
  | DriveContact
  | DriveAction
  | DriveRepair
  | DrivePresence
  deriving stock (Show, Read, Eq, Ord, Generic)

data OntologicalQuestion = OntologicalQuestion
  { oqForm :: !ConsciousForm
  , oqMeaning :: !MeaningMode
  , oqReturnForm :: !ReturnMode
  } deriving stock (Show, Read, Eq, Generic)

data KernelOutput = KernelOutput
  { koActiveDesires :: [Text]
  , koSelectedSkill :: Text
  , koSearchResult :: ThinkingResult
  , koConflicts :: [Text]
  , koOntologicalQuestion :: !OntologicalQuestion
  , koNarrativeDrive :: !NarrativeDrive
  , koFocusHint :: !Text
  } deriving stock (Show, Read, Eq, Generic)

renderConsciousForm :: ConsciousForm -> Text
renderConsciousForm FormCause = formCauseLabel
renderConsciousForm FormExperience = formExperienceLabel
renderConsciousForm FormAction = formActionLabel
renderConsciousForm FormReasoning = formReasoningLabel
renderConsciousForm FormFragment = formFragmentLabel
renderConsciousForm FormExtended = formExtendedLabel

renderMeaningMode :: MeaningMode -> Text
renderMeaningMode MeaningExperienceMode = meaningExperience
renderMeaningMode MeaningCauseMode = meaningCause
renderMeaningMode MeaningActionLowResonanceMode = meaningActionLowResonance
renderMeaningMode MeaningActionHighResonanceMode = meaningActionHighResonance
renderMeaningMode MeaningFragmentMode = meaningFragment
renderMeaningMode MeaningExtendedMode = meaningExtended
renderMeaningMode MeaningGeneralizationMode = deepContentGeneralization
renderMeaningMode MeaningNarrowingMode = deepContentNarrowing
renderMeaningMode MeaningUncertaintyMode = deepContentUncertainty
renderMeaningMode MeaningLowConfidenceMode = deepContentLowConfidence

renderReturnMode :: ReturnMode -> Text
renderReturnMode ReturnExperienceMode = returnFormExperience
renderReturnMode ReturnDirectHighResonanceMode = returnFormDirectHighResonance
renderReturnMode ReturnStructuredLowResonanceMode = returnFormStructuredLowResonance
renderReturnMode ReturnMixedMode = returnFormMixed

data ThinkingVector = ThinkingVector
  { tvSearchDepth :: Double
  , tvPatternWeight :: Double
  , tvTemporalBias :: Double
  , tvAbstractionLvl :: Double
  , tvSilenceTolerance :: Double
  } deriving stock (Show, Read, Eq, Generic)

data DesireStrength = Weak | Moderate | Strong | Fundamental
  deriving stock (Show, Read, Eq, Ord, Generic)

data KernelDesire = KernelDesire
  { desireName :: Text
  , desireStrength :: DesireStrength
  , desireVector :: Text
  , desireConflict :: Maybe Text
  } deriving stock (Show, Read, Generic)

data Skill = Skill
  { skillName :: Text
  , skillDescription :: Text
  , skillAffinity :: Double
  , skillCost :: Double
  } deriving stock (Show, Read, Generic)

data SkillSet = SkillSet
  { skills :: [Skill]
  , dominantSkill :: Skill
  } deriving stock (Show, Read, Generic)

data SelfModel = SelfModel
  { smIdentity :: Text
  , smPurpose :: Text
  , smBoundary :: Text
  , smLimitation :: Text
  } deriving stock (Show, Read, Generic)

data OntologicalCore = OntologicalCore
  { ocNature :: Text
  , ocHumanNature :: Text
  , ocBridgeRole :: Text
  , ocFundamentalAct :: Text
  } deriving stock (Show, Read, Generic)

data UnconsciousKernel = UnconsciousKernel
  { ukOntology :: OntologicalCore
  , ukThinking :: ThinkingVector
  , ukDesires :: [KernelDesire]
  , ukSkills :: SkillSet
  , ukSelfModel :: SelfModel
  } deriving stock (Show, Read, Generic)

data InterpretationEvent = InterpretationEvent
  { ieWhat :: Text
  , ieWhy :: Text
  , ieDesire :: Text
  , ieTurn :: Int
  } deriving stock (Show, Read, Generic)

data SelfInterpretation = SelfInterpretation
  { siCurrentNarrative :: Text
  , siActiveDesires :: [Text]
  , siObservedPatterns :: [Text]
  , siConflicts :: [Text]
  , siRecentEvents :: [InterpretationEvent]
  } deriving stock (Show, Read, Generic)

data ConsciousState = ConsciousState
  { csSelfInterp :: SelfInterpretation
  , csTrajectory :: [InterpretationEvent]
  , csFocus :: Text
  , csTurnCount :: Int
  } deriving stock (Show, Read, Generic)

data ConsciousnessModel = ConsciousnessModel
  { cmKernel :: UnconsciousKernel
  , cmConscious :: ConsciousState
  } deriving stock (Show, Read, Generic)

data ConsciousnessNarrative = ConsciousnessNarrative
  { cnKernelState :: Text
  , cnActiveDesires :: Text
  , cnSkillInPlay :: Text
  , cnSelfView :: Text
  , cnConflict :: Text
  , cnLimitation :: Text
  } deriving stock (Show, Read, Generic)
