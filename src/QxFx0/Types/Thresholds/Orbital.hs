module QxFx0.Types.Thresholds.Orbital
  ( orbitalHighRiskThreshold
  , orbitalCounterpressureThreshold
  , encounterMirroringTensionThreshold
  , egoTensionDecayFactor
  , egoTensionInputFactor
  , egoAgencyDecayFactor
  , egoAgencyInputFactor
  , egoTrendWindow
  , egoTrendRisingThreshold
  , egoTrendFallingThreshold
  , egoHistoryRetention
  , egoHistoryLimit
  , orbitalHistoryLimit
  , orbitalDistEstCollapseRisk
  , orbitalDistEstFreezeRisk
  , orbitalDistEstCounterpressure
  , orbitalDistEstRecovery
  , orbitalDistEstStable
  , orbitalEmaAlpha
  , orbitalContactBoostRecovery
  , orbitalContactBoostFreezeRisk
  , orbitalContactPenaltyCounterpressure
  , orbitalBoundaryBoostCollapseRisk
  , orbitalBoundaryBoostCounterpressure
  , orbitalBoundaryPenaltyRecovery
  , directiveDefaultContactBias
  , directiveDefaultBoundaryBias
  , directiveDefaultAssertionForce
  , directiveDefaultCounterpressureStrength
  , directiveDefaultStabilityUnderTension
  ) where

orbitalHighRiskThreshold :: Double
orbitalHighRiskThreshold = 0.7

orbitalCounterpressureThreshold :: Double
orbitalCounterpressureThreshold = 0.4

encounterMirroringTensionThreshold :: Double
encounterMirroringTensionThreshold = 0.5

egoTensionDecayFactor :: Double
egoTensionDecayFactor = 0.85

egoTensionInputFactor :: Double
egoTensionInputFactor = 0.15

egoAgencyDecayFactor :: Double
egoAgencyDecayFactor = 0.8

egoAgencyInputFactor :: Double
egoAgencyInputFactor = 0.2

egoTrendWindow :: Int
egoTrendWindow = 5

egoTrendRisingThreshold :: Double
egoTrendRisingThreshold = 0.05

egoTrendFallingThreshold :: Double
egoTrendFallingThreshold = -0.05

egoHistoryRetention :: Int
egoHistoryRetention = 19

egoHistoryLimit :: Int
egoHistoryLimit = 20

orbitalHistoryLimit :: Int
orbitalHistoryLimit = 24

orbitalDistEstCollapseRisk :: Double
orbitalDistEstCollapseRisk = 0.8

orbitalDistEstFreezeRisk :: Double
orbitalDistEstFreezeRisk = 0.9

orbitalDistEstCounterpressure :: Double
orbitalDistEstCounterpressure = 0.6

orbitalDistEstRecovery :: Double
orbitalDistEstRecovery = 0.4

orbitalDistEstStable :: Double
orbitalDistEstStable = 0.3

orbitalEmaAlpha :: Double
orbitalEmaAlpha = 0.15

orbitalContactBoostRecovery :: Double
orbitalContactBoostRecovery = 0.15

orbitalContactBoostFreezeRisk :: Double
orbitalContactBoostFreezeRisk = 0.20

orbitalContactPenaltyCounterpressure :: Double
orbitalContactPenaltyCounterpressure = -0.10

orbitalBoundaryBoostCollapseRisk :: Double
orbitalBoundaryBoostCollapseRisk = 0.15

orbitalBoundaryBoostCounterpressure :: Double
orbitalBoundaryBoostCounterpressure = 0.20

orbitalBoundaryPenaltyRecovery :: Double
orbitalBoundaryPenaltyRecovery = -0.10

directiveDefaultContactBias :: Double
directiveDefaultContactBias = 0.5

directiveDefaultBoundaryBias :: Double
directiveDefaultBoundaryBias = 0.5

directiveDefaultAssertionForce :: Double
directiveDefaultAssertionForce = 0.5

directiveDefaultCounterpressureStrength :: Double
directiveDefaultCounterpressureStrength = 0.5

directiveDefaultStabilityUnderTension :: Double
directiveDefaultStabilityUnderTension = 0.5
