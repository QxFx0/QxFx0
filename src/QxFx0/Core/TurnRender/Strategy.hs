{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Render-strategy adaptation from routing decisions and identity signal cues. -}
module QxFx0.Core.TurnRender.Strategy
  ( applyRenderStrategy
  , renderStyleFromDecision
  , strategyDepthMode
  , strategyToAnswerStrategy
  , responseStanceToMarker
  , strategyEpistemicFromDepth
  , strategyDepthLabel
  ) where

import Data.Text (Text)

import QxFx0.Core.IdentitySignal (IdentitySignal(..))
import QxFx0.Core.PrincipledCore (PrincipledMode(..))
import QxFx0.Core.R5Dynamics (EncounterMode(..))
import QxFx0.Core.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( strategyDeepKnownConfidenceCap
  , strategyDeepKnownConfidenceBoost
  , strategyDeepProbableToKnownCap
  , strategyDeepProbableToKnownBoost
  , strategyDeepUncertainToProbableCap
  , strategyDeepUncertainToProbableBoost
  , strategyDeepUnknownToUncertainCap
  , strategyDeepSpeculativeToUncertainCap
  , strategyShallowKnownToProbableFloor
  , strategyShallowKnownPenalty
  , strategyShallowProbableToUncertainFloor
  , strategyShallowProbablePenalty
  )

applyRenderStrategy :: CanonicalMoveFamily -> ResponseStrategy -> ResponseMeaningPlan -> ResponseMeaningPlan
applyRenderStrategy family strategy meaningPlan =
  meaningPlan
    { rmpStrategy = strategyToAnswerStrategy family strategy
    , rmpStance = responseStanceToMarker (rsStance strategy)
    , rmpEpistemic = strategyEpistemicFromDepth (rsDepth strategy) (rmpEpistemic meaningPlan)
    , rmpDepthMode = strategyDepthMode (rsDepth strategy)
    }

renderStyleFromDecision :: ResponseStrategy -> Maybe PrincipledMode -> IdentitySignal -> Maybe SemanticAnchor -> SemanticInput -> RenderStyle
renderStyleFromDecision strategy mode identitySignal semanticAnchor semanticInput =
  let byStrategy = styleFromStrategy strategy
      byPrincipled = styleFromPrincipled mode byStrategy
      byIdentity = styleFromIdentity identitySignal byPrincipled
      bySemantic = styleFromSemantic semanticInput byIdentity
   in maybe bySemantic (`styleFromAnchor` bySemantic) semanticAnchor

strategyDepthMode :: ResponseDepth -> DepthMode
strategyDepthMode DeepResp = DeepDepth
strategyDepthMode ModerateResp = MediumDepth
strategyDepthMode ShallowResp = SurfaceDepth

strategyToAnswerStrategy :: CanonicalMoveFamily -> ResponseStrategy -> AnswerStrategy
strategyToAnswerStrategy _family strategy =
  case rsMove strategy of
    CounterMove -> DeepenThenProbe
    ReframeMove -> ClarifyThenDisambiguate
    QuestionMove -> DeepenThenProbe
    ValidateMove -> ContactThenBridge
    SilenceMove -> AnchorThenStabilize

responseStanceToMarker :: ResponseStance -> StanceMarker
responseStanceToMarker HoldStance = Firm
responseStanceToMarker OpenStance = Explore
responseStanceToMarker RedirectStance = Observe
responseStanceToMarker AcknowledgeStance = Honest

strategyEpistemicFromDepth :: ResponseDepth -> EpistemicStatus -> EpistemicStatus
strategyEpistemicFromDepth depth current =
  case depth of
    DeepResp ->
      case current of
        Known confidence ->
          Known
            (min strategyDeepKnownConfidenceCap (confidence + strategyDeepKnownConfidenceBoost))
        Probable confidence ->
          Known
            (min strategyDeepProbableToKnownCap (confidence + strategyDeepProbableToKnownBoost))
        Uncertain confidence ->
          Probable
            (min strategyDeepUncertainToProbableCap (confidence + strategyDeepUncertainToProbableBoost))
        Unknown confidence ->
          Uncertain
            (min strategyDeepUnknownToUncertainCap (confidence + strategyDeepUncertainToProbableBoost))
        Speculative confidence ->
          Uncertain
            (min strategyDeepSpeculativeToUncertainCap (confidence + strategyDeepUncertainToProbableBoost))
    ModerateResp -> current
    ShallowResp ->
      case current of
        Known confidence ->
          Probable
            (max strategyShallowKnownToProbableFloor (confidence - strategyShallowKnownPenalty))
        Probable confidence ->
          Uncertain
            (max strategyShallowProbableToUncertainFloor (confidence - strategyShallowProbablePenalty))
        other -> other

strategyDepthLabel :: ResponseDepth -> Text
strategyDepthLabel = depthModeText . strategyDepthMode

styleFromStrategy :: ResponseStrategy -> RenderStyle
styleFromStrategy strategy =
  case (rsStance strategy, rsMove strategy, rsDepth strategy) of
    (HoldStance, _, _) -> StyleFormal
    (_, CounterMove, _) -> StyleDirect
    (_, _, DeepResp) -> StylePoetic
    (AcknowledgeStance, _, _) -> StyleWarm
    _ -> StyleStandard

styleFromPrincipled :: Maybe PrincipledMode -> RenderStyle -> RenderStyle
styleFromPrincipled mode fallback =
  case mode of
    Just HoldGround -> StyleFormal
    Just AcknowledgeAndHold -> StyleWarm
    _ -> fallback

styleFromIdentity :: IdentitySignal -> RenderStyle -> RenderStyle
styleFromIdentity identitySignal fallback =
  case isEncounterMode identitySignal of
    EncounterRecovery -> StyleWarm
    EncounterHolding -> StyleFormal
    EncounterPressure -> StyleDirect
    _ -> fallback

styleFromSemantic :: SemanticInput -> RenderStyle -> RenderStyle
styleFromSemantic semanticInput fallback =
  case siNeedLayer semanticInput of
    ContactLayer -> StyleWarm
    MetaLayer -> StyleFormal
    ContentLayer -> fallback

styleFromAnchor :: SemanticAnchor -> RenderStyle -> RenderStyle
styleFromAnchor anchor fallback
  | saDominantChannel anchor == ChannelContact = StyleWarm
  | saDominantChannel anchor == ChannelAnchor = StyleFormal
  | otherwise = fallback
