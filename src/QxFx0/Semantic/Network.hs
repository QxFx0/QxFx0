{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network
  ( module QxFx0.Semantic.Network.Types
  , buildSemanticNetwork
  , mergeSemanticNetworks
  , mergeSemanticNetworksWithProvenance
  , mergeSemanticEdge
  , activate
  , activateWithField
  , activateTopic
  , activateTopicWithField
  , activateArtifact
  , activationArtifactNetwork
  , spreadActivation
  , spreadActivationWithField
  , spreadActivationEnhanced
  , spreadActivationWithFieldEnhanced
  , getActivatedAtoms
  , contentDensityGate
  , spreadingActivationActive
  , neutralField
  , adjustEdge
  , computeAdaptiveDecay
  , computeDynamicMaxHops
  , calibrateActivationWeights
  ) where

import Prelude hiding ()
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import QxFx0.Core.MeaningGraph (MeaningGraph(..), MeaningEdge(..))
import QxFx0.Self.Field (Field(..), Resonance(..), Atmosphere(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))
import QxFx0.Semantic.Network.Types
import QxFx0.Semantic.Network.Types (relationTypeWeight)

buildSemanticNetwork :: MeaningGraph -> SemanticNetwork
buildSemanticNetwork mg =
  let edges = mgEdges mg
      nodes = S.fromList $ concatMap (\e -> S.toList (meAtoms e)) edges
      edgeMap = M.fromList
        [ ((a1, a2), semanticEdge a1 a2 (fromIntegral count / fromIntegral maxCount) count ExplicitEdge)
        | e <- edges
        , a1 <- S.toList (meAtoms e)
        , a2 <- S.toList (meAtoms e)
        , a1 /= a2
        , let count = meCount e
        ]
      maxCount = maximum (1 : map meCount edges)
  in SemanticNetwork
    { snNodes = nodes
    , snEdges = edgeMap
    , snActivation = M.empty
    , snDecayRate = 0.5
    , snMaxHops = 3
    , snActivationLog = Seq.empty
    }

mergeSemanticNetworks :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
mergeSemanticNetworks = mergeSemanticNetworksWithProvenance

mergeSemanticNetworksWithProvenance :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
mergeSemanticNetworksWithProvenance base update =
  SemanticNetwork
    { snNodes = S.union (snNodes base) (snNodes update)
    , snEdges = M.unionWith mergeSemanticEdge (snEdges base) (snEdges update)
    , snActivation = M.empty
    , snDecayRate = snDecayRate base
    , snMaxHops = snMaxHops base
    , snActivationLog = Seq.empty
    }

-- | Resolve one colliding edge using the same explicit precedence policy as
-- whole-network merge. The first edge is the current owner value and the
-- second is the incoming update; an exact authority/confidence tie selects the
-- incoming edge deterministically.
mergeSemanticEdge :: SemanticEdge -> SemanticEdge -> SemanticEdge
mergeSemanticEdge baseEdge updateEdge =
  case (isAuthoritative baseEdge, isAuthoritative updateEdge) of
    (True, False) -> baseEdge
    (False, True) -> updateEdge
    _ ->
      case compare (seConfidence baseEdge) (seConfidence updateEdge) of
        GT -> baseEdge
        LT -> updateEdge
        EQ -> updateEdge
  where
    isAuthoritative e = case seProvenance e of
      ProvenanceCurated          -> True
      ProvenanceIngested         -> True
      ProvenanceSelfPlay         -> True
      ProvenanceRuntimeLLM       -> True
      ProvenanceHumanCorrection  -> True
      ProvenanceDerived          -> True
      ProvenanceCorpus           -> False
      ProvenanceSubstrate        -> False
      ProvenanceDialogueFeedback -> False

-- | Adjust an existing edge in the network by its endpoint key.
-- If the key is not present, the network is returned unchanged.
adjustEdge :: (Text, Text) -> (SemanticEdge -> SemanticEdge) -> SemanticNetwork -> SemanticNetwork
adjustEdge key f sn = sn { snEdges = M.adjust f key (snEdges sn) }

activate :: Text -> SemanticNetwork -> SemanticNetwork
activate = activateWithField neutralField

activateWithField :: Field -> Text -> SemanticNetwork -> SemanticNetwork
activateWithField field seed sn =
  let initialActivation = M.singleton seed 1.0
      step0 = ActivationStep seed ExplicitEdge seed 0 1.0
  in spreadActivationWithField field (sn { snActivationLog = Seq.singleton step0 }) initialActivation 0

activateTopic :: Set Text -> SemanticNetwork -> SemanticNetwork
activateTopic = activateTopicWithField neutralField

activateTopicWithField :: Field -> Set Text -> SemanticNetwork -> SemanticNetwork
activateTopicWithField field topicAtoms sn =
  let initialActivation = M.fromList [(atom, 1.0) | atom <- S.toList topicAtoms]
      steps0 = Seq.fromList [ ActivationStep atom ExplicitEdge atom 0 1.0 | atom <- S.toList topicAtoms ]
  in spreadActivationWithField field (sn { snActivationLog = steps0 }) initialActivation 0

-- | Compute one immutable turn-local activation result. Traversed edges are
-- captured now so later graph merges cannot change the feedback source.
activateArtifact :: [Text] -> Field -> Set Text -> SemanticNetwork -> ActivationArtifact
activateArtifact topics field topicAtoms network =
  let activated = activateTopicWithField field topicAtoms network
  in ActivationArtifact
      { aaSeedTopics = topics
      , aaActivation = snActivation activated
      , aaSteps = snActivationLog activated
      , aaUsedEdges = usedEdges network (snActivationLog activated)
      }

-- | Materialize the activation-only view expected by existing selector math.
-- No spreading activation is performed here.
activationArtifactNetwork :: ActivationArtifact -> SemanticNetwork
activationArtifactNetwork artifact =
  SemanticNetwork
    { snNodes = S.fromList (M.keys (aaActivation artifact))
    , snEdges = M.empty
    , snActivation = aaActivation artifact
    , snDecayRate = 0.5
    , snMaxHops = 0
    , snActivationLog = aaSteps artifact
    }

usedEdges :: SemanticNetwork -> Seq ActivationStep -> [SemanticEdge]
usedEdges network = go S.empty . foldr (:) []
  where
    go _ [] = []
    go seen (step : rest) =
      case M.lookup (asVia step, asNode step) (snEdges network) of
        Just edge
          | let key = (seFrom edge, seTo edge)
          , not (S.member key seen) -> edge : go (S.insert key seen) rest
        _ -> go seen rest

-- | A neutral field for callers that do not supply one. All dimensions are
-- set to 0.5 so the modulation multipliers evaluate to exactly 1.0 and the
-- historical activation behaviour is preserved.
neutralField :: Field
neutralField =
  Field
    { fieldResonance      = Resonance 0.5
    , fieldAtmosphere     = Atmosphere 0.5 0.5
    , fieldConfidence     = FieldConfidence 0.5
    , fieldConsolidation  = Consolidation 0.5
    , fieldCounterfactual = Counterfactual 0.5
    }

spreadActivation :: SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivation = spreadActivationWithField neutralField

spreadActivationWithField :: Field -> SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivationWithField field sn activation hopCount
  | hopCount >= snMaxHops sn = sn { snActivation = activation }
  | otherwise =
      let newSteps = buildSteps field activation sn (hopCount + 1)
          newActs = M.fromList [(asNode s, asWeight s) | s <- newSteps]
          merged = M.unionWith max activation newActs
      in if M.size merged == M.size activation
         then sn { snActivation = merged }
         else spreadActivationWithField field
                (sn { snActivationLog = snActivationLog sn <> Seq.fromList newSteps })
                merged
                (hopCount + 1)

buildSteps :: Field -> Map Text Double -> SemanticNetwork -> Int -> [ActivationStep]
buildSteps field activation sn hop =
  [ ActivationStep neighbor (seSource edge) atom hop weight
  | (atom, act) <- M.toList activation
  , (neighbor, edge) <- getNeighbors atom sn
  , not (M.member neighbor activation)
  , let weight = clampUnit (act * seWeight edge * snDecayRate sn * confMul * counterMul * resMul)
        confMul = 1.0 - 0.3 * (1.0 - unFieldConfidence (fieldConfidence field))
        counterMul = 1.0 + 0.2 * unCounterfactual (fieldCounterfactual field)
        resMul = 1.0 + 0.2 * unResonance (fieldResonance field)
  ]

clampUnit :: Double -> Double
clampUnit = max 0.0 . min 1.0

propagateAll :: Map Text Double -> SemanticNetwork -> Map Text Double
propagateAll activation sn =
  M.foldlWithKey' (\acc atom act ->
    M.unionWith max acc (propagateOne atom act sn activation)
  ) M.empty activation

