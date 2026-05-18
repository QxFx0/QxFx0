{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-| Turn pipeline effect protocol and deterministic prepare-stage planning inputs. -}
module QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  , PrepareStatic(..)
  , PrepareEffectRequest(..)
  , PrepareEffectPlan(..)
  , buildPrepareEffectPlan
  ) where

import QxFx0.Types
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence
  , ShadowSnapshotId
  )
import QxFx0.Semantic.Embedding (EmbeddingResult)
import QxFx0.Semantic.MeaningAtoms (collectAtoms, updateTrace, extractObjectFromAtom)
import QxFx0.Semantic.Logic (runSemanticLogic)
import QxFx0.Semantic.Proposition (parseProposition)
import QxFx0.Semantic.SemanticInput (SemanticInput, buildSemanticInputSimple)
import QxFx0.Policy.Contracts (fallbackWord)
import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop, ResponseObservation)
import QxFx0.Types.Intuition (IntuitiveFlash)
import QxFx0.Semantic.DialogAtom (DialogAtoms)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Conatus (ConatusEnergy, computeConatusEnergy)
import QxFx0.Self.Field
  ( Field (..)
  , emptyField
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkResonance
  , deriveFieldConfidence
  )
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Salience (conatusGateFires)

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time.Clock (UTCTime)

data TurnEffectRequest
  = TurnReqEmbedding !Text
  | TurnReqNixGuard !Text !Double !Double
  | TurnReqConsciousness !SemanticInput !Double !Double !ConatusEnergy
  | TurnReqIntuition !Text !Double !Double !Int !ConatusEnergy
  | TurnReqApiHealth
  | TurnReqShadow !CanonicalMoveFamily !IllocutionaryForce ![AtomTag]
  | TurnReqAgdaVerify
  | TurnReqCurrentTime
  | TurnReqRequestId
  | TurnReqReadEnv !Text
  | TurnReqTestMarkOnceFile !Text
  | TurnReqSemanticIntrospectionEnv
  | TurnReqCommitRuntimeState !ConsciousnessLoop !IntuitiveState !ResponseObservation
  | TurnReqSaveState !SystemState !Text !(Maybe TurnProjection)
  | TurnReqRollbackTurnProjections !Text !Int
  | TurnReqCheckpoint !Int
  | TurnReqLinearizeClaimAst !(Maybe FilePath) !Text !ClaimAst
  | TurnReqLinearizeDialogAtoms !(Maybe FilePath) !Text !DialogAtoms
  deriving stock (Show)

data TurnEffectResult
  = TurnResEmbedding !EmbeddingResult
  | TurnResNixGuard !NixGuardStatus
  | TurnResConsciousness !ConsciousnessLoop !(Maybe ConsciousnessNarrative) !(Maybe Text)
  | TurnResIntuition !(Maybe IntuitiveFlash) !Double !IntuitiveState
  | TurnResApiHealth !Bool
  | TurnResShadow !(Maybe (CanonicalMoveFamily, IllocutionaryForce)) !ShadowStatus !ShadowDivergence !ShadowSnapshotId ![Text]
  | TurnResAgdaVerify !AgdaVerificationStatus
  | TurnResCurrentTime !UTCTime
  | TurnResRequestId !Text
  | TurnResReadEnv !(Maybe Text)
  | TurnResTestMarkOnceFile !Bool
  | TurnResSemanticIntrospectionEnv !Bool
  | TurnResCommitRuntimeState
  | TurnResSaveState !(Either PersistenceDiagnostic SystemState)
  | TurnResRollbackTurnProjections !(Either PersistenceDiagnostic ())
  | TurnResCheckpointCompleted
  | TurnResLinearizeClaimAst !(Either Text Text)
  | TurnResLinearizeDialogAtoms !(Either Text Text)

