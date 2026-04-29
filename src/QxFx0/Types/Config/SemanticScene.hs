{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Config.SemanticScene
  ( semanticSceneRangeWidthFloor
  , semanticSceneTagBonusPerMatch
  , semanticSceneHysteresisBonus
  , semanticDefaultScene
  , semanticDefaultScenes
  ) where

import QxFx0.Types.Domain (AtomTag(..), SemanticScene(..))

semanticSceneRangeWidthFloor :: Double
semanticSceneRangeWidthFloor = 0.001

semanticSceneTagBonusPerMatch :: Double
semanticSceneTagBonusPerMatch = 0.5

semanticSceneHysteresisBonus :: Double
semanticSceneHysteresisBonus = 0.1

semanticDefaultScene :: SemanticScene
semanticDefaultScene = SemanticScene 0.0 1.0 [] "нейтральное состояние"

semanticDefaultScenes :: [SemanticScene]
semanticDefaultScenes =
  [ SemanticScene 0.7 1.0 [NeedContact "восстановление"] "истощение"
  , SemanticScene 0.3 0.7 [Searching "определение"] "поиск"
  , SemanticScene 0.0 0.3 [] "покой"
  ]