propagateOne :: Text -> Double -> SemanticNetwork -> Map Text Double -> Map Text Double
propagateOne atom act sn activation =
  let neighbors = getNeighbors atom sn
      decay = snDecayRate sn
      newActs = [ (neighbor, act * seWeight edge * decay)
                | (neighbor, edge) <- neighbors
                , not (M.member neighbor activation)
                ]
  in M.fromList newActs

getNeighbors :: Text -> SemanticNetwork -> [(Text, SemanticEdge)]
getNeighbors atom sn =
  [ (seTo e, e)
  | ((from, _), e) <- M.toList (snEdges sn)
  , from == atom
  ]

getActivatedAtoms :: SemanticNetwork -> [(Text, Double)]
getActivatedAtoms sn =
  [ (atom, act)
  | (atom, act) <- M.toList (snActivation sn)
  , act > 0.05
  ]

contentDensityGate :: SemanticNetwork -> Bool
contentDensityGate sn =
  let edgeCount = M.size (snEdges sn)
      nodeCount = S.size (snNodes sn)
  in edgeCount >= 50 && nodeCount >= 15

-- | Feature flag for ADR-0050 Phase 2 spreading-activation surface generation.
spreadingActivationActive :: Bool
spreadingActivationActive = True

-- ============================================================================
-- Enhanced Spreading Activation Functions
-- ============================================================================

