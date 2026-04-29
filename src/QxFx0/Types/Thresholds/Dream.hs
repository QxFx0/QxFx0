module QxFx0.Types.Thresholds.Dream
  ( dreamRewireCycleInterval
  , dreamRewireSuccessRateThreshold
  , dreamRewireBiasDelta
  , dreamRewireMinEdgeCount
  , dreamMinCycleDurationHours
  , meaningGraphRoutingThreshold
  , meaningGraphDreamBiasLimit
  , dreamExperienceWeightBase
  , dreamExperienceWeightIntuitionScale
  , dreamExperienceWeightLoadScale
  , dreamQualityWeightShadowUnavailableFloor
  , dreamQualityWeightShadowUnavailableScale
  , dreamQualityWeightShadowDivergedFloor
  , dreamQualityWeightShadowDivergedScale
  , dreamQualityWeightStableBonus
  , dreamAttractorNormScale
  , dreamAttractorDirectivenessPenalty
  , dreamRewireWeightFloor
  ) where

dreamRewireCycleInterval :: Int
dreamRewireCycleInterval = 10

dreamRewireSuccessRateThreshold :: Double
dreamRewireSuccessRateThreshold = 0.5

dreamRewireBiasDelta :: Double
dreamRewireBiasDelta = 0.05

dreamRewireMinEdgeCount :: Int
dreamRewireMinEdgeCount = 2

dreamMinCycleDurationHours :: Double
dreamMinCycleDurationHours = 0.25

meaningGraphRoutingThreshold :: Double
meaningGraphRoutingThreshold = 0.5

meaningGraphDreamBiasLimit :: Double
meaningGraphDreamBiasLimit = 0.25

dreamExperienceWeightBase :: Double
dreamExperienceWeightBase = 0.45

dreamExperienceWeightIntuitionScale :: Double
dreamExperienceWeightIntuitionScale = 0.35

dreamExperienceWeightLoadScale :: Double
dreamExperienceWeightLoadScale = 0.20

dreamQualityWeightShadowUnavailableFloor :: Double
dreamQualityWeightShadowUnavailableFloor = 0.35

dreamQualityWeightShadowUnavailableScale :: Double
dreamQualityWeightShadowUnavailableScale = 0.6

dreamQualityWeightShadowDivergedFloor :: Double
dreamQualityWeightShadowDivergedFloor = 0.20

dreamQualityWeightShadowDivergedScale :: Double
dreamQualityWeightShadowDivergedScale = 0.5

dreamQualityWeightStableBonus :: Double
dreamQualityWeightStableBonus = 0.1

dreamAttractorNormScale :: Double
dreamAttractorNormScale = 0.08

dreamAttractorDirectivenessPenalty :: Double
dreamAttractorDirectivenessPenalty = 0.6

dreamRewireWeightFloor :: Double
dreamRewireWeightFloor = 0.25