data PrepareStatic = PrepareStatic
  { psInputText :: !Text
  , psAtomSet :: !AtomSet
  , psNewTrace :: !AtomTrace
  , psNextUserState :: !UserState
  , psRecommendedFamily :: !CanonicalMoveFamily
  , psFrame :: !InputPropositionFrame
  , psConceptToCheck :: !Text
  , psBestTopic :: !Text
  , psResonance :: !Double
  , psAtomLoad :: !Double
  , psConatusEnergy :: !ConatusEnergy
    -- ^ Phase 2.5 (M2d): the runtime Conatus energy computed
    --   from the current 'SelfBlanket' and its 'BlanketViolation's.
    --   Stored once per turn so downstream recovery-decision call
    --   sites (e.g. 'buildLocalRecoveryPlan' in
    --   'QxFx0.Core.TurnPipeline.Route.Render') can priority-check
    --   the Conatus gate without recomputing from 'SystemState'.
  , psBlanketViolationCount :: !Int
    -- ^ Phase 6 (M6): the count of 'BlanketViolation's reported
    --   by 'checkInitialBlanket' on the current 'SelfBlanket'.
    --   Stored alongside 'psConatusEnergy' so the recovery-plan
    --   evidence line @"blanket_violations=N"@ at the
    --   render-stage call site can be reconstructed without a
    --   second 'computeSelfBlanket' + 'checkInitialBlanket' pass.
  , psConatusGateFired :: !Bool
    -- ^ Phase 6 addendum (M6.1): single-source-of-truth flag for
    --   the Conatus gate.  Computed once in 'buildPrepareEffectPlan'
    --   by 'conatusGateFires', then read by both the salience
    --   controller and the recovery-decision site in
    --   'buildLocalRecoveryPlan'.  Eliminates the previous
    --   duplicate call to 'conatusGateFires'.
  , psField :: !Field
    -- ^ Per-turn 'QxFx0.Self.Field.Field' snapshot.  All five
    --   components are populated from runtime signals:
    --
    --     * 'fieldResonance'      — atom-trace current load
    --       ('psResonance').
    --     * 'fieldAtmosphere'     — valence = (ego agency −
    --       ego tension) modulated by legitimacy; arousal =
    --       ego tension.
    --     * 'fieldConsolidation'  — sliding-window narrative
    --       success rate, optionally floored by topic stability.
    --     * 'fieldCounterfactual' — normalised entropy of
    --       candidate family weights, boosted by holistic streak.
    --     * 'fieldConfidence'     — derived by
    --       'deriveFieldConfidence' from the four above.
    --
    --   Threaded through 'tiField' so all routing and salience-
    --   decision call sites share one canonical pre-turn Field.
  } deriving stock (Eq, Show)

data PrepareEffectRequest
  = PrepareReqEmbedding !Text
  | PrepareReqNixGuard !Text !Double !Double
  | PrepareReqConsciousness !SemanticInput !Double !Double !ConatusEnergy
  | PrepareReqIntuition !Text !Double !Double !Int !ConatusEnergy
  | PrepareReqApiHealth
  deriving stock (Eq, Show)

data PrepareEffectPlan = PrepareEffectPlan
  { pepStatic :: !PrepareStatic
  , pepEmbeddingRequest :: !PrepareEffectRequest
  , pepNixGuardRequest :: !PrepareEffectRequest
  , pepConsciousnessRequest :: !PrepareEffectRequest
  , pepIntuitionRequest :: !PrepareEffectRequest
  , pepApiHealthRequest :: !PrepareEffectRequest
  } deriving stock (Eq, Show)

