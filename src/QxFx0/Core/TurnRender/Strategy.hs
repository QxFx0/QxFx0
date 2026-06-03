{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Render-strategy adaptation from routing decisions and identity signal cues. -}
module QxFx0.Core.TurnRender.Strategy
  ( applyRenderStrategy
  , applyRenderStrategyWithTruthContract
  , renderStyleFromDecision
  , renderStyleFromDecisionWithSalience
  , applySalienceToStyle
  , strategyDepthMode
  , strategyToAnswerStrategy
  , responseStanceToMarker
  , strategyEpistemicFromDepth
  , strategyDepthLabel
  ) where

import Data.Text (Text)

import QxFx0.Core.TruthContract (capByTruthContract)
import QxFx0.Core.IdentitySignal (IdentitySignal(..))
import QxFx0.Core.PrincipledCore (PrincipledMode(..))
import QxFx0.Core.R5Dynamics (EncounterMode(..))
import QxFx0.Self.Adjunction (Holistic(..), Formal(..), Adjunction(..))
import QxFx0.Self.Field (Field)
import QxFx0.Self.Deliberation (NarrativeTone(..))
import QxFx0.Self.Salience
  ( Salience
  , SalienceWeights
  , SalienceDriver(..)
  , SalienceVerdict(..)
  , chooseBranch
  , salienceDriver
  , salienceVerdict
  )
import QxFx0.Semantic.SemanticInput (SemanticInput(..))
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

applyRenderStrategyWithTruthContract :: TruthContractStatus -> CanonicalMoveFamily -> ResponseStrategy -> ResponseMeaningPlan -> ResponseMeaningPlan
applyRenderStrategyWithTruthContract truthStatus family strategy meaningPlan =
  meaningPlan
    { rmpStrategy = strategyToAnswerStrategy family strategy
    , rmpStance = responseStanceToMarker (rsStance strategy)
    , rmpEpistemic = strategyEpistemicFromDepthWithTruthContract truthStatus (rsDepth strategy) (rmpEpistemic meaningPlan)
    , rmpDepthMode = strategyDepthMode (rsDepth strategy)
    }

renderStyleFromDecision :: ResponseStrategy -> Maybe PrincipledMode -> NarrativeTone -> IdentitySignal -> Maybe SemanticAnchor -> SemanticInput -> RenderStyle
renderStyleFromDecision strategy mode tone identitySignal semanticAnchor semanticInput =
  let byStrategy = styleFromStrategy strategy
      byPrincipled = styleFromPrincipled mode byStrategy
      byTone = styleFromTone tone byPrincipled
      byIdentity = styleFromIdentity identitySignal byTone
      bySemantic = styleFromSemantic semanticInput byIdentity
   in maybe bySemantic (`styleFromAnchor` bySemantic) semanticAnchor

-- | Salience-aware variant of 'renderStyleFromDecision'. The base
-- style is picked by the existing strategy/principled/identity/
-- semantic/anchor chain, then post-processed under the salience
-- verdict via 'applySalienceToStyle'.
--
-- Behaviour at neutral salience ('Tied' verdict, 'DrivenByDefault'
-- driver) is identity, so any call site that does not yet supply
-- rich Field signals observes no behaviour change.
renderStyleFromDecisionWithSalience
  :: SalienceWeights
  -> Salience
  -> Field
  -> ResponseStrategy
  -> Maybe PrincipledMode
  -> NarrativeTone
  -> IdentitySignal
  -> Maybe SemanticAnchor
  -> SemanticInput
  -> RenderStyle
renderStyleFromDecisionWithSalience salienceWeights salience field strategy mode tone identitySignal semanticAnchor semanticInput =
  applySalienceToStyle
    salienceWeights
    salience
    field
    (renderStyleFromDecision strategy mode tone identitySignal semanticAnchor semanticInput)

-- | Re-shape a 'RenderStyle' under a 'Salience' verdict via the
-- 'Holistic ⊣ Formal' adjunction.  This is the first runtime call
-- site of 'chooseBranch', making the adjunction types participate
-- in execution rather than remaining pure algebra.
--
-- Decision rule (matches ADR-0010 §4 and §5):
--
--   * 'DrivenByConatusGate' (structural risk) overrides every
--     other verdict and forces 'StyleRecovery'. This is the strict
--     reading of the Conatus-gate priority discipline.
--   * 'PreferFormal' verdict leans neutral and warm picks toward
--     formal/contract-respecting variants.
--   * 'PreferHolistic' verdict leans neutral and direct picks
--     toward expressive/holistic variants.
--   * 'Tied' verdict is identity — the dead band preserves the
--     style picked by the existing strategy chain.
--
-- Already-specialised picks (Clinical, Cautious, Recovery, and the
-- styles already aligned with the verdict) are preserved on every
-- branch so the controller does not /override/ a more informative
-- pick from the strategy chain.
applySalienceToStyle :: SalienceWeights -> Salience -> Field -> RenderStyle -> RenderStyle
applySalienceToStyle salienceWeights salience field baseStyle =
  case salienceDriver salience of
    DrivenByConatusGate -> StyleRecovery
    _ ->
      chooseBranch
        (salienceVerdict salienceWeights salience)
        (\(Holistic (base, _field)) -> holisticLean base)
        (\base -> Formal (\_field -> formalLean base))
        (Holistic (baseStyle, field))
  where
    formalLean StyleStandard = StyleFormal
    formalLean StyleWarm     = StyleFormal
    formalLean StyleDirect   = StyleFormal
    formalLean other         = other

    holisticLean StyleStandard = StylePoetic
    holisticLean StyleFormal   = StylePoetic
    holisticLean StyleDirect   = StyleWarm
    holisticLean other         = other

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
  let modulated =
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
  in modulated

strategyEpistemicFromDepthWithTruthContract :: TruthContractStatus -> ResponseDepth -> EpistemicStatus -> EpistemicStatus
strategyEpistemicFromDepthWithTruthContract truthStatus depth current =
  capByTruthContract truthStatus (strategyEpistemicFromDepth depth current)

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

styleFromTone :: NarrativeTone -> RenderStyle -> RenderStyle
styleFromTone tone fallback =
  case tone of
    NarrativeRecovery -> StyleRecovery
    NarrativeWarm -> StyleWarm
    NarrativeFormal -> StyleFormal
    NarrativeTerse -> StyleCautious
    NarrativeNeutral -> fallback

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
