{-| Selection and render admission floors.

Central registry for the affinity/score floors scattered across
content selection ('QxFx0.Semantic.ContentSelector'), analogy
fallback ('QxFx0.Semantic.Analogy'), render admission
('QxFx0.Core.TurnPipeline.Route.Render'), finalize adaptation
('QxFx0.Core.TurnPipeline.Finalize.State' /
'QxFx0.Core.TurnPipeline.Finalize.Projection'), and route-hint
arbitration ('QxFx0.Semantic.Input.Assemble'). Values verbatim:
no behavior change, single address for tuning
(calibration-grade changes only).
-}
module QxFx0.Types.Thresholds.Selection
  ( selectorAffinityFloor
  , selectorBaseMultiplier
  , selectorBonusRate
  , compositionActivationFloor
  , compositionShareFloor
  , compositionFallbackBaseScore
  , analogyFallbackFloor
  , externalToolReliabilityFloor
  , learningNeedEscalationLevel
  , adaptiveSignalEpsilon
  , activationReportFloor
  , routeHintMargin
  ) where

-- | Minimum adjusted score for a predicate to clear selection.
selectorAffinityFloor :: Double
selectorAffinityFloor = 0.1

-- | Neutral base of the boosted score multiplier (selection
-- activation bonus and ontology depth boost).
selectorBaseMultiplier :: Double
selectorBaseMultiplier = 1.0

-- | Activation value above which an atom/topic counts as activated
-- for content composition (spreading-activation views).
compositionActivationFloor :: Double
compositionActivationFloor = 0.05

-- | Minimum share of the summed score a predicate must reach to
-- survive composition filtering (@score >= totalScore * floor@).
compositionShareFloor :: Double
compositionShareFloor = 0.3

-- | Base score assigned to the first predicate of a topic when
-- scoring yields no candidates in composition fallback.
compositionFallbackBaseScore :: Double
compositionFallbackBaseScore = 0.3

-- | Bonus rate in the adjusted-score multiplier.
selectorBonusRate :: Double
selectorBonusRate = 0.3

-- | Minimum similarity for the analogy fallback topic.
analogyFallbackFloor :: Double
analogyFallbackFloor = 0.3

-- | Minimum tool reliability for issuing an external action.
externalToolReliabilityFloor :: Double
externalToolReliabilityFloor = 0.3

-- | Learning-need level at which a need escalates beyond local strategies (WP3).
learningNeedEscalationLevel :: Double
learningNeedEscalationLevel = 0.6

-- | Absolute signal strength for strong/adaptive evidence.
adaptiveSignalEpsilon :: Double
adaptiveSignalEpsilon = 0.15

-- | Activation value above which a concept is reported (P0.2).
activationReportFloor :: Double
activationReportFloor = 0.05

-- | Score margin by which the best candidate must beat the rule candidate.
routeHintMargin :: Double
routeHintMargin = 0.05
