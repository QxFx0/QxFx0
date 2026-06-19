{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Stance defense and revision logic for Anomaly v3.0.

This module implements the graded stance defense mechanism that replaces
the simple 3-threshold revisePosition from Layer 1.

== Architecture

The stance defense follows a pentagon trajectory:

@
StanceHeld → StanceDoubted → StanceRevised → AdversaryClassified → Collapse
@

Each transition is triggered by user challenges with sufficient evidence
weight. The system can recover from Doubted back to Held (capped at 0.9).

== Key Functions

* 'evidenceWeight' — computes the weight of user's challenge
* 'defendOrAdapt' — main defense function implementing the pentagon
* 'reviseStance' — performs graded revision of the stance
* 'recoverStance' — recovers confidence when no attacks occur
-}
module QxFx0.Semantic.Stance
  ( -- * Main defense
    defendOrAdapt
  , reviseStance
  , recoverStance
    -- * Evidence weight
  , evidenceWeight
    -- * Collapse
  , Collapse(..)
  , collapseReason
    -- * Selection
  , selectNearestSatisfying
  , selectFarthestPoint
    -- * User stance extraction
  , extractUserStance
    -- * Helpers
  , stanceSimilarity
  , collapseThreshold
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.List (sortBy)
import Data.Ord (comparing, Down(..))

import QxFx0.Types.State.Stance
import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))
import QxFx0.Semantic.Space.Types (SemanticSpace(..))
import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..))
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Self.Field (Field(..))
import QxFx0.Semantic.Intent.Features (SemanticFeatures(..))

-- | Collapse reason when defense fails.
data Collapse
  = CollapseConatusExhausted
    -- ^ Conatus energy fell below threshold while stance was Doubted
  | CollapseAdversaryClassified
    -- ^ User classified as static (not changing position)
  | CollapseEssenceRupture
    -- ^ Essence integrity compromised
  deriving stock (Eq, Show)

-- | Human-readable collapse reason.
collapseReason :: Collapse -> Text
collapseReason CollapseConatusExhausted = "conatus energy exhausted while defending"
collapseReason CollapseAdversaryClassified = "adversary classified as static"
collapseReason CollapseEssenceRupture = "essence integrity compromised"

-- | Compute the weight of user's challenge.
--
-- Evidence weight follows the v3.0 specification formula:
-- weight = 1.0 - (argumentStrength * 0.3)
--
-- Where argumentStrength = novelty × relevance:
-- * novelty — fraction of atoms not seen before in sdEvidenceSeen
-- * relevance — semantic relevance based on challenge size and context overlap
--
-- Returns a value in [0.7, 1.0] where lower means stronger challenge.
evidenceWeight
  :: StanceDefense
  -> Set.Set Text
  -- ^ Atoms from user's challenge
  -> Double
evidenceWeight sd challengeAtoms =
  let evidenceSeen = sdEvidenceSeen sd
      novelAtoms = Set.difference challengeAtoms evidenceSeen
      novelCount = Set.size novelAtoms
      totalCount = Set.size challengeAtoms
      
      novelty = if totalCount == 0 then 0 else fromIntegral novelCount / fromIntegral totalCount
      
      overlapCount = Set.size (Set.intersection challengeAtoms evidenceSeen)
      sizeRelevance = min 1.0 (fromIntegral totalCount / 5.0)
      contextRelevance = if totalCount == 0 then 0 else fromIntegral overlapCount / fromIntegral totalCount
      relevance = 0.7 * sizeRelevance + 0.3 * contextRelevance
      
      argumentStrength = novelty * relevance
  in 1.0 - min 1.0 (max 0.0 argumentStrength) * 0.3

-- | Compute Jaccard similarity between two sets of atoms.
--
-- Used to measure how similar user's stance is to system's stance.
stanceSimilarity :: Set.Set Text -> Set.Set Text -> Double
stanceSimilarity a b =
  let intersection = Set.size (Set.intersection a b)
      union = Set.size (Set.union a b)
  in if union == 0 then 0 else fromIntegral intersection / fromIntegral union

