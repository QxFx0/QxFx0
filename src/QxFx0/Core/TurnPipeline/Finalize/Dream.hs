{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage dream-cycle application and rewiring event extraction. -}
module QxFx0.Core.TurnPipeline.Finalize.Dream
  ( applyDreamDynamics
  ) where

import QxFx0.Core.Dream.Pressure
import QxFx0.Types
import QxFx0.Types.Config.Dream (defaultDreamPressureRegime, dreamFamilyBiasProfile, dreamMaxAttractorNormDefault)
import QxFx0.Types.Thresholds
  ( dreamAttractorDirectivenessPenalty
  , dreamAttractorNormScale
  , dreamExperienceWeightBase
  , dreamExperienceWeightIntuitionScale
  , dreamExperienceWeightLoadScale
  , dreamQualityWeightShadowDivergedFloor
  , dreamQualityWeightShadowDivergedScale
  , dreamQualityWeightShadowUnavailableFloor
  , dreamQualityWeightShadowUnavailableScale
  , dreamQualityWeightStableBonus
  , dreamRewireBiasDelta
  , dreamRewireMinEdgeCount
  , dreamRewireSuccessRateThreshold
  , dreamRewireWeightFloor
  )
import QxFx0.Core.TurnPipeline.Types
import qualified QxFx0.Core.DreamDynamics as Dream
import QxFx0.Core.MeaningGraph (rewireMeaningGraphForDreamCycle, successRate)

import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

applyDreamDynamics :: UTCTime -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> MeaningGraph -> (Dream.DreamState, MeaningGraph, Int)
applyDreamDynamics now ss ti ts tp ta baseGraph =
  let currentDreamState = semDreamState (ssSemantic ss)
      dreamOutcome = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      evidence = buildDreamThemeEvidence dreamOutcome ti ts tp ta
      (dreamState', cycleLogs) =
        Dream.runDreamCatchup Dream.defaultDreamConfig evidence now currentDreamState
      edgeDeltas =
        if null cycleLogs
          then []
          else
            [ (edge, dreamEdgeDelta attractor edge)
            | edge <- mgEdges baseGraph
            , meCount edge >= dreamRewireMinEdgeCount
            ]
      (rewired, rewireEvents) =
        if null edgeDeltas
          then (baseGraph, [])
          else rewireMeaningGraphForDreamCycle now edgeDeltas baseGraph
      attractor = Dream.dsBiasAttractor dreamState'
   in (dreamState', rewired, length cycleLogs + length rewireEvents)

buildDreamThemeEvidence :: DreamOutcome -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> [Dream.DreamThemeEvidence]
buildDreamThemeEvidence dreamOutcome ti ts tp ta =
  [ Dream.DreamThemeEvidence
      { Dream.dteTheme = dreamThemeLabel
      , Dream.dteBias =
          clampVecNorm dreamMaxAttractorNormDefault
            ( vecAdd
                (dreamFamilyBiasProfile (tdFamily (taDecision ta)))
                (vecAdd (doBias dreamOutcome) (doAppliedBias dreamOutcome))
            )
      , Dream.dteExperienceWeight =
          min 1.0
            ( dreamExperienceWeightBase
            + tsIntuitPosterior ts * dreamExperienceWeightIntuitionScale
            + asLoad (tiAtomSet ti) * dreamExperienceWeightLoadScale
            )
      , Dream.dteQualityWeight = min 1.0 (qualityWeight + candidateBonus (doCandidateDecisions dreamOutcome))
      , Dream.dteBiographyPermission = not (tpShadowGateTriggered tp)
      }
  ]
  where
    dreamThemeLabel =
      let topic = tiBestTopic ti
      in if T.null topic then T.pack (show (tdFamily (taDecision ta))) else topic
    qualityWeight
      | tpShadowStatus tp == ShadowUnavailable =
          max dreamQualityWeightShadowUnavailableFloor
            (tpLegitScore tp * dreamQualityWeightShadowUnavailableScale)
      | tpShadowStatus tp == ShadowDiverged =
          max dreamQualityWeightShadowDivergedFloor
            (tpLegitScore tp * dreamQualityWeightShadowDivergedScale)
      | otherwise = min 1.0 (tpLegitScore tp + dreamQualityWeightStableBonus)
    candidateBonus [] = 0.0
    candidateBonus decisions =
      let acceptedStrengths =
            [ dccStrength (dceCandidate (adcEnvelope accepted))
            | DreamCandidateAccepted accepted <- decisions
            ]
      in case acceptedStrengths of
           [] -> 0.0
           _ -> min 0.15 (maximum acceptedStrengths * 0.1)

dreamEdgeDelta :: CoreVec -> MeaningEdge -> Double
dreamEdgeDelta attractor edge =
  let normWeight = min 1.0 (vecNorm attractor / dreamAttractorNormScale)
      attractorWeight =
        cvPresence attractor
          + cvDepth attractor
          + cvSteadiness attractor
          - cvDirectiveness attractor * dreamAttractorDirectivenessPenalty
      direction =
        if successRate edge > dreamRewireSuccessRateThreshold then 1.0 else -1.0
  in direction * dreamRewireBiasDelta * max dreamRewireWeightFloor (normWeight * max 0.0 attractorWeight)
