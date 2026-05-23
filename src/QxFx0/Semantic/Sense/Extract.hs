{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Sense.Extract
  ( extractSenseVector
  ) where

import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import qualified Data.Text as T

import QxFx0.Semantic.Input.Model
import QxFx0.Semantic.Sense

extractSenseVector :: UtteranceSemanticFrame -> SenseVector
extractSenseVector frame =
  let anchorTxt = if T.null (T.strip (usfTopic frame)) then "unknown" else usfTopic frame
      evidenceNodes = map (SemanticNodeId . wmuLemma) (take 6 (usfWordUnits frame))
      axes = foldl accumulateAxis M.empty (usfWordUnits frame)
      operators = nub [inferOperator frame]
      polarity = case usfPolarity frame of
        PolarityPositive -> SpAffirm
        PolarityNegative -> SpDeny
      lexicalFamily =
        let roots = nub (map wmuLemma (filter ((/= PosUnknown) . wmuPartOfSpeech) (usfWordUnits frame)))
        in case roots of
             root:_ -> Just (FamilyId root)
             [] -> Nothing
      toNode txt = if T.null (T.strip txt) then Nothing else Just (SemanticNodeId txt)
  in emptySenseVector
      { svAnchor = SemanticNodeId anchorTxt
      , svLexicalFamily = lexicalFamily
      , svEvidenceNodes = evidenceNodes
      , svAxes = axes
      , svOperators = operators
      , svPolarity = polarity
      , svAgent = toNode =<< Just (fromMaybeText (usfAgent frame))
      , svTarget = toNode =<< Just (fromMaybeText (usfTarget frame))
      , svConfidence = usfConfidence frame
      }
  where
    fromMaybeText = maybe "" id

accumulateAxis :: Map SenseAxis Double -> WordMeaningUnit -> Map SenseAxis Double
accumulateAxis acc unit =
  foldl (\m axis -> M.insertWith (+) axis 1.0 m) acc (mapMaybe semanticClassAxis (wmuSemanticClasses unit) ++ discourseAxes)
  where
    discourseAxes = concatMap discourseAxis (wmuDiscourseFunctions unit)

semanticClassAxis :: InputSemanticClass -> Maybe SenseAxis
semanticClassAxis cls = case cls of
  SemIdentity -> Just AxIdentity
  SemCause -> Just AxCause
  SemAction -> Just AxAction
  SemState -> Just AxState
  SemKnowledge -> Just AxKnowledge
  SemSelfReference -> Just AxSelf
  SemUserReference -> Just AxOther
  SemDialogueRepair -> Just AxRepair
  SemComparison -> Just AxComparison
  _ -> Nothing

discourseAxis :: InputDiscourseFunction -> [SenseAxis]
discourseAxis fn = case fn of
  DiscNegation -> [AxBoundary]
  DiscQuestion -> [AxKnowledge]
  DiscContrast -> [AxComparison, AxBoundary]
  DiscCause -> [AxCause]
  DiscClarification -> [AxRepair]
  _ -> []

inferOperator :: UtteranceSemanticFrame -> SenseOperator
inferOperator frame =
  case T.toLower (irhTag (usfRouteHint frame)) of
    "concept_knowledge" -> OpDefine
    "world_cause" -> OpExplainCause
    "comparison_plausibility" -> OpDistinguish
    "comparison_relation" -> OpDistinguish
    "misunderstanding" -> OpRepair
    "boundary_command" -> OpRepair
    "next_step" -> OpNextStep
    _ | usfSpeechAct frame == ActAsk -> OpConstrain
      | otherwise -> OpGround
