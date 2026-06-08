{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-| Proposition classification from user text into canonical move families and semantic frames.

This module has been refactored into focused sub-modules for better maintainability.
It re-exports all public functions to maintain backward compatibility.

Original file (2435 lines) backed up as Proposition.hs.backup
-}
module QxFx0.Semantic.Proposition
  ( -- * Core Types
    PropositionType(..)
  , propositionToFamily
  , propositionTypeFromText
  , propositionTypeText
  , diagnosticPropositionFamily
  , diagnosticPropositionFamilyTyped
  , toFallbackType
  , fromFallbackType
    -- * Parsing Functions
  , parseProposition
  , parsePropositionWithTruthContract
  , parsePropositionWithFrame
  , parsePropositionWithFrameAndTruthContract
  , parsePropositionMorph
    -- * Focus Extraction
  , extractFocusEntity
  , extractKeyPhrases
  , dedupeNormalized
  , dedupeEvidence
  , isSemanticCandidateSurface
  , isFocusCandidate
  , normalizeFocus
  , logicalFocusStopwords
    -- * Semantic Analysis
  , inferSemanticSlots
  , specialFocusEntity
  , semanticEvidenceFor
  , computeConfidence
  , detectEmotion
  , clamp01
  , invitationTopic
  , conceptSubject
  , contemplativeTopic
  , extractTopicAfterMarkers
  , asksAboutUser
  , comparisonCandidates
  , hasConcreteWorldNoun
  , hasMentalNoun
  , hasConceptLikeNoun
  , firstConcreteWorldNoun
  , firstMentalNoun
  , firstNonVapid
  , lastNonVapid
  , capabilitySubject
    -- * Detection
  , detectPropositionType
  , detectRegressionFamilyOverrides
  , detectKeywordFallbackType
  , collectRawKeywordFallbackDecisions
  , buildKeywordFallbackTypeFromDecisions
  , detectContactSignal
  , detectConfrontSignal
  , detectNextStepSignal
  , detectAffectiveSupport
  , detectSelfKnowledge
  , detectPurposeFunction
  , detectDialogueInvitation
  , detectConceptKnowledge
  , detectWorldCause
  , detectLocationFormation
  , detectSelfState
  , detectComparisonPlausibility
  , detectMisunderstanding
  , detectRepairDirective
  , detectGenerativePrompt
  , detectContemplativeTopic
  , detectExploratoryPrompt
  , detectOperationalStatus
  , detectOperationalCause
  , detectSystemLogic
  , detectDistinctionQuestion
    -- * Fallback Detection
  , RawPropositionKeywordFallbackDecision(..)
  , collectRawContactTriggers
  , fallbackKeywordGroups
  , collectKeywordFallbackDecision
  , fallbackDecisionToPhraseDecisions
  , matchKeywords
  ) where

-- Re-export from sub-modules
import QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , propositionToFamily
  , propositionTypeFromText
  , propositionTypeText
  , diagnosticPropositionFamily
  , diagnosticPropositionFamilyTyped
  , toFallbackType
  , fromFallbackType
  )

import QxFx0.Semantic.Proposition.Parse
  ( parseProposition
  , parsePropositionWithTruthContract
  , parsePropositionWithFrame
  , parsePropositionWithFrameAndTruthContract
  , parsePropositionMorph
  )

import QxFx0.Semantic.Proposition.Focus
  ( extractFocusEntity
  , extractKeyPhrases
  , dedupeNormalized
  , dedupeEvidence
  , isSemanticCandidateSurface
  , isFocusCandidate
  , normalizeFocus
  , logicalFocusStopwords
  )

import QxFx0.Semantic.Proposition.Semantic
  ( inferSemanticSlots
  , specialFocusEntity
  , semanticEvidenceFor
  , computeConfidence
  , detectEmotion
  , clamp01
  , invitationTopic
  , conceptSubject
  , contemplativeTopic
  , extractTopicAfterMarkers
  , asksAboutUser
  , comparisonCandidates
  , hasConcreteWorldNoun
  , hasMentalNoun
  , hasConceptLikeNoun
  , firstConcreteWorldNoun
  , firstMentalNoun
  , firstNonVapid
  , lastNonVapid
  , capabilitySubject
  , fallbackKeywordGroups
  , collectKeywordFallbackDecision
  , fallbackDecisionToPhraseDecisions
  , matchKeywords
  )

import QxFx0.Semantic.Proposition.Detection
  ( detectPropositionType
  , detectRegressionFamilyOverrides
  , detectKeywordFallbackType
  , collectRawKeywordFallbackDecisions
  , buildKeywordFallbackTypeFromDecisions
  )

-- Re-export types needed by public API
import QxFx0.Types.PropositionFallbackAdmission
  ( RawPropositionKeywordFallbackDecision(..)
  )

-- Re-export full detection chain
import QxFx0.Semantic.Proposition.Detectors

-- Refactored: 2026-06-03
-- Original: 2435 lines → New: 145 lines (94% reduction)
-- Modules: Types (225), Focus (222), Semantic (583), Detection (155), Detection(Detectors ~1446), Parse (283)
-- Total: ~2900 lines across 6 focused modules
