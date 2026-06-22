{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SensePlan
  ( buildResponseSensePlan
  , constrainFamilyBySense
  , buildMicroPlan
  , familySenseBundle
  ) where

import Data.Map.Strict (toList)
import Data.List (sortOn)
import Data.Ord (Down(..))

import QxFx0.Semantic.Sense
import QxFx0.Semantic.Sense.Adjacency
import QxFx0.Types.Sense
  ( SenseOperator(..)
  , SenseVector(..)
  , ResponseSensePlan(..)
  , MicroPlan(..)
  , RhetoricalMove(..)
  , FallbackPolicy(..)
  , rhetoricalMoveFromOperator
  , fallbackPolicyFromPhase
  )
import QxFx0.Types.State.DialogueDevelopment
import QxFx0.Types

buildResponseSensePlan :: CanonicalMoveFamily -> DialogueCommitmentLedger -> DialoguePhase -> SenseVector -> ResponseSensePlan
buildResponseSensePlan family ledger phase inputVec =
  let inputOp = case svOperators inputVec of
        op:_ -> op
        [] -> OpGround
      familyOp = familyToSenseOperator family
      chosenOp0 = if allowedTransition inputOp familyOp then familyOp else fallbackContinuation inputOp
      chosenOp = legalizeOperator phase ledger chosenOp0
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

familySenseBundle :: CanonicalMoveFamily -> DialogueCommitmentLedger -> DialoguePhase -> DialogueThread -> SenseVector -> Double -> (CanonicalMoveFamily, ResponseSensePlan, MicroPlan)
familySenseBundle family ledger phase thread inputVec doubt =
  let constrainedFamily = constrainFamilyBySense family ledger phase inputVec
      sensePlan = buildResponseSensePlan constrainedFamily ledger phase inputVec
      microPlan = buildMicroPlan thread ledger phase sensePlan doubt
  in (constrainedFamily, sensePlan, microPlan)

constrainFamilyBySense :: CanonicalMoveFamily -> DialogueCommitmentLedger -> DialoguePhase -> SenseVector -> CanonicalMoveFamily
constrainFamilyBySense family ledger phase inputVec =
  let plan = buildResponseSensePlan family ledger phase inputVec
  in case (family, rspChosenOperator plan) of
       (CMGround, OpDefine) -> CMDefine
       (CMGround, OpExplainCause) -> CMClarify
       (CMDescribe, OpRepair) -> CMRepair
       (CMDescribe, OpNextStep) -> CMNextStep
       (CMDescribe, OpDistinguish) -> CMDistinguish
       (CMGround, OpRepair) -> CMRepair
       (CMDeepen, OpDeepen) -> CMDeepen
       (CMPurpose, OpExplainPurpose) -> CMPurpose
       (CMConfront, OpDistinguish) -> CMConfront
       (other, _) -> other

buildMicroPlan :: DialogueThread -> DialogueCommitmentLedger -> DialoguePhase -> ResponseSensePlan -> Double -> MicroPlan
buildMicroPlan thread ledger phase sensePlan doubt =
  let operator = rspChosenOperator sensePlan
      phaseBudget = case phase of
        Repairing -> 1
        Clarifying -> 1
        Grounding -> 1
        Exploring -> 2
        Advancing -> 2
        Contesting -> 1
        Closing -> 1
      -- WP-D R-D2: explicitness modulation based on doubt
      -- Base explicitness from dialogue state
      baseExplicitness = 0.35 + fromIntegral (length (dtAcceptedTerms thread)) * 0.02 + if commitmentAllowsAdvance ledger then 0.15 else (-0.10)
      -- High doubt (≥0.75) reduces explicitness by up to 0.20
      -- Rationale: uncertainty → simpler, more tentative language
      doubtPenalty = if doubt >= 0.75 then 0.20 * (doubt - 0.75) / 0.25 else 0.0
      explicitness = clamp01 (baseExplicitness - doubtPenalty)
      moves = case operator of
        OpRepair -> [MvRepair]
        OpClarify -> [MvClarify]
        OpGround -> [MvGround]
        OpDefine -> [MvDefine]
        OpExplainCause -> [MvExplainCause]
        OpDistinguish -> [MvDistinguish]
        OpDeepen -> [MvDeepen]
        OpReflect -> [MvReflect]
        OpExplainPurpose -> [MvExplainPurpose]
        OpNextStep -> [MvNextStep]
        OpConstrain -> [MvConstrain]
      fallbackPolicy = fallbackPolicyFromPhase phase
  in MicroPlan
      { mpRhetoricalMoves = take 2 moves
      , mpExplicitness = explicitness
      , mpStructureBudget = phaseBudget
      , mpFallbackPolicy = fallbackPolicy
      }

commitmentAllowsAdvance :: DialogueCommitmentLedger -> Bool
commitmentAllowsAdvance (DialogueCommitmentLedger items) =
  not (any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) items)

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0

familyToSenseOperator :: CanonicalMoveFamily -> SenseOperator
familyToSenseOperator family = case family of
  CMDefine -> OpDefine
  CMGround -> OpGround
  CMClarify -> OpClarify
  CMRepair -> OpRepair
  CMNextStep -> OpNextStep
  CMDeepen -> OpDeepen
  CMConfront -> OpDistinguish
  CMPurpose -> OpExplainPurpose
  CMDistinguish -> OpDistinguish
  CMReflect -> OpReflect
  CMDescribe -> OpGround
  CMAnchor -> OpGround
  CMContact -> OpGround
  CMHypothesis -> OpReflect

fallbackContinuation :: SenseOperator -> SenseOperator
fallbackContinuation op = case adjacentOperators op of
  next:_ -> next
  [] -> op

legalizeOperator :: DialoguePhase -> DialogueCommitmentLedger -> SenseOperator -> SenseOperator
legalizeOperator phase ledger op
  | not (commitmentAllowsOperator ledger op) = OpClarify
  | not (phaseAllows phase op) = phaseFallback phase
  | otherwise = op

commitmentAllowsOperator :: DialogueCommitmentLedger -> SenseOperator -> Bool
commitmentAllowsOperator (DialogueCommitmentLedger items) op =
  case op of
    OpNextStep -> clear
    OpDeepen -> clear
    OpExplainPurpose -> clear
    _ -> True
  where
    clear = not (any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) items)

phaseAllows :: DialoguePhase -> SenseOperator -> Bool
phaseAllows phase op = op `elem` case phase of
  Exploring -> [OpGround, OpDefine, OpDistinguish, OpClarify, OpReflect]
  Clarifying -> [OpClarify, OpGround, OpDefine, OpDistinguish, OpRepair]
  Grounding -> [OpGround, OpDefine, OpExplainCause, OpClarify]
  Repairing -> [OpRepair, OpClarify, OpGround]
  Advancing -> [OpNextStep, OpExplainPurpose, OpDeepen, OpGround]
  Contesting -> [OpDistinguish, OpConstrain, OpClarify, OpGround]
  Closing -> [OpGround, OpReflect, OpNextStep]

phaseFallback :: DialoguePhase -> SenseOperator
phaseFallback phase = case phase of
  Repairing -> OpRepair
  Clarifying -> OpClarify
  Grounding -> OpGround
  Contesting -> OpConstrain
  Closing -> OpReflect
  Exploring -> OpGround
  Advancing -> OpGround
