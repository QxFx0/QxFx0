{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Recovery
  ( LocalRecoveryPolicy(..)
  , LocalRecoveryCause(..)
  , LocalRecoveryStrategy(..)
  , renderLocalRecoveryPolicy
  , renderLocalRecoveryCause
  , renderLocalRecoveryStrategy
  ) where

import Data.Aeson (FromJSON, ToJSON(..))
import Data.Text (Text)
import GHC.Generics (Generic)

data LocalRecoveryPolicy
  = LocalRecoveryEnabled
  | LocalRecoveryDisabled
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data LocalRecoveryCause
  = RecoveryLowLegitimacy
  | RecoveryParserLowConfidence
  | RecoveryShadowUnavailable
  | RecoveryShadowDivergence
  | RecoveryRenderBlocked
  | RecoveryUnknownTopic
  | RecoveryRuntimeDegraded
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

instance ToJSON LocalRecoveryCause where
  toJSON = toJSON . renderLocalRecoveryCause

data LocalRecoveryStrategy
  = StrategyAskClarification
  | StrategyNarrowScope
  | StrategyDefineKnownTerms
  | StrategyDistinguishCandidates
  | StrategyExposeUncertainty
  | StrategySafeRecovery
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

instance ToJSON LocalRecoveryStrategy where
  toJSON = toJSON . renderLocalRecoveryStrategy

renderLocalRecoveryPolicy :: LocalRecoveryPolicy -> Text
renderLocalRecoveryPolicy LocalRecoveryEnabled = "enabled"
renderLocalRecoveryPolicy LocalRecoveryDisabled = "disabled"

renderLocalRecoveryCause :: LocalRecoveryCause -> Text
renderLocalRecoveryCause RecoveryLowLegitimacy = "low_legitimacy"
renderLocalRecoveryCause RecoveryParserLowConfidence = "parser_low_confidence"
renderLocalRecoveryCause RecoveryShadowUnavailable = "shadow_unavailable"
renderLocalRecoveryCause RecoveryShadowDivergence = "shadow_divergence"
renderLocalRecoveryCause RecoveryRenderBlocked = "render_blocked"
renderLocalRecoveryCause RecoveryUnknownTopic = "unknown_topic"
renderLocalRecoveryCause RecoveryRuntimeDegraded = "runtime_degraded"

renderLocalRecoveryStrategy :: LocalRecoveryStrategy -> Text
renderLocalRecoveryStrategy StrategyAskClarification = "ask_clarification"
renderLocalRecoveryStrategy StrategyNarrowScope = "narrow_scope"
renderLocalRecoveryStrategy StrategyDefineKnownTerms = "define_known_terms"
renderLocalRecoveryStrategy StrategyDistinguishCandidates = "distinguish_candidates"
renderLocalRecoveryStrategy StrategyExposeUncertainty = "expose_uncertainty"
renderLocalRecoveryStrategy StrategySafeRecovery = "safe_recovery"
