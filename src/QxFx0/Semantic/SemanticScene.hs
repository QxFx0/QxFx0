{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.SemanticScene
  ( inferActiveScene
  , defaultScenes
  ) where

import QxFx0.Types (SemanticScene(..), AtomTrace(..), AtomTag(..))
import QxFx0.Types.Config.SemanticScene
  ( semanticDefaultScene
  , semanticDefaultScenes
  , semanticSceneHysteresisBonus
  , semanticSceneRangeWidthFloor
  , semanticSceneTagBonusPerMatch
  )
import Data.List (maximumBy)
import Data.Ord (comparing)

inferActiveScene :: AtomTrace -> [AtomTag] -> SemanticScene -> [SemanticScene] -> SemanticScene
inferActiveScene trace currentTags currentScene scenes =
  let load = atCurrentLoad trace
      scored = map (scoreScene load currentTags currentScene) scenes
      candidates = filter (\(s, _) -> load >= sceLoadMin s && load <= sceLoadMax s) scored
  in case candidates of
       (_:_) -> fst $ maximumBy (comparing snd) candidates
       [] -> case scenes of
               (s:_) -> s
               []    -> defaultScene

scoreScene :: Double -> [AtomTag] -> SemanticScene -> SemanticScene -> (SemanticScene, Double)
scoreScene load tags currentScene scene =
  let rangeCenter = (sceLoadMin scene + sceLoadMax scene) / 2
      rangeWidth = max semanticSceneRangeWidthFloor (sceLoadMax scene - sceLoadMin scene)
      proximity = 1.0 - (abs (load - rangeCenter) / rangeWidth)
      tagMatchCount = length $ filter (`elem` sceTags scene) tags
      tagBonus = fromIntegral tagMatchCount * semanticSceneTagBonusPerMatch
      hysteresisBonus =
        if sceDescription scene == sceDescription currentScene
          then semanticSceneHysteresisBonus
          else 0.0
      totalScore = proximity + tagBonus + hysteresisBonus
  in (scene, totalScore)

defaultScene :: SemanticScene
defaultScene = semanticDefaultScene

defaultScenes :: [SemanticScene]
defaultScenes = semanticDefaultScenes
