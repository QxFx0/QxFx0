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

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withText)
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Decode an enum from the text its render function produces, by inverting the
-- render map over all constructors. Keeps render/parse in lockstep — a new
-- constructor is automatically parseable as soon as it has a render case.
parseRendered :: (Bounded a, Enum a) => String -> (a -> Text) -> Value -> Parser a
parseRendered label render = withText label $ \t ->
  case lookup t [(render c, c) | c <- [minBound .. maxBound]] of
    Just c  -> pure c
    Nothing -> fail (label <> ": unrecognized rendered value " <> T.unpack t)

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
  | RecoveryLearningNeed
  | RecoveryConatusGate
    -- ^ Phase 2.5 (M2d): the runtime Conatus energy dropped
    --   below 'conatusGateThreshold' indicating structural risk.
    --   Triggered exclusively by
    --   'QxFx0.Self.Salience.conatusGateFires' in
    --   'QxFx0.Core.TurnPipeline.Route.Render.buildLocalRecoveryPlan'.
    --   Distinct from 'RecoveryRuntimeDegraded' (which means
    --   the runtime mode itself is degraded for environmental
    --   reasons, e.g. shadow unavailability, partial DB).
  deriving stock (Eq, Show, Generic, Bounded, Enum)

instance ToJSON LocalRecoveryCause where
  toJSON = toJSON . renderLocalRecoveryCause

-- | Inverse of 'renderLocalRecoveryCause' (the format 'ToJSON' writes). The
-- generic 'FromJSON' would expect the constructor name ("RecoveryLowLegitimacy")
-- and so fail to decode the rendered snake_case ("low_legitimacy"); this parser
-- keeps the round-trip total. Auto-syncs with the render map via [minBound..].
instance FromJSON LocalRecoveryCause where
  parseJSON = parseRendered "LocalRecoveryCause" renderLocalRecoveryCause

data LocalRecoveryStrategy
  = StrategyAskClarification
  | StrategyNarrowScope
  | StrategyDefineKnownTerms
  | StrategyDistinguishCandidates
  | StrategyExposeUncertainty
  | StrategySafeRecovery
  | StrategyMorphologyExpansion
    -- ^ WP1 (GAP1): Conatus-gradient recovery — morphology component
    --   (∂m) is dominant; system should expand morphological substrate.
  | StrategyIdentityReinforcement
    -- ^ WP1 (GAP1): Conatus-gradient recovery — identity component
    --   (∂c) is dominant; system should reinforce identity claims.
  | StrategyTemporalDeepening
    -- ^ WP1 (GAP1): Conatus-gradient recovery — temporal component
    --   (∂t) is dominant; system should deepen temporal continuity.
  | StrategyRequestCalibration
    -- ^ WP3: learning-driven recovery — salience weights need
    --   empirical calibration; system requests external calibration data.
  | StrategyRequestRule
    -- ^ WP3: learning-driven recovery — routing or deliberation
    --   rule is insufficient; system requests a validated rule update.
  | StrategyRequestConcept
    -- ^ WP3: learning-driven recovery — concept / keyword gap
    --   is persistent; system requests an external concept addition.
  | StrategyExternalDialogue
    -- ^ Phase 9: autonomous exploratory learning — system initiates
    --   an external dialogue query to acquire new knowledge.
  deriving stock (Eq, Show, Generic, Bounded, Enum)

instance ToJSON LocalRecoveryStrategy where
  toJSON = toJSON . renderLocalRecoveryStrategy

-- | Inverse of 'renderLocalRecoveryStrategy' (see 'LocalRecoveryCause' note).
instance FromJSON LocalRecoveryStrategy where
  parseJSON = parseRendered "LocalRecoveryStrategy" renderLocalRecoveryStrategy

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
renderLocalRecoveryCause RecoveryLearningNeed = "learning_need"
renderLocalRecoveryCause RecoveryConatusGate = "conatus_gate"

renderLocalRecoveryStrategy :: LocalRecoveryStrategy -> Text
renderLocalRecoveryStrategy StrategyAskClarification = "ask_clarification"
renderLocalRecoveryStrategy StrategyNarrowScope = "narrow_scope"
renderLocalRecoveryStrategy StrategyDefineKnownTerms = "define_known_terms"
renderLocalRecoveryStrategy StrategyDistinguishCandidates = "distinguish_candidates"
renderLocalRecoveryStrategy StrategyExposeUncertainty = "expose_uncertainty"
renderLocalRecoveryStrategy StrategySafeRecovery = "safe_recovery"
renderLocalRecoveryStrategy StrategyMorphologyExpansion = "morphology_expansion"
renderLocalRecoveryStrategy StrategyIdentityReinforcement = "identity_reinforcement"
renderLocalRecoveryStrategy StrategyTemporalDeepening = "temporal_deepening"
renderLocalRecoveryStrategy StrategyRequestCalibration = "request_calibration"
renderLocalRecoveryStrategy StrategyRequestRule = "request_rule"
renderLocalRecoveryStrategy StrategyRequestConcept = "request_concept"
renderLocalRecoveryStrategy StrategyExternalDialogue = "external_dialogue"
