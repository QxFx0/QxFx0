{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Sense.Adjacency
  ( adjacentOperators
  , allowedTransition
  ) where

import QxFx0.Semantic.Sense

adjacentOperators :: SenseOperator -> [SenseOperator]
adjacentOperators op = case op of
  OpDefine -> [OpDistinguish, OpGround, OpClarify]
  OpGround -> [OpDefine, OpExplainCause, OpClarify]
  OpDistinguish -> [OpExplainCause, OpConstrain, OpClarify]
  OpExplainCause -> [OpConstrain, OpExplainPurpose, OpGround]
  OpExplainPurpose -> [OpConstrain, OpNextStep]
  OpReflect -> [OpClarify, OpConstrain]
  OpConstrain -> [OpClarify, OpNextStep, OpGround]
  OpRepair -> [OpClarify, OpGround]
  OpClarify -> [OpGround, OpDefine, OpDeepen]
  OpDeepen -> [OpReflect, OpNextStep]
  OpNextStep -> [OpGround]

allowedTransition :: SenseOperator -> SenseOperator -> Bool
allowedTransition from to = to == from || to `elem` adjacentOperators from
