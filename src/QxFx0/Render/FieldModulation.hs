{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Field-aware surface text modulation.

This module implements P6' (Field-Aware Rendering) from Track-I closure.
The Field (5-component right-hemispheric observation summary) influences
surface realization via 4 types of modulations:

1. fieldConfidence → epistemic hedges
2. fieldAtmosphere → lexical valence/arousal
3. fieldConsolidation → discourse connectors
4. fieldCounterfactual → alternative markers

Default-off via 'fieldAwareRenderingActive' flag in "QxFx0.Self.Field".
-}
module QxFx0.Render.FieldModulation
  ( applyFieldModulations
  , applyFieldConfidenceHedges
  , applyAtmosphereLexical
  , applyConsolidationConnectors
  , applyCounterfactualMarkers
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Function ((&))

import QxFx0.Self.Field
  ( Field(..)
  , FieldConfidence(..)
  , Atmosphere(..)
  , Consolidation(..)
  , Counterfactual(..)
  , fieldAwareRenderingActive
  )

-- | Apply all Field-driven modulations to surface text.
-- Identity function when 'fieldAwareRenderingActive' is False.
applyFieldModulations :: Field -> Text -> Text
applyFieldModulations field text
  | not fieldAwareRenderingActive = text
  | otherwise =
      text
        & applyFieldConfidenceHedges (fieldConfidence field)
        & applyAtmosphereLexical (fieldAtmosphere field)
        & applyConsolidationConnectors (fieldConsolidation field)
        & applyCounterfactualMarkers (fieldCounterfactual field)
  where
    (&) = flip ($)

-- | Modulate epistemic hedges based on FieldConfidence.
--
-- High confidence (> 0.7): strengthen assertions
-- Low confidence (< 0.3): add hedges
-- Mid-range: identity
applyFieldConfidenceHedges :: FieldConfidence -> Text -> Text
applyFieldConfidenceHedges (FieldConfidence conf) text
  | conf > 0.7 = strengthenAssertion text
  | conf < 0.3 = addHedge text
  | otherwise = text
  where
    strengthenAssertion t
      | "возможно" `T.isInfixOf` t = T.replace "возможно" "определённо" t
      | "может быть" `T.isInfixOf` t = T.replace "может быть" "скорее всего" t
      | otherwise = t

    addHedge t
      | T.null t = t
      | "определённо" `T.isInfixOf` t = T.replace "определённо" "возможно" t
      | "скорее всего" `T.isInfixOf` t = T.replace "скорее всего" "может быть" t
      | not (hasHedge t) = "Возможно, " <> t
      | otherwise = t

    hasHedge t = any (`T.isInfixOf` t) ["возможно", "может быть", "вероятно", "похоже"]

-- | Modulate lexical choice based on Atmosphere valence/arousal.
--
-- Positive valence: warmer lexical choices
-- Negative valence: more formal/neutral choices
-- High arousal: more dynamic verbs
applyAtmosphereLexical :: Atmosphere -> Text -> Text
applyAtmosphereLexical (Atmosphere valence arousal) text
  | valence > 0.6 = warmLexical text
  | valence < 0.4 = formalLexical text
  | arousal > 0.7 = dynamicLexical text
  | otherwise = text
  where
    warmLexical t = t
      & T.replace "необходимо" "важно"
      & T.replace "следует" "стоит"
      & T.replace "требуется" "нужно"

    formalLexical t = t
      & T.replace "важно" "необходимо"
      & T.replace "стоит" "следует"
      & T.replace "нужно" "требуется"

    dynamicLexical t = t
      & T.replace "рассмотрим" "исследуем"
      & T.replace "посмотрим" "проанализируем"

-- | Add discourse connectors based on Consolidation level.
--
-- High consolidation (> 0.7): add continuity markers
-- Low consolidation (< 0.3): add contrast markers
-- Mid-range: identity
applyConsolidationConnectors :: Consolidation -> Text -> Text
applyConsolidationConnectors (Consolidation consol) text
  | consol > 0.7 = addContinuity text
  | consol < 0.3 = addContrast text
  | otherwise = text
  where
    addContinuity t
      | T.null t = t
      | not (hasConnector t) = "Далее, " <> t
      | otherwise = t

    addContrast t
      | T.null t = t
      | not (hasConnector t) = "Однако, " <> t
      | otherwise = t

    hasConnector t = any (`T.isPrefixOf` t)
      ["Далее", "Однако", "Кроме того", "При этом", "Тем не менее"]

-- | Add alternative/counterfactual markers based on Counterfactual level.
--
-- High counterfactual (> 0.6): add alternative framing
-- Low counterfactual (< 0.2): identity
applyCounterfactualMarkers :: Counterfactual -> Text -> Text
applyCounterfactualMarkers (Counterfactual counter) text
  | counter > 0.6 = addAlternative text
  | otherwise = text
  where
    addAlternative t
      | T.null t = t
      | not (hasAlternative t) = "С другой стороны, " <> t
      | otherwise = t

    hasAlternative t = any (`T.isPrefixOf` t)
      ["С другой стороны", "Альтернативно", "Иначе говоря"]

