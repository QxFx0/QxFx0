{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Parsing operational template descriptors into normalized content moves. -}
module QxFx0.Core.TurnPlanning.Templates
  ( templateToMoves
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types (ContentMove(..))

templateToMoves :: Text -> [ContentMove]
templateToMoves structure =
  M.findWithDefault [MoveGroundKnown] (normalizeTemplateKey structure) templateMoveMap

normalizeTemplateKey :: Text -> Text
normalizeTemplateKey = T.toLower . T.replace " " "_"

templateMoveMap :: Map Text [ContentMove]
templateMoveMap =
  M.fromList
    [ ("ground_known", [MoveGroundKnown, MoveGroundBasis])
    , ("ground_basis", [MoveGroundBasis, MoveShiftFromLabel])
    , ("shift_from_label", [MoveShiftFromLabel, MoveGroundBasis])
    , ("define_frame", [MoveDefineFrame, MoveStateDefinition])
    , ("state_definition", [MoveStateDefinition, MoveShowContrast])
    , ("show_contrast", [MoveShowContrast, MoveStateBoundary])
    , ("state_boundary", [MoveStateBoundary, MoveShowContrast])
    , ("reflect_mirror", [MoveReflectMirror, MoveReflectResonate])
    , ("reflect_resonate", [MoveReflectResonate, MoveDeepenProbe])
    , ("describe_sketch", [MoveDescribeSketch, MoveDescribeSketch])
    , ("purpose_teleology", [MovePurposeTeleology, MovePurposeTeleology])
    , ("hypothesize_test", [MoveHypothesizeTest, MoveHypothesizeTest])
    , ("affirm_presence", [MoveAffirmPresence, MoveContactReach])
    , ("acknowledge_rupture", [MoveAcknowledgeRupture, MoveRepairBridge])
    , ("repair_bridge", [MoveRepairBridge, MoveContactBridge])
    , ("contact_bridge", [MoveContactBridge, MoveContactReach])
    , ("contact_reach", [MoveContactReach, MoveAffirmPresence])
    , ("anchor_stabilize", [MoveAnchorStabilize, MoveGroundKnown])
    , ("clarify_disambiguate", [MoveClarifyDisambiguate, MoveStateDefinition])
    , ("deepen_probe", [MoveDeepenProbe, MoveHypothesizeTest])
    , ("confront_challenge", [MoveConfrontChallenge, MoveShowContrast])
    , ("next_step", [MoveNextStep, MoveNextStep])
    , ("opening_ground", [MoveGroundKnown])
    , ("opening_define", [MoveDefineFrame])
    , ("opening_distinction", [MoveShowContrast])
    , ("opening_reflect", [MoveReflectMirror])
    , ("opening_describe", [MoveDescribeSketch])
    , ("opening_purpose", [MovePurposeTeleology])
    , ("opening_hypothesis", [MoveHypothesizeTest])
    , ("opening_repair", [MoveRepairBridge])
    , ("opening_contact", [MoveContactBridge])
    , ("opening_anchor", [MoveAnchorStabilize])
    , ("opening_clarify", [MoveClarifyDisambiguate])
    , ("opening_deepen", [MoveDeepenProbe])
    , ("opening_confront", [MoveConfrontChallenge])
    , ("opening_next", [MoveNextStep])
    , ("core_ground", [MoveGroundBasis])
    , ("core_define", [MoveStateDefinition])
    , ("core_distinction", [MoveStateBoundary])
    , ("core_reflect", [MoveReflectResonate])
    , ("core_describe", [MoveDescribeSketch])
    , ("core_purpose", [MovePurposeTeleology])
    , ("core_hypothesis", [MoveHypothesizeTest])
    , ("core_repair", [MoveAcknowledgeRupture])
    , ("core_contact", [MoveContactReach])
    , ("core_anchor", [MoveAnchorStabilize])
    , ("core_clarify", [MoveClarifyDisambiguate])
    , ("core_deepen", [MoveDeepenProbe])
    , ("core_confront", [MoveConfrontChallenge])
    , ("core_next", [MoveNextStep])
    ]