-- | Compute collapse threshold based on confidence.
--
-- Range: [2, 6]. Higher confidence = higher threshold (harder to collapse).
-- Formula: 2 + floor(confidence * 4)
collapseThreshold :: Double -> Int
collapseThreshold confidence =
  let clamped = min 1.0 (max 0.0 confidence)
  in 2 + floor (clamped * 4.0)

-- | Main defense function implementing the pentagon.
--
-- Returns either a Collapse (defense failed) or updated StanceDefense.
--
-- Pentagon transitions:
-- * StanceHeld + weak challenge → StanceHeld (defend)
-- * StanceHeld + strong challenge → StanceDoubted
-- * StanceDoubted + weak challenge → StanceDoubted (defend)
-- * StanceDoubted + strong challenge → StanceRevised
-- * StanceDoubted + low conatus → Collapse
-- * StanceRevised → AdversaryClassified (if user not changing)
-- * AdversaryClassified → Collapse (if continue attacking)
defendOrAdapt
  :: StanceDefense
  -> ConatusEnergy
  -> Set.Set Text
  -- ^ Atoms from user's challenge
  -> Either Collapse StanceDefense
defendOrAdapt sd conatus challengeAtoms =
  let weight = evidenceWeight sd challengeAtoms
      stance = sdStance sd
      confidence = stanceConfidence stance
      threshold = collapseThreshold confidence
      conatusScalar = ceScalar conatus
      conatusFloor = cpConatusFloor (sdCollapsePolicy sd)
  in case stance of
    StanceHeld conf ->
      if weight < 0.88
        then -- Strong challenge: transition to Doubted
          Right $ sd
            { sdStance = StanceDoubted (conf * 0.8)
            , sdAttackCount = sdAttackCount sd + 1
            , sdRecoveryCounter = 0
            , sdEvidenceSeen = Set.union (sdEvidenceSeen sd) challengeAtoms
            }
        else -- Weak challenge: defend
          Right $ sd
            { sdAttackCount = sdAttackCount sd + 1
            , sdRecoveryCounter = 0
            , sdEvidenceSeen = Set.union (sdEvidenceSeen sd) challengeAtoms
            }

    StanceDoubted conf ->
      if conatusScalar < conatusFloor
        then -- Low conatus: collapse
          Left CollapseConatusExhausted
       else if weight < 0.88
          then -- Strong challenge: revise
            Right $ sd
              { sdStance = StanceRevised "revised position"
              , sdAttackCount = sdAttackCount sd + 1
              , sdRecoveryCounter = 0
              , sdEvidenceSeen = Set.union (sdEvidenceSeen sd) challengeAtoms
              }
          else -- Weak challenge: defend
            Right $ sd
              { sdAttackCount = sdAttackCount sd + 1
              , sdRecoveryCounter = 0
              , sdEvidenceSeen = Set.union (sdEvidenceSeen sd) challengeAtoms
              }

    StanceRevised _ ->
      -- After revision, check if user is classified as static
      if sdAdversary sd == AdversaryClassified
        then Left CollapseAdversaryClassified
        else Right $ sd
          { sdAttackCount = sdAttackCount sd + 1
          , sdRecoveryCounter = 0
          }

-- | Perform graded revision of the stance.
--
-- Revision follows a graded trajectory based on confidence:
-- * confidence > 0.7 → StanceDoubted (high confidence, but challenged)
-- * confidence ≤ 0.7 → StanceRevised (low confidence, needs revision)
--
-- Records the transition in lineage.
reviseStance
  :: StanceDefense
  -> Text
  -- ^ New position text
  -> TurnSeq
  -> StanceDefense
reviseStance sd newText turnSeq =
  let oldStance = sdStance sd
      oldConfidence = stanceConfidence oldStance
      -- Graded revision based on confidence
      newStance = if oldConfidence > 0.7
        then -- High confidence: doubt the position
          StanceDoubted (oldConfidence * 0.8)
        else -- Low confidence: revise to new position
          StanceRevised newText
      transition = StanceTransition
        { stFrom = oldStance
        , stTo = newStance
        , stTrigger = "graded revision"
        , stTurn = turnSeq
        }
  in sd { sdStance = newStance }

