module QxFx0.Policy.SemanticScoring
  ( semanticLogicRepairWeight
  , semanticLogicContactWeight
  , semanticLogicDefineWeight
  , semanticLogicReflectWeight
  , semanticLogicAnchorWeight
  , semanticLogicClarifyWeight
  , semanticLogicDeepenWeight
  , semanticLogicConfrontWeight
  , semanticLogicDistinguishWeight
  , semanticLogicHypothesisWeight
  , semanticSpecialPurposeWeight
  , semanticSpecialDescribeWeight
  , semanticFallbackNextStepWeight
  , semanticFallbackGroundWeight
  , semanticAtomIntensity
  , semanticLexicalAgencyLostStrength
  , propositionBaseConfidenceDefinitional
  , propositionBaseConfidenceDistinction
  , propositionBaseConfidenceGround
  , propositionBaseConfidenceReflective
  , propositionBaseConfidenceSelfDescription
  , propositionBaseConfidencePurpose
  , propositionBaseConfidenceHypothetical
  , propositionBaseConfidenceRepair
  , propositionBaseConfidenceContact
  , propositionBaseConfidenceAnchor
  , propositionBaseConfidenceClarify
  , propositionBaseConfidenceDeepen
  , propositionBaseConfidenceConfront
  , propositionBaseConfidenceNextStep
  , propositionBaseConfidencePlainAssert
  , propositionBaseConfidenceAffective
  , propositionBaseConfidenceEpistemic
  , propositionBaseConfidenceRequest
  , propositionBaseConfidenceEvaluation
  , propositionBaseConfidenceNarrative
  , propositionBaseConfidenceSelfKnowledge
  , propositionBaseConfidenceDialogueInvitation
  , propositionBaseConfidenceConceptKnowledge
  , propositionBaseConfidenceWorldCause
  , propositionBaseConfidenceLocationFormation
  , propositionBaseConfidenceSelfState
  , propositionBaseConfidenceComparisonPlausibility
  , propositionBaseConfidenceMisunderstanding
  , propositionBaseConfidenceGenerativePrompt
  , propositionBaseConfidenceContemplativeTopic
  , propositionKeywordBonusPerPhrase
  , propositionKeywordBonusCap
  ) where

import QxFx0.Types.Domain (AtomTag(..))

semanticLogicRepairWeight :: Double
semanticLogicRepairWeight = 0.9

semanticLogicContactWeight :: Double
semanticLogicContactWeight = 0.8

semanticLogicDefineWeight :: Double
semanticLogicDefineWeight = 0.7

semanticLogicReflectWeight :: Double
semanticLogicReflectWeight = 0.7

semanticLogicAnchorWeight :: Double
semanticLogicAnchorWeight = 0.8

semanticLogicClarifyWeight :: Double
semanticLogicClarifyWeight = 0.6

semanticLogicDeepenWeight :: Double
semanticLogicDeepenWeight = 0.5

semanticLogicConfrontWeight :: Double
semanticLogicConfrontWeight = 0.9

semanticLogicDistinguishWeight :: Double
semanticLogicDistinguishWeight = 0.6

semanticLogicHypothesisWeight :: Double
semanticLogicHypothesisWeight = 0.4

semanticSpecialPurposeWeight :: Double
semanticSpecialPurposeWeight = 0.4

semanticSpecialDescribeWeight :: Double
semanticSpecialDescribeWeight = 0.15

semanticFallbackNextStepWeight :: Double
semanticFallbackNextStepWeight = 0.2

semanticFallbackGroundWeight :: Double
semanticFallbackGroundWeight = 0.1

semanticAtomIntensity :: AtomTag -> Double
semanticAtomIntensity tag = case tag of
  Exhaustion _ -> 0.85
  NeedContact _ -> 0.75
  NeedMeaning _ -> 0.72
  AgencyLost _ -> 0.60
  Searching _ -> 0.60
  Verification _ -> 0.50
  Doubt _ -> 0.40
  AgencyFound _ -> 0.55
  Anchoring _ -> 0.80
  Contradiction _ _ -> 0.90
  CustomAtom _ _ -> 0.30
  AffectiveAtom _ v -> abs v

semanticLexicalAgencyLostStrength :: Double
semanticLexicalAgencyLostStrength = 0.6

propositionBaseConfidenceDefinitional :: Double
propositionBaseConfidenceDefinitional = 0.85

propositionBaseConfidenceDistinction :: Double
propositionBaseConfidenceDistinction = 0.8

propositionBaseConfidenceGround :: Double
propositionBaseConfidenceGround = 0.8

propositionBaseConfidenceReflective :: Double
propositionBaseConfidenceReflective = 0.7

propositionBaseConfidenceSelfDescription :: Double
propositionBaseConfidenceSelfDescription = 0.65

propositionBaseConfidencePurpose :: Double
propositionBaseConfidencePurpose = 0.74

propositionBaseConfidenceHypothetical :: Double
propositionBaseConfidenceHypothetical = 0.6

propositionBaseConfidenceRepair :: Double
propositionBaseConfidenceRepair = 0.75

propositionBaseConfidenceContact :: Double
propositionBaseConfidenceContact = 0.8

propositionBaseConfidenceAnchor :: Double
propositionBaseConfidenceAnchor = 0.85

propositionBaseConfidenceClarify :: Double
propositionBaseConfidenceClarify = 0.65

propositionBaseConfidenceDeepen :: Double
propositionBaseConfidenceDeepen = 0.6

propositionBaseConfidenceConfront :: Double
propositionBaseConfidenceConfront = 0.55

propositionBaseConfidenceNextStep :: Double
propositionBaseConfidenceNextStep = 0.65

propositionBaseConfidencePlainAssert :: Double
propositionBaseConfidencePlainAssert = 0.5

propositionBaseConfidenceAffective :: Double
propositionBaseConfidenceAffective = 0.6

propositionBaseConfidenceEpistemic :: Double
propositionBaseConfidenceEpistemic = 0.7

propositionBaseConfidenceRequest :: Double
propositionBaseConfidenceRequest = 0.6

propositionBaseConfidenceEvaluation :: Double
propositionBaseConfidenceEvaluation = 0.65

propositionBaseConfidenceNarrative :: Double
propositionBaseConfidenceNarrative = 0.5

propositionBaseConfidenceSelfKnowledge :: Double
propositionBaseConfidenceSelfKnowledge = 0.82

propositionBaseConfidenceDialogueInvitation :: Double
propositionBaseConfidenceDialogueInvitation = 0.78

propositionBaseConfidenceConceptKnowledge :: Double
propositionBaseConfidenceConceptKnowledge = 0.8

propositionBaseConfidenceWorldCause :: Double
propositionBaseConfidenceWorldCause = 0.82

propositionBaseConfidenceLocationFormation :: Double
propositionBaseConfidenceLocationFormation = 0.82

propositionBaseConfidenceSelfState :: Double
propositionBaseConfidenceSelfState = 0.8

propositionBaseConfidenceComparisonPlausibility :: Double
propositionBaseConfidenceComparisonPlausibility = 0.82

propositionBaseConfidenceMisunderstanding :: Double
propositionBaseConfidenceMisunderstanding = 0.85

propositionBaseConfidenceGenerativePrompt :: Double
propositionBaseConfidenceGenerativePrompt = 0.78

propositionBaseConfidenceContemplativeTopic :: Double
propositionBaseConfidenceContemplativeTopic = 0.76

propositionKeywordBonusPerPhrase :: Double
propositionKeywordBonusPerPhrase = 0.02

propositionKeywordBonusCap :: Double
propositionKeywordBonusCap = 0.1