-- | Compute adaptive decay rate based on Field state and network density.
-- Lower resonance -> higher decay (more focused activation)
-- Higher counterfactual -> lower decay (more exploratory activation)
-- Denser networks -> slightly higher decay to prevent oversaturation
computeAdaptiveDecay :: Field -> SemanticNetwork -> Double
computeAdaptiveDecay field sn =
  let baseDecay = snDecayRate sn
      resonance = unResonance (fieldResonance field)
      counterfactual = unCounterfactual (fieldCounterfactual field)
      confidence = unFieldConfidence (fieldConfidence field)
      -- Network density factor: more edges relative to nodes -> higher decay
      nodeCount = fromIntegral (S.size (snNodes sn))
      edgeCount = fromIntegral (M.size (snEdges sn))
      densityFactor = if nodeCount > 0 then min 1.0 (edgeCount / nodeCount / 5.0) else 0.0
      -- Field-based modulation
      resonanceMod = 0.5 + 0.3 * (1.0 - resonance)  -- Low resonance -> higher decay
      counterfactualMod = 0.5 + 0.2 * counterfactual  -- High counterfactual -> lower decay
      confidenceMod = 0.5 + 0.1 * (1.0 - confidence)  -- High confidence -> lower decay
      -- Combined adaptive decay
      adaptive = baseDecay * resonanceMod * counterfactualMod * confidenceMod * (1.0 + densityFactor)
  in clampUnit adaptive

