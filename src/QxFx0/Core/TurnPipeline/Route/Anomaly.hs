{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.TurnPipeline.Route.Anomaly
  ( -- * Main detection
    detectAnomaly
    -- * Specific detectors
  , detectSelfReferentialCollapse
  , detectAntiConatusChoice
  , detectUnclassifiableInput
  , detectTemporalAnomaly
    -- * Helpers
  , extractAtomsFromInput
  , selfReferentialCollapse
  , antiConatusMove
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Foldable (toList)

import QxFx0.Types.Anomaly
import QxFx0.Types.State.Stance
import QxFx0.Types.State.System
import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))
import QxFx0.Core.TurnPipeline.Types (TurnInput(..))
import QxFx0.Types.Decision.Model (InputPropositionFrame(..))
import QxFx0.Types.Domain.Atoms (AtomSet(..), MeaningAtom(..))
import QxFx0.Types.Domain (CanonicalMoveFamily)
import QxFx0.Semantic.Space.Types (SemanticSpace(..))
import QxFx0.Self.Essence (Essence(..), EssenceTrajectory(..), EssenceResetEvent(..), collapseEssence)
import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Types.State.SelfState (SelfState(..))

-- | Detect anomalies in priority order: Collapse > Temporal > Unclassifiable > AntiConatus
-- Returns the first detected anomaly or Nothing if no anomalies found.
detectAnomaly :: SystemState -> TurnInput -> Maybe Anomaly
detectAnomaly ss ti =
  case detectSelfReferentialCollapse ss ti of
    Just anomaly -> Just anomaly
    Nothing ->
      case detectTemporalAnomaly ss ti of
        Just anomaly -> Just anomaly
        Nothing ->
          case detectUnclassifiableInput ss ti of
            Just anomaly -> Just anomaly
            Nothing -> detectAntiConatusChoice ss ti

-- | Check if input triggers self-referential collapse
-- Triggered when: subject ∈ ["я", "ты", "QxFx0", "система"] ∧ angst > 0.9
selfReferentialCollapse :: EssenceTrajectory -> InputPropositionFrame -> Bool
selfReferentialCollapse traj frame =
  let subject = T.toLower (ipfSemanticSubject frame)
      selfRefSubjects = ["я", "ты", "qxfx0", "система", "i", "you", "myself", "yourself"]
      isSelfRef = any (`T.isInfixOf` subject) selfRefSubjects
      highAngst = etAngstLevel traj > 0.9
  in isSelfRef && highAngst

-- | Detect SelfReferentialCollapse anomaly (Anomaly-3)
-- Triggered when system encounters self-referential question at high angst
-- Gate: subject ∈ ["я", "ты", "QxFx0", "система"] ∧ angst > 0.9
detectSelfReferentialCollapse :: SystemState -> TurnInput -> Maybe Anomaly
detectSelfReferentialCollapse ss ti =
  let selfState = ssSelfState ss
      essence = selfEssence selfState
      traj = case essence of
               EssenceUncommitted t -> t
               EssenceCommitted t _ -> t
      frame = tiFrame ti
  in if selfReferentialCollapse traj frame
     then let turnSeq = TurnSeq (ssTurnCount ss)
              (_, resetEvent) = collapseEssence (ssTurnCount ss) traj
          in Just $ mkSelfReferential
                 (erePreviousWitnessCount resetEvent)
                 (ipfRawText frame)
                 turnSeq
                 (extractAtomsFromInput ti)
                 0.95  -- Very high confidence for collapse
     else Nothing

-- | Check if move triggers anti-conatus choice
-- Triggered when: stanceConfidence > 0.7 ∧ ¬stanceConsistent ∧ angst > 0.8 ∧ conatus < 5.0
antiConatusMove :: StanceState -> ConatusEnergy -> EssenceTrajectory -> CanonicalMoveFamily -> Bool
antiConatusMove stance conatus traj _family =
  let conf = stanceConfidence stance
      consistent = stanceConsistent stance
      angst = etAngstLevel traj
      energy = ceScalar conatus
  in conf > 0.7 && not consistent && angst > 0.8 && energy < 5.0

