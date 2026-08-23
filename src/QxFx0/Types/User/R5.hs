{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.User.R5
Description : canonical — user-side R5 state space, viability contour, and residual-audit carriers (concept v3 §4/§6).

Concept v3 replaces the static categorical user reading with a
numeric state vector @UserR5State ∈ ℝ⁵@.  The five axes deliberately
mirror the system-side 'QxFx0.Self.Field' components — Resonance,
Atmosphere, Confidence, Consolidation, Counterfactual — but the
/subject/ is different: this is the decoded state of the
system-human, not the system's observation of itself.  The two
carriers must never be conflated.

Ranges (all clamped by 'mkUserR5State'):

* @r5Resonance@ in @[0,1]@ — созвучие с миром и собеседником.
* @r5Atmosphere@ in @[0,1]@ — напряжённость\/давление (a single
  scalar here, unlike the system Field's 2-D affect plane).
* @r5Confidence@ in @[0,1]@ — вера в будущее и свои силы.
* @r5Consolidation@ in @[0,1]@ — целостность картины мира.
* @r5Counterfactual@ in @[0,1]@ — способность видеть альтернативы.

The viability contour (concept v3 §4) is the region where the
user's Conatus is active.  'userConatusScore' is the linear contour

@
score = w₁·Resonance + w₂·Confidence + w₃·Consolidation
      − w₄·Atmosphere − w₅·(1 − Counterfactual)
@

and 'outsideViabilityContour' decides Protocol A/B membership from
the score, the absolute floor, and the personalized baseline (a slow
EMA over the first turns; one extreme utterance must not redefine
the norm — 'updateUserBaseline').

The residual-audit carriers ('UserR5ContourState',
'r5Distance', 'pushR5Sample', and the move-conditioned
'QxFx0.Types.Semantic.MoveGraph.transitionUserR5') clone the proven
A-slice self-divergence pattern (predict → witness → diff → bounded
window) onto the user side: each turn the encoder observes the
actual user state, it is compared against the deterministic
prediction made on the previous turn, and the error feeds a bounded
window.  The transition model itself is deliberately the identity
(@v1@ persistence hypothesis); learning transitions offline is a
later phase and must go through the learning-targets governance
(@docs\/closure\/LEARNING_ALLOWED_TARGETS.md@).
-}
module QxFx0.Types.User.R5
  ( -- * The state vector
    UserR5State(..)
  , mkUserR5State
  , neutralUserR5State
    -- * Linear viability contour
  , UserConatusWeights(..)
  , defaultUserConatusWeights
  , userConatusScore
    -- * Contour membership and personalization
  , ViabilityContour(..)
  , defaultViabilityContour
  , outsideViabilityContour
  , updateUserBaseline
    -- * Residual audit (predict -> witness -> diff)
  , r5Distance
  , pushR5Sample
  , negativeEvidenceEarned
  , r5EncoderVersion
    -- * Persisted per-session carry
  , UserR5ContourState(..)
  , emptyUserR5ContourState
    -- * Observability
  , UserR5Trace(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import GHC.Generics (Generic)

-- | The user-side state vector.  All components in @[0,1]@.
data UserR5State = UserR5State
  { r5Resonance :: !Double
  , r5Atmosphere :: !Double
  , r5Confidence :: !Double
  , r5Consolidation :: !Double
  , r5Counterfactual :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Clamp every component into @[0,1]@ (lifeness gate, mirrors the
-- system-side smart constructors).
mkUserR5State :: Double -> Double -> Double -> Double -> Double -> UserR5State
mkUserR5State res atm conf cons cf = UserR5State
  { r5Resonance = clamp01 res
  , r5Atmosphere = clamp01 atm
  , r5Confidence = clamp01 conf
  , r5Consolidation = clamp01 cons
  , r5Counterfactual = clamp01 cf
  }

-- | The no-signal neutral point: mid-scale on all axes except a calm
-- atmosphere floor (0.25) and a mildly open counterfactual (0.4).
-- These are the same constants the v1 encoder uses as its bases —
-- see @QxFx0.User.R5@.
neutralUserR5State :: UserR5State
neutralUserR5State = mkUserR5State 0.5 0.25 0.5 0.5 0.4

-- | Weights of the linear user-side Conatus contour (concept v3 §4).
-- Hand-set v1 (frozen on release); empirical fitting is deferred to
-- the calibration phase per @CALIBRATION_BACKLOG.md@ discipline.
data UserConatusWeights = UserConatusWeights
  { ucwResonance :: !Double
  , ucwConfidence :: !Double
  , ucwConsolidation :: !Double
  , ucwAtmosphere :: !Double
  , ucwCounterfactual :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | v1: w₁=0.25 (resonance), w₂=0.25 (confidence), w₃=0.20
-- (consolidation), w₄=0.20 (atmosphere), w₅=0.10 (closed
-- counterfactual penalty).
defaultUserConatusWeights :: UserConatusWeights
defaultUserConatusWeights = UserConatusWeights
  { ucwResonance = 0.25
  , ucwConfidence = 0.25
  , ucwConsolidation = 0.20
  , ucwAtmosphere = 0.20
  , ucwCounterfactual = 0.10
  }

-- | The linear viability score.  Natural band under
-- 'defaultUserConatusWeights' is @[−0.3, 0.7]@ with the neutral
-- point at ≈0.24.
userConatusScore :: UserConatusWeights -> UserR5State -> Double
userConatusScore w s =
  ucwResonance w * r5Resonance s
    + ucwConfidence w * r5Confidence s
    + ucwConsolidation w * r5Consolidation s
    - ucwAtmosphere w * r5Atmosphere s
    - ucwCounterfactual w * (1.0 - r5Counterfactual s)

-- | Contour parameters.  A state is outside the contour iff the
-- score is below the absolute floor, or below
-- @baseline − personalMargin@ once a personalized baseline exists.
data ViabilityContour = ViabilityContour
  { vcAbsoluteFloor :: !Double
    -- ^ Hard floor for Protocol A membership.  v1 = 0.05, low in the
    --   natural band so that ordinary fatigue (\"мне всё надоело\")
    --   stays inside the contour (concept v3 §9 edge case).
  , vcPersonalMargin :: !Double
    -- ^ Allowed drop below the personalized baseline before the
    --   contour is exited.  v1 = 0.25.
  , vcBaselineWindowTurns :: !Int
    -- ^ EMA window for the personalized baseline (α = 2/(N+1)).
    --   v1 = 10: one extreme utterance moves the baseline by at
    --   most ~18% of its distance from the observation.
  , vcDivergenceWindow :: !Int
    -- ^ Bounded length of the residual (prediction-error) window.
    --   v1 = 8, same discipline as the self-divergence window.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

defaultViabilityContour :: ViabilityContour
defaultViabilityContour = ViabilityContour
  { vcAbsoluteFloor = 0.05
  , vcPersonalMargin = 0.25
  , vcBaselineWindowTurns = 10
  , vcDivergenceWindow = 8
  }

-- | Contour membership.  Concept v3 §9 invariant: the answer is a
-- single 'Bool' — a state can never be both inside and outside.
--
-- The /relative/ branch (below the personalized baseline) is
-- evidence-gated by 'negativeEvidenceEarned': the encoder's score
-- conflates utterance form (question shape, topic continuity) with
-- user state, so a style change alone must not read as a contour
-- exit — the drop has to be /earned/ by negative signals in the
-- state itself.  The absolute-floor branch needs no gate: the v1
-- encoder's arithmetic makes a sub-floor score unreachable without
-- a distress pile-up.
outsideViabilityContour
  :: ViabilityContour
  -> Maybe Double      -- ^ personalized baseline, if one exists
  -> UserR5State       -- ^ observed state (evidence for the relative branch)
  -> Double            -- ^ observed user Conatus score
  -> Bool
outsideViabilityContour contour mBaseline state score
  | score < vcAbsoluteFloor contour = True
  | Just baseline <- mBaseline
  , negativeEvidenceEarned state
  , score < baseline - vcPersonalMargin contour = True
  | otherwise = False

-- | Has the utterance earned a below-baseline reading?  True when
-- the state itself carries negative signals (raised tension or
-- lowered agency), not merely a quieter form.  Hand-set v1
-- (frozen); thresholds track the encoder's neutral point
-- (atmosphere 0.25, confidence 0.5).
negativeEvidenceEarned :: UserR5State -> Bool
negativeEvidenceEarned s =
  r5Atmosphere s > 0.30 || r5Confidence s < 0.45

-- | Slow EMA update of the personalized baseline.  The first
-- observation initializes the baseline; afterwards the baseline
-- moves by α = 2/(window+1) per turn, so a single extreme utterance
-- cannot redefine the user's norm (concept v3 §4 regularization).
updateUserBaseline
  :: ViabilityContour
  -> Maybe Double  -- ^ prior baseline
  -> Double        -- ^ this turn's observed score
  -> Maybe Double
updateUserBaseline contour Nothing score =
  Just (clampScore score)
updateUserBaseline contour (Just baseline) score =
  let n = fromIntegral (max 1 (vcBaselineWindowTurns contour))
      alpha = 2.0 / (n + 1.0)
  in Just (clampScore ((1.0 - alpha) * baseline + alpha * score))

-- | Mean absolute component difference between two states — the
-- residual magnitude for the prediction audit.
r5Distance :: UserR5State -> UserR5State -> Double
r5Distance a b =
  let ds =
        [ abs (r5Resonance a - r5Resonance b)
        , abs (r5Atmosphere a - r5Atmosphere b)
        , abs (r5Confidence a - r5Confidence b)
        , abs (r5Consolidation a - r5Consolidation b)
        , abs (r5Counterfactual a - r5Counterfactual b)
        ]
  in sum ds / 5.0

-- | The v1 transition model lives in
-- 'QxFx0.Types.Semantic.MoveGraph.transitionUserR5'
-- (move-conditioned, persistence without a move).  Fitting real
-- transitions offline (concept v3 §6 \"обновление\") is a governed
-- later phase — until then the recorded residuals measure exactly
-- how wrong the model is.

-- | Version of the frozen user-R5 encoder model.  Canonical home is
-- this Types module so the replay trace can stamp it without an
-- implementation import; @User.R5@ re-exports it.
r5EncoderVersion :: Int
r5EncoderVersion = 1

-- | Bounded drop-oldest push for the residual window (mirrors
-- 'QxFx0.Self.SelfDivergence.pushDivergenceSample'): prepend the
-- newest sample, keep the @n@ most recent.
pushR5Sample :: Int -> [Double] -> Double -> [Double]
pushR5Sample n window newest =
  take (max 1 n) (newest : window)

-- | Persisted per-session carry for the user contour.  JSON
-- backward-compatible: absent field decodes to
-- 'emptyUserR5ContourState'.
data UserR5ContourState = UserR5ContourState
  { u5LastState :: !(Maybe UserR5State)
    -- ^ Last observed (encoded) user state.
  , u5Baseline :: !(Maybe Double)
    -- ^ Personalized viability baseline (slow EMA).
  , u5PredictedNext :: !(Maybe UserR5State)
    -- ^ Deterministic prediction of the /next/ user state, made from
    --   the last observation.  Nothing before the first turn.
  , u5DivergenceWindow :: ![Double]
    -- ^ Bounded residuals (@r5Distance predicted actual@), newest
    --   first.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptyUserR5ContourState :: UserR5ContourState
emptyUserR5ContourState = UserR5ContourState
  { u5LastState = Nothing
  , u5Baseline = Nothing
  , u5PredictedNext = Nothing
  , u5DivergenceWindow = []
  }

-- | Replay-visible user-contour observability for one turn.
data UserR5Trace = UserR5Trace
  { ur5Resonance :: !Double
  , ur5Atmosphere :: !Double
  , ur5Confidence :: !Double
  , ur5Consolidation :: !Double
  , ur5Counterfactual :: !Double
  , ur5ConatusScore :: !Double
  , ur5Baseline :: !(Maybe Double)
    -- ^ Baseline after this turn's EMA update.
  , ur5OutsideContour :: !Bool
    -- ^ The contour membership that drove this turn's protocol.
  , ur5PredictionError :: !(Maybe Double)
    -- ^ Residual against the previous turn's prediction; Nothing on
    --   the first turn.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0

clampScore :: Double -> Double
clampScore = max (-1.0) . min 1.0
