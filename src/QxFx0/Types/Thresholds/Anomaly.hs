{-| Anomaly-detection gates (Anomaly Architecture v3.0).

Central registry for the numeric gates in
'QxFx0.Core.TurnPipeline.Route.Anomaly'. Values are the audited
v3.0 gates, verbatim: moving them here changes no behavior, it
only gives tuning a single address. Any change to these values
is calibration-grade (pre-register rule + bar, math-version
bump per the regime law).
-}
module QxFx0.Types.Thresholds.Anomaly
  ( anomalySelfRefAngst
  , anomalyCollapseConfidence
  , anomalyAntiConatusConfidence
  , anomalyAntiConatusAngst
  , anomalyAntiConatusEnergy
  , anomalyAntiConatusConfidenceOut
  , anomalyTemporalConfidence
  , anomalyUnclassifiableRatio
  ) where

-- | Angst above which a self-referential subject collapses (Anomaly-3).
anomalySelfRefAngst :: Double
anomalySelfRefAngst = 0.9

-- | Confidence attached to the collapse anomaly (Anomaly-3).
anomalyCollapseConfidence :: Double
anomalyCollapseConfidence = 0.95

-- | Stance confidence above which a weakening move is anti-conatus (Anomaly-2).
anomalyAntiConatusConfidence :: Double
anomalyAntiConatusConfidence = 0.7

-- | Angst above which a weakening move is anti-conatus (Anomaly-2).
anomalyAntiConatusAngst :: Double
anomalyAntiConatusAngst = 0.8

-- | Conatus energy below which a weakening move is anti-conatus (Anomaly-2).
anomalyAntiConatusEnergy :: Double
anomalyAntiConatusEnergy = 5.0

-- | Confidence attached to the anti-conatus anomaly (Anomaly-2).
anomalyAntiConatusConfidenceOut :: Double
anomalyAntiConatusConfidenceOut = 0.85

-- | Confidence attached to the temporal anomaly.
anomalyTemporalConfidence :: Double
anomalyTemporalConfidence = 0.85

-- | Known-atom ratio below which input is unclassifiable.
anomalyUnclassifiableRatio :: Double
anomalyUnclassifiableRatio = 0.2
