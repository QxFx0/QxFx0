{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SensePlan
  ( buildResponseSensePlan
  , constrainFamilyBySense
  ) where

import Data.Map.Strict (toList)
import Data.List (sortOn)
import Data.Ord (Down(..))

import QxFx0.Semantic.Sense
import QxFx0.Semantic.Sense.Adjacency
import QxFx0.Types

buildResponseSensePlan :: CanonicalMoveFamily -> SenseVector -> ResponseSensePlan
buildResponseSensePlan family inputVec =
  let inputOp = case svOperators inputVec of
        op:_ -> op
        [] -> OpGround
      familyOp = familyToSenseOperator family
      chosenOp = if allowedTransition inputOp familyOp then familyOp else fallbackContinuation inputOp
      preservedAxes = map fst (take 2 (sortOn (Down . snd) (toList (svAxes inputVec))))
      reason
        | chosenOp == familyOp = "family_aligned_continuation"
        | otherwise = "bounded_adjacent_shift"
      distance = if chosenOp == inputOp then 0 else 1
  in ResponseSensePlan
      { rspInputVector = inputVec
      , rspChosenOperator = chosenOp
      , rspPreservedAxes = preservedAxes
      , rspShiftReason = reason
      , rspDistance = distance
      }

constrainFamilyBySense :: CanonicalMoveFamily -> SenseVector -> CanonicalMoveFamily
constrainFamilyBySense family inputVec =
  let plan = buildResponseSensePlan family inputVec
  in case (family, rspChosenOperator plan) of
       (CMGround, OpDefine) -> CMDefine
       (CMGround, OpExplainCause) -> CMClarify
       (CMDescribe, OpRepair) -> CMRepair
       (CMDescribe, OpNextStep) -> CMNextStep
       (CMDescribe, OpDistinguish) -> CMDistinguish
       (CMGround, OpRepair) -> CMRepair
       (other, _) -> other

familyToSenseOperator :: CanonicalMoveFamily -> SenseOperator
familyToSenseOperator family = case family of
  CMDefine -> OpDefine
  CMGround -> OpGround
  CMClarify -> OpConstrain
  CMRepair -> OpRepair
  CMNextStep -> OpNextStep
  CMDeepen -> OpConstrain
  CMConfront -> OpDistinguish
  CMPurpose -> OpConstrain
  _ -> OpGround

fallbackContinuation :: SenseOperator -> SenseOperator
fallbackContinuation op = case adjacentOperators op of
  next:_ -> next
  [] -> op
