module QxFx0.Types.Thresholds.GameTheory where

-- Depth costs for different canonical moves
depthCostDeepen, depthCostHypothesis, depthCostDefine, depthCostDistinguish, depthCostDefault :: Double
depthCostDeepen     = 0.2
depthCostHypothesis = 0.25
depthCostDefine     = 0.15
depthCostDistinguish = 0.1
depthCostDefault    = 0.05

-- Engagement penalties
engagementPenaltyMedium, engagementPenaltyLow :: Double
engagementPenaltyMedium = -0.1
engagementPenaltyLow    = -0.3

-- Phase multipliers
phaseMultiplierOpening, phaseMultiplierExploring, phaseMultiplierDeep, phaseMultiplierClosing :: Double
phaseMultiplierOpening   = 1.2
phaseMultiplierExploring = 1.0
phaseMultiplierDeep      = 0.8
phaseMultiplierClosing   = 0.5

-- Tension threshold for high-tension bonus
tensionHighThreshold :: Double
tensionHighThreshold = 0.6

-- Tension bonus values for different moves under high tension
tensionBonusContact, tensionBonusRepair, tensionBonusReflect, tensionBonusGround, tensionBonusDefault :: Double
tensionBonusContact = 0.5
tensionBonusRepair  = 0.4
tensionBonusReflect = 0.2
tensionBonusGround  = 0.1
tensionBonusDefault = -0.2

-- Insight shift bonuses
insightShiftDefine, insightShiftDeepen, insightShiftClarify, insightShiftDefault :: Double
insightShiftDefine  = 0.4
insightShiftDeepen  = 0.3
insightShiftClarify = 0.2
insightShiftDefault = 0.0

-- Contradiction shift bonuses
contradictionShiftConfront, contradictionShiftDistinguish, contradictionShiftClarify, contradictionShiftDefault :: Double
contradictionShiftConfront    = 0.3
contradictionShiftDistinguish = 0.2
contradictionShiftClarify     = 0.2
contradictionShiftDefault     = -0.1

-- User bonus for matching moves
userBonusDefine, userBonusClarify, userBonusAnchor, userBonusDeepenDefine, userBonusConfrontContact, userBonusReflectRepair, userBonusContactContact, userBonusRepairConfront :: Double
userBonusDefine        = 0.3
userBonusClarify       = 0.3
userBonusAnchor        = 0.3
userBonusDeepenDefine  = -0.2
userBonusConfrontContact = -0.3
userBonusReflectRepair = 0.2
userBonusContactContact = 0.25
userBonusRepairConfront = 0.5

-- Tension coefficient for utility calculation
tensionCoefficient :: Double
tensionCoefficient = 0.3
