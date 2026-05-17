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
  )
import QxFx0.Self.Invariants (checkInitialBlanket)

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
  , psField :: !Field
    -- ^ Phase 5.5d: per-turn 'QxFx0.Self.Field.Field' snapshot.
    --   Currently only 'fieldResonance' is populated from
    --   'psResonance' (atom-trace current load); the remaining
    --   four components ('fieldAtmosphere', 'fieldConfidence',
    --   'fieldConsolidation', 'fieldCounterfactual') stay at
    --   their 'emptyField' defaults pending the broader Field-
    --   broadening work (Atmosphere from Ego, Consolidation
    --   from topic stability, Counterfactual from candidate
    --   ambiguity). Threaded through 'tiField' so all routing
    --   and salience-decision call sites share one canonical
    --   pre-turn Field.
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
      -- 'fieldConfidence' stays at 1.0 (the 'emptyField'
      -- default) which per ADR-0009 §4.4 means "uninformed,
      -- not unconfident" — a derived confidence signal across
      -- the four channels is left for a later refinement
      -- (could call 'deriveFieldConfidence' here, but the
      -- current four sources are still heuristic so a
      -- derived confidence would risk false precision).
      topicStability =
        if not (T.null bestTopic) && bestTopic == ssLastTopic ss
          then 0.8
          else 0.2
      counterfactualAmbiguity = case sortedLogic of
        (_, w1) : (_, w2) : _ | w1 > 0 -> w2 / w1
        _ -> 0.0
      atmosphereValence = egoAgency (ssEgo ss) - egoTension (ssEgo ss)
      atmosphereArousal = egoTension (ssEgo ss)
      preparedField = emptyField
        { fieldResonance      = mkResonance resonance
        , fieldAtmosphere     = mkAtmosphere atmosphereValence atmosphereArousal
        , fieldConsolidation  = mkConsolidation topicStability
        , fieldCounterfactual = mkCounterfactual counterfactualAmbiguity
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