buildPrepareEffectPlan :: SystemState -> Text -> PrepareEffectPlan
buildPrepareEffectPlan ss input =
  let atomSet = collectAtoms input (ssClusters ss)
      newTrace = updateTrace (ssTrace ss) (ssTurnCount ss) atomSet
      nextUserState = inferUserState (ssClusters ss) input
      logicResults = runSemanticLogic atomSet
      sortedLogic = L.sortBy (\(_, w1) (_, w2) -> compare w2 w1) logicResults
      recommendedFamily = case sortedLogic of
        ((fam, _):_) -> fam
        [] -> CMGround
      frame = parseProposition input
      atomFocus = case asAtoms atomSet of
        (a:_) -> extractObjectFromAtom a
        [] -> ""
      conceptToCheck =
        firstNonEmpty
          [ ipfFocusNominative frame
          , ipfFocusEntity frame
          , atomFocus
          , fromMaybe fallbackWord (listToMaybe (T.words input))
          ]
      focus = firstNonEmpty [ipfFocusNominative frame, ipfFocusEntity frame, atomFocus, ssLastTopic ss]
      bestTopic = if T.null focus then ssLastTopic ss else focus
      resonance = atCurrentLoad newTrace
      atomLoad = asLoad atomSet
      semanticInput =
        buildSemanticInputSimple
          input
          atomSet
          frame
          recommendedFamily
          (ipfRegisterHint frame)
          (ipfSemanticLayer frame)
      blanket = computeSelfBlanket ss
      violations = checkInitialBlanket blanket
      conatusEnergy = computeConatusEnergy blanket violations
      violationCount = length violations
      conatusGateFired = conatusGateFires conatusEnergy
      -- Phase 5.5d: populate four of five Field components
      -- from runtime signals:
      --   * Resonance      <- atom-trace current load (already
      --                       computed above as 'resonance').
      --   * Consolidation  <- topic-stability heuristic: same
      --                       focused topic as previous turn
      --                       => 0.8; topic changed or first
      --                       turn => 0.2.
      --   * Counterfactual <- candidate-family ambiguity:
      --                       ratio of second-best to best
      --                       family weight in the semantic-
      --                       logic ranking; > 0 only when at
      --                       least two families are ranked.
      --   * Atmosphere     <- Ego differential:
      --                         valence = agency - tension
      --                                   (high agency + low
      --                                    tension = positive;
      --                                    low agency + high
      --                                    tension = negative)
      --                         arousal = tension (structural
      --                                   proxy for activation
      --                                   level).
      -- 'fieldConfidence' is now derived via 'deriveFieldConfidence'
      -- on the four populated components (Resonance, Atmosphere,
      -- Consolidation, Counterfactual).  The default formula reduces
      -- Atmosphere to arousal magnitude and computes 1 - dispersion
      -- (variance of the four scalars).  This is still heuristic,
      -- but it is no longer the fixed 1.0 default.
      -- Step 6a: sliding-window narrative-consolidation replaces
      -- the old binary topic-stability heuristic.
      recentSuccess = take 5 $ ssRecentNarrativeSuccess ss
      narrativeRate = if null recentSuccess
                        then 0.2
                        else fromIntegral (length (filter id recentSuccess))
                             / fromIntegral (length recentSuccess)
      topicStability =
        if not (T.null bestTopic) && bestTopic == ssLastTopic ss
          then max 0.5 narrativeRate
          else narrativeRate
      -- Step 6b: entropy-based counterfactual replaces the w2/w1 gap.
      -- 1.0 = all families equiprobable, 0.0 = one family dominates.
      weights = map snd sortedLogic
      totalWeight = sum weights
      normWeights = map (/ max 1e-9 totalWeight) weights
      entropy = negate $ sum [p * log (max 1e-9 p) | p <- normWeights]
      maxEntropy = log (fromIntegral (max 1 (length normWeights)))
      counterfactualAmbiguity = if maxEntropy > 0 then entropy / maxEntropy else 0.0
      -- Step 4: feedback bias from holistic streak into counterfactual
      -- ambiguity.  Long unbroken holistic runs raise the "what if we
      -- had chosen differently?" signal, which dampens salience
      -- confidence and can trigger a mode switch via the controller.
      streakBoost = min (fromIntegral (ssHolisticStreak ss) * 0.05) 0.2
      adjustedCounterfactual = min 1.0 (counterfactualAmbiguity + streakBoost)
      -- Step 6c: legitimacy score modulates atmosphere valence.
      -- High legitimacy -> positive affect; low -> negative.
      valenceBase = egoAgency (ssEgo ss) - egoTension (ssEgo ss)
      legitScore = obsLastLegitimacyScore (ssObservability ss)
      legitBonus = (legitScore - 0.5) * 0.4
      atmosphereValence = max (-1.0) (min 1.0 (valenceBase + legitBonus))
      atmosphereArousal = egoTension (ssEgo ss)
      preparedField0 = emptyField
        { fieldResonance      = mkResonance resonance
        , fieldAtmosphere     = mkAtmosphere atmosphereValence atmosphereArousal
        , fieldConsolidation  = mkConsolidation topicStability
        , fieldCounterfactual = mkCounterfactual adjustedCounterfactual
        }
      preparedField = preparedField0
        { fieldConfidence = deriveFieldConfidence preparedField0
        }
      static = PrepareStatic
        { psInputText = input
        , psAtomSet = atomSet
        , psNewTrace = newTrace
        , psNextUserState = nextUserState
        , psRecommendedFamily = recommendedFamily
        , psFrame = frame
        , psConceptToCheck = conceptToCheck
        , psBestTopic = bestTopic
        , psResonance = resonance
        , psAtomLoad = atomLoad
        , psConatusEnergy = conatusEnergy
        , psBlanketViolationCount = violationCount
        , psConatusGateFired = conatusGateFired
        , psField = preparedField
        }
  in PrepareEffectPlan
      { pepStatic = static
      , pepEmbeddingRequest = PrepareReqEmbedding input
      , pepNixGuardRequest = PrepareReqNixGuard conceptToCheck resonance atomLoad
      , pepConsciousnessRequest =
          PrepareReqConsciousness semanticInput (egoAgency (ssEgo ss)) resonance conatusEnergy
      , pepIntuitionRequest =
          PrepareReqIntuition input resonance (egoTension (ssEgo ss)) (ssTurnCount ss + 1) conatusEnergy
      , pepApiHealthRequest = PrepareReqApiHealth
      }
  where
    firstNonEmpty = fromMaybe "" . listToMaybe . filter (not . T.null)