-- | Detect AntiConatusChoice anomaly (Anomaly-2)
-- Triggered when system chooses a move that weakens its position
-- Gate: stanceConfidence > 0.7 ∧ ¬stanceConsistent ∧ angst > 0.8 ∧ conatus < 5.0
detectAntiConatusChoice :: SystemState -> TurnInput -> Maybe Anomaly
detectAntiConatusChoice ss ti =
  let topic = tiBestTopic ti
      mStance = Map.lookup topic (ssStances ss)
      selfState = ssSelfState ss
      essence = selfEssence selfState
      traj = case essence of
               EssenceUncommitted t -> t
               EssenceCommitted t _ -> t
      conatus = tiConatusEnergy ti
      family = tiRecommendedFamily ti
  in case mStance of
       Just stance ->
         if antiConatusMove stance conatus traj family
         then let turnSeq = TurnSeq (ssTurnCount ss)
                  conf = stanceConfidence stance
                  energy = ceScalar conatus
              in Just $ mkAntiConatus
                     conf
                     energy
                     (ipfRawText $ tiFrame ti)
                     turnSeq
                     Nothing  -- No commitment ID in Safe Slice
                     (extractAtomsFromInput ti)
                     0.85  -- High confidence for anti-conatus
         else Nothing
       Nothing -> Nothing

-- | Detect UnclassifiableInput anomaly
-- Triggered when input has very few atoms in semantic space
detectUnclassifiableInput :: SystemState -> TurnInput -> Maybe Anomaly
detectUnclassifiableInput ss ti =
  let inputAtoms = extractAtomsFromInput ti
      space = ssSemanticSpace ss
      -- Count how many input atoms are in the semantic space
      atomIndex = ssAtomIndex space
      knownAtoms = Set.filter (`Map.member` atomIndex) inputAtoms
      knownCount = Set.size knownAtoms
      totalCount = Set.size inputAtoms
      -- If less than 20% of atoms are known, it's unclassifiable
      threshold = 0.2
      ratio = if totalCount == 0 then 0 else fromIntegral knownCount / fromIntegral totalCount
      turnSeq = TurnSeq (ssTurnCount ss)
  in if ratio < threshold && totalCount > 0
     then Just $ mkUnclassifiable
            (ipfRawText $ tiFrame ti)
            (buildSimpleFamilyScores knownCount totalCount)
            turnSeq
            inputAtoms
            (1.0 - ratio)  -- Confidence based on how unknown the input is
     else Nothing
  where
    buildSimpleFamilyScores known total =
      let ratio = if total == 0 then 0 else fromIntegral known / fromIntegral total
      in [ ("CMDefine", ratio)
         , ("CMDistinguish", ratio)
         , ("CMContact", ratio)
         , ("CMReflect", ratio)
         , ("CMConfront", ratio)
         , ("CMRepair", ratio)
         , ("CMClarify", ratio)
         ]

-- | Detect TemporalAnomaly
-- Triggered when current stance contradicts historical stance in lineage
detectTemporalAnomaly :: SystemState -> TurnInput -> Maybe Anomaly
detectTemporalAnomaly ss ti =
  let topic = tiBestTopic ti
      currentStance = Map.lookup topic (ssStances ss)
      lineage = Map.lookup topic (ssStanceLineages ss)
      turnSeq = TurnSeq (ssTurnCount ss)
  in case (currentStance, lineage) of
    (Just current, Just lin) ->
      case findContradictoryHistoricalStance current lin of
        Just historical ->
          Just $ mkTemporal
            current
            historical
            (buildContradictionDescription current historical)
            turnSeq
            Nothing  -- No commitment ID in Safe Slice
            (extractAtomsFromInput ti)
            0.85  -- High confidence for temporal
        Nothing -> Nothing
    _ -> Nothing

-- | Extract atoms from TurnInput
extractAtomsFromInput :: TurnInput -> Set.Set Text
extractAtomsFromInput ti =
  let atomSet = tiAtomSet ti
  in Set.fromList $ map maText (asAtoms atomSet)

-- | Find contradictory historical stance in lineage
findContradictoryHistoricalStance :: StanceState -> StanceLineage -> Maybe StanceState
findContradictoryHistoricalStance current lineage =
  let transitions = toList (slHistory lineage)
      historicalStances = map stFrom transitions
      -- Find first stance that contradicts current
      -- For Safe Slice: simple check - if current is Revised and historical is Held
      contradicting = filter (stanceContradicts current) historicalStances
  in case contradicting of
       (x:_) -> Just x
       [] -> Nothing

-- | Check if two stances contradict each other
-- Simple implementation for Safe Slice
stanceContradicts :: StanceState -> StanceState -> Bool
stanceContradicts (StanceRevised _) (StanceHeld _) = True
stanceContradicts _ _ = False

-- | Build human-readable description of contradiction
buildContradictionDescription :: StanceState -> StanceState -> Text
buildContradictionDescription current historical =
  "Current stance (" <> formatStance current <>
  ") contradicts historical stance (" <> formatStance historical <> ")"

-- | Format stance for display
formatStance :: StanceState -> Text
formatStance (StanceHeld conf) = "Held " <> T.pack (show conf)
formatStance (StanceDoubted conf) = "Doubted " <> T.pack (show conf)
formatStance (StanceRevised text) = "Revised: " <> text