-- | Recover confidence when no attacks occur.
--
-- Recovery is capped at 0.9 to prevent overconfidence.
-- Returns updated StanceDefense with recovered confidence.
recoverStance
  :: StanceDefense
  -> StanceDefense
recoverStance sd =
  let stance = sdStance sd
      policy = sdRecoveryPolicy sd
      counter = sdRecoveryCounter sd
      turnsNeeded = rwTurnsSinceLastChallenge policy
      rate = rwRecoveryRate policy
  in case stance of
    StanceDoubted conf ->
      if counter >= turnsNeeded
        then
          let newConf = min 0.9 (conf + rate * conf)
          in sd { sdStance = StanceHeld newConf }
        else sd
    _ -> sd

-- | Select predicate nearest to current stance (for defense).
--
-- Finds the predicate with highest similarity to current position atoms.
-- Constrained to same concept category to maintain semantic coherence.
selectNearestSatisfying
  :: ContentSelector
  -> Field
  -> Text
  -- ^ Topic
  -> Set.Set Text
  -- ^ Current stance atoms
  -> Maybe SemanticPredicate
selectNearestSatisfying cs field topic currentAtoms =
  case Map.lookup topic (csTopicPredicates cs) of
    Nothing -> Nothing
    Just preds ->
      let scored = map (\p ->
            let predAtoms = tokenizePredicate (csLemmaMap cs) (spRu p)
                sim = stanceSimilarity currentAtoms predAtoms
            in (p, sim)
            ) preds
          sorted = sortBy (comparing (Down . snd)) scored
      in case sorted of
           ((p, _):_) -> Just p
           [] -> Nothing
  where
    tokenizePredicate lemmaMap text =
      let words' = T.words text
          normalized = map (T.toLower . T.filter (\c -> c /= '.' && c /= ',' && c /= '?' && c /= '!')) words'
          lemmatized = map (\w -> Map.findWithDefault w w lemmaMap) normalized
      in Set.fromList lemmatized

-- | Select predicate farthest from current stance (for revision).
--
-- Finds the predicate with lowest similarity to current position atoms.
-- Constrained to same concept category to maintain semantic coherence.
-- Used when revising stance to a new position.
selectFarthestPoint
  :: ContentSelector
  -> Field
  -> Text
  -- ^ Topic
  -> Set.Set Text
  -- ^ Current stance atoms
  -> Maybe SemanticPredicate
selectFarthestPoint cs field topic currentAtoms =
  case Map.lookup topic (csTopicPredicates cs) of
    Nothing -> Nothing
    Just preds ->
      let scored = map (\p ->
            let predAtoms = tokenizePredicate (csLemmaMap cs) (spRu p)
                sim = stanceSimilarity currentAtoms predAtoms
            in (p, sim)
            ) preds
          sorted = sortBy (comparing snd) scored
      in case sorted of
           ((p, _):_) -> Just p
           [] -> Nothing
  where
    tokenizePredicate lemmaMap text =
      let words' = T.words text
          normalized = map (T.toLower . T.filter (\c -> c /= '.' && c /= ',' && c /= '?' && c /= '!')) words'
          lemmatized = map (\w -> Map.findWithDefault w w lemmaMap) normalized
      in Set.fromList lemmatized

-- | Extract user's stance from SemanticFeatures.
--
-- Uses sfHasChallengeMark and sfHasContradiction to detect if user is
-- challenging the system's position. Returns atoms representing user's
-- committed claims.
extractUserStance
  :: SemanticFeatures
  -> Set.Set Text
  -- ^ Atoms from user's utterance
  -> TurnSeq
  -> UserStance
extractUserStance features userAtoms turnSeq =
  let isChallenge = sfHasChallengeMark features || sfHasContradiction features
      confidence = if isChallenge then 0.8 else 0.5
  in UserStance
    { usCommittedClaims = userAtoms
    , usConfidence = confidence
    , usTurn = turnSeq
    }