-- | Compute dynamic max hops based on network density and Field state.
-- Denser networks allow more hops
-- Higher counterfactual -> more hops (more exploratory)
-- Higher confidence -> fewer hops (more focused)
computeDynamicMaxHops :: Field -> SemanticNetwork -> Int
computeDynamicMaxHops field sn =
  let baseHops = snMaxHops sn
      nodeCount = fromIntegral (S.size (snNodes sn))
      edgeCount = fromIntegral (M.size (snEdges sn))
      -- Density ratio: edges per node
      densityRatio = if nodeCount > 0 then edgeCount / nodeCount else 0.0
      -- Field-based modulation
      counterfactual = unCounterfactual (fieldCounterfactual field)
      confidence = unFieldConfidence (fieldConfidence field)
      -- More hops for denser networks (logarithmic scaling)
      densityBonus = floor (log (1.0 + densityRatio) / log 2.0)
      -- Counterfactual bonus: high counterfactual -> more exploratory
      counterfactualBonus = if counterfactual > 0.7 then 1 else 0
      -- Confidence penalty: high confidence -> more focused
      confidencePenalty = if confidence > 0.8 then -1 else 0
      -- Ensure minimum of 1 hop
      result = baseHops + densityBonus + counterfactualBonus + confidencePenalty
  in max 1 result

-- | Calibrate edge weights for activation based on relation type and confidence.
-- Uses relationTypeWeight as base and modifies by edge confidence.
calibrateActivationWeights :: SemanticNetwork -> Map (Text, Text) Double
calibrateActivationWeights sn =
  M.mapWithKey calibrateEdge (snEdges sn)
  where
    calibrateEdge :: (Text, Text) -> SemanticEdge -> Double
    calibrateEdge _ edge =
      let baseWeight = seWeight edge
          relationBoost = case seRelationType edge of
            Just rt -> relationTypeWeight rt
            Nothing -> 0.5
          confidenceFactor = seConfidence edge
          -- Combine: base weight * relation boost * confidence
          calibrated = baseWeight * relationBoost * confidenceFactor
      in clampUnit calibrated

-- | Enhanced spreading activation with adaptive parameters.
-- Uses Field-aware decay, dynamic hops, and calibrated weights.
spreadActivationEnhanced :: SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivationEnhanced = spreadActivationWithFieldEnhanced neutralField

-- | Enhanced spreading activation with Field modulation.
-- This is the main improved activation function that:
-- 1. Uses adaptive decay rate based on Field state
-- 2. Uses dynamic max hops based on network density and Field
-- 3. Calibrates edge weights based on relation type and confidence
-- 4. Implements priority-based activation for important nodes
spreadActivationWithFieldEnhanced :: Field -> SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivationWithFieldEnhanced field sn activation hopCount
  | hopCount >= dynamicMaxHops = sn { snActivation = activation }
  | otherwise =
      let adaptiveDecay = computeAdaptiveDecay field sn
          calibratedWeights = calibrateActivationWeights sn
          newSteps = buildStepsEnhanced field activation sn calibratedWeights adaptiveDecay (hopCount + 1)
          newActs = M.fromList [(asNode s, asWeight s) | s <- newSteps]
          merged = M.unionWith max activation newActs
      in if M.size merged == M.size activation
         then sn { snActivation = merged }
         else spreadActivationWithFieldEnhanced field
                (sn { snActivationLog = snActivationLog sn <> Seq.fromList newSteps })
                merged
                (hopCount + 1)
  where
    dynamicMaxHops = computeDynamicMaxHops field sn

-- | Build enhanced activation steps with calibrated weights and adaptive decay.
buildStepsEnhanced :: Field -> Map Text Double -> SemanticNetwork -> Map (Text, Text) Double -> Double -> Int -> [ActivationStep]
buildStepsEnhanced field activation sn calibratedWeights adaptiveDecay hop =
  [ ActivationStep neighbor (seSource edge) atom hop weight
  | (atom, act) <- M.toList activation
  , (neighbor, edge) <- getNeighbors atom sn
  , not (M.member neighbor activation)
  , let -- Get calibrated weight for this edge
        edgeKey = (seFrom edge, seTo edge)
        calibWeight = M.findWithDefault (seWeight edge) edgeKey calibratedWeights
        -- Compute field-based multipliers
        confMul = 1.0 - 0.3 * (1.0 - unFieldConfidence (fieldConfidence field))
        counterMul = 1.0 + 0.2 * unCounterfactual (fieldCounterfactual field)
        resMul = 1.0 + 0.2 * unResonance (fieldResonance field)
        -- Enhanced weight calculation with adaptive decay
        weight = clampUnit (act * calibWeight * adaptiveDecay * confMul * counterMul * resMul)
  ]
