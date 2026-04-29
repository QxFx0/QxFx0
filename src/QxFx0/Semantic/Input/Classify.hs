{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Semantic.Input.Classify
  ( classifyWordUnits
  ) where

import Data.List (findIndex)
import Data.Text (Text)

import QxFx0.Semantic.Input.Lexicon
  ( discourseFunctionsForToken
  , guessMorphFeatures
  , guessPartOfSpeech
  , isFunctionWord
  , lemmaForToken
  , semanticClassesForToken
  )
import QxFx0.Semantic.Input.Model
import QxFx0.Semantic.Input.Normalize (NormalizedInput(..))

classifyWordUnits :: NormalizedInput -> [WordMeaningUnit]
classifyWordUnits normalizedInput =
  assignSyntacticRoles (map classifyToken (niTokens normalizedInput))

classifyToken :: Text -> WordMeaningUnit
classifyToken token =
  let pos = guessPartOfSpeech token
      morphFeatures = guessMorphFeatures token
      semanticClasses = semanticClassesForToken token
      discourseFunctions = discourseFunctionsForToken token
      confidence
        | pos == PosUnknown = 0.35
        | isFunctionWord token = 0.7
        | otherwise = 0.82
      ambiguityCandidates =
        case pos of
          PosUnknown -> [token]
          PosAdverb -> [token, lemmaForToken token]
          PosAdjective -> [token, lemmaForToken token]
          _ -> [lemmaForToken token]
  in WordMeaningUnit
      { wmuSurfaceForm = token
      , wmuLemma = lemmaForToken token
      , wmuPartOfSpeech = pos
      , wmuMorphFeatures = morphFeatures
      , wmuSyntacticRole = SynUnknown
      , wmuSemanticClasses = semanticClasses
      , wmuDiscourseFunctions = discourseFunctions
      , wmuAmbiguityCandidates = ambiguityCandidates
      , wmuConfidence = confidence
      }

assignSyntacticRoles :: [WordMeaningUnit] -> [WordMeaningUnit]
assignSyntacticRoles units =
  zipWith assign [0 ..] units
  where
    rootIndex = findRootIndex units
    assign idx unit =
      unit {wmuSyntacticRole = inferRole rootIndex idx unit}

inferRole :: Int -> Int -> WordMeaningUnit -> InputSyntacticRole
inferRole rootIndex idx unit
  | idx == rootIndex = SynRoot
  | wmuPartOfSpeech unit == PosVerb = SynPredicate
  | idx < rootIndex && wmuPartOfSpeech unit `elem` [PosNoun, PosPronoun, PosNumeral] = SynSubject
  | idx > rootIndex && wmuPartOfSpeech unit `elem` [PosNoun, PosPronoun, PosNumeral] = SynObject
  | wmuPartOfSpeech unit == PosAdjective = SynAttribute
  | wmuPartOfSpeech unit `elem` [PosAdverb, PosPreposition] = SynCircumstance
  | wmuPartOfSpeech unit `elem` [PosConjunction, PosParticle, PosInterjection] = SynMarker
  | otherwise = SynUnknown

findRootIndex :: [WordMeaningUnit] -> Int
findRootIndex units =
  case findIndex ((== PosVerb) . wmuPartOfSpeech) units of
    Just idx -> idx
    Nothing ->
      case findIndex (\u -> wmuPartOfSpeech u `elem` [PosNoun, PosPronoun]) units of
        Just idx -> idx
        Nothing -> 0
