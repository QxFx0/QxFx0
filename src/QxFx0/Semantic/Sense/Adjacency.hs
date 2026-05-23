{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Sense.Adjacency
  ( adjacentOperators
  , allowedTransition
  ) where

import QxFx0.Semantic.Sense

adjacentOperators :: SenseOperator -> [SenseOperator]
adjacentOperators op = case op of
  OpDefine -> [OpDistinguish, OpGround]
  OpGround -> [OpDefine, OpExplainCause]
  OpDistinguish -> [OpExplainCause, OpConstrain]
  OpExplainCause -> [OpConstrain, OpGround]
  OpConstrain -> [OpNextStep, OpGround]
  OpRepair -> [OpGround, OpNextStep]
  OpNextStep -> [OpGround]

allowedTransition :: SenseOperator -> SenseOperator -> Bool
allowedTransition from to = to == from || to `elem` adjacentOperators from
