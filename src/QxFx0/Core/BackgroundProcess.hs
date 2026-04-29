{-# LANGUAGE DerivingStrategies, OverloadedStrings #-}
{-| Background surfacing state machine and pressure-channel bookkeeping. -}
module QxFx0.Core.BackgroundProcess
  ( PressureChannel(..)
  , BackgroundState(..)
  , SurfacingEvent(..)
  , initialBackground
  , recordDesireConflict
  , runBackgroundCycle
  , checkSurfacing
  , surfacingToFragment
  , surfacingThreshold
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (sortBy)
import Data.Ord (comparing, Down(..))
import QxFx0.Types.Thresholds
  ( backgroundConflictMediumThreshold
  , backgroundConflictStrongThreshold
  , backgroundDesireConflictDelta
  , backgroundExplicitConflictDelta
  , backgroundPressureDecayFactor
  , backgroundProductModeResistanceDelta
  , backgroundSurfacingThreshold
  )
import QxFx0.Core.Policy.Consciousness
  ( desireConflictPrefix, productModeSkillLabel
  , surfacingDesireConflictPrefix, surfacingPatternNoticePrefix
  , surfacingSelfModelGapPrefix, surfacingTrajectoryInsightPrefix
  , surfacingProductModePrefix, surfacingProductModeFragment
  , conflictStrongFragment, conflictStrongSuffix, conflictMediumFragment
  , conflictLightFragment, patternNoticeFragmentPrefix
  , patternNoticeFragmentSuffix, selfModelGapFragmentPrefix
  , trajectoryInsightFragmentPrefix
  , productModeSkillAnalyzeName, productModeSkillComposeName, productModeSkillWriteName
  )

data PressureChannel
  = DesireConflict | PatternNotice | SelfModelGap | TrajectoryInsight | ProductModeResistance
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded)

data BackgroundPressure = BackgroundPressure
  { channel  :: PressureChannel
  , pressure :: Double
  , content  :: Text
  , turns    :: Int
  } deriving stock (Show, Read)

data BackgroundState = BackgroundState
  { bsPressures    :: [BackgroundPressure]
  , bsLastSurfaced :: Int
  , bsTurnCount    :: Int
  } deriving stock (Show, Read)

data SurfacingEvent = SurfacingEvent
  { seChannel  :: PressureChannel
  , seContent  :: Text
  , seFragment :: Text
  , sePressure :: Double
  } deriving stock (Show, Read)

surfacingThreshold :: Double
surfacingThreshold = backgroundSurfacingThreshold

minSurfacingGap :: Int
minSurfacingGap = 3

initialBackground :: BackgroundState
initialBackground = BackgroundState
  { bsPressures    = map emptyChannel [minBound .. maxBound]
  , bsLastSurfaced = -100
  , bsTurnCount    = 0
  }

emptyChannel :: PressureChannel -> BackgroundPressure
emptyChannel ch = BackgroundPressure ch 0.0 "" 0

tickBackground :: BackgroundState -> BackgroundState
tickBackground bs = bs
  { bsPressures = map tick (bsPressures bs)
  , bsTurnCount = bsTurnCount bs + 1
  }
  where
    tick bp = bp { pressure = pressure bp * backgroundPressureDecayFactor, turns = turns bp + 1 }

recordKernelAction :: BackgroundState -> Text -> [Text] -> [Text] -> BackgroundState
recordKernelAction bs skillUsed _activeDesires conflicts =
  let bs1 = if not (null conflicts)
            then addPressure bs DesireConflict backgroundDesireConflictDelta (desireConflictPrefix <> T.intercalate ", " conflicts)
            else bs
      bs2 = if skillUsed `elem` [productModeSkillAnalyzeName, productModeSkillComposeName, productModeSkillWriteName]
            then addPressure bs1 ProductModeResistance backgroundProductModeResistanceDelta (productModeSkillLabel <> skillUsed)
            else bs1
  in bs2

recordDesireConflict :: BackgroundState -> Text -> BackgroundState
recordDesireConflict bs conflictDesc =
  addPressure bs DesireConflict backgroundExplicitConflictDelta conflictDesc

addPressure :: BackgroundState -> PressureChannel -> Double -> Text -> BackgroundState
addPressure bs ch delta newContent =
  let newPressures = map update (bsPressures bs)
  in bs { bsPressures = newPressures }
  where
    update bp
      | channel bp == ch = bp
          { pressure = min 1.0 (pressure bp + delta)
          , content  = if T.null (content bp) then newContent else content bp <> " / " <> newContent
          , turns    = 0
          }
      | otherwise = bp

checkSurfacing :: BackgroundState -> Maybe SurfacingEvent
checkSurfacing bs
  | bsTurnCount bs - bsLastSurfaced bs < minSurfacingGap = Nothing
  | otherwise =
      let candidates = filter (\bp -> pressure bp >= surfacingThreshold) (bsPressures bs)
      in case sortBy (comparing (Down . pressure)) candidates of
           []     -> Nothing
           (bp:_) -> Just (buildSurfacingEvent bp)

buildSurfacingEvent :: BackgroundPressure -> SurfacingEvent
buildSurfacingEvent bp =
  let (what, fragment) = channelSurfacing (channel bp) (content bp) (pressure bp)
  in SurfacingEvent (channel bp) what fragment (pressure bp)

channelSurfacing :: PressureChannel -> Text -> Double -> (Text, Text)
channelSurfacing DesireConflict pc p =
  (surfacingDesireConflictPrefix <> pc, conflictFragment pc p)
channelSurfacing PatternNotice pc _ =
  (surfacingPatternNoticePrefix <> pc, patternNoticeFragmentPrefix <> pc <> patternNoticeFragmentSuffix)
channelSurfacing SelfModelGap pc _ =
  (surfacingSelfModelGapPrefix <> pc, selfModelGapFragmentPrefix <> pc <> patternNoticeFragmentSuffix)
channelSurfacing TrajectoryInsight pc _ =
  (surfacingTrajectoryInsightPrefix <> pc, trajectoryInsightFragmentPrefix <> pc <> patternNoticeFragmentSuffix)
channelSurfacing ProductModeResistance pc _ =
  (surfacingProductModePrefix <> pc, surfacingProductModeFragment)

conflictFragment :: Text -> Double -> Text
conflictFragment pc p
  | p > backgroundConflictStrongThreshold = conflictStrongFragment <> T.take 60 pc <> conflictStrongSuffix
  | p > backgroundConflictMediumThreshold = conflictMediumFragment <> T.take 60 pc <> patternNoticeFragmentSuffix
  | otherwise = conflictLightFragment <> T.take 60 pc <> patternNoticeFragmentSuffix

surfacingToFragment :: SurfacingEvent -> Text
surfacingToFragment = seFragment

runBackgroundCycle :: BackgroundState -> Text -> [Text] -> [Text] -> (BackgroundState, Maybe SurfacingEvent)
runBackgroundCycle bs skill desires conflicts =
  let bs1 = tickBackground bs
      bs2 = recordKernelAction bs1 skill desires conflicts
      mEv = checkSurfacing bs2
      bs3 = maybe bs2 (applySurfacing bs2) mEv
  in (bs3, mEv)

applySurfacing :: BackgroundState -> SurfacingEvent -> BackgroundState
applySurfacing bs ev = bs
  { bsPressures = map reset (bsPressures bs)
  , bsLastSurfaced = bsTurnCount bs
  }
  where
    reset bp
      | channel bp == seChannel ev = bp { pressure = 0.0, content = "" }
      | otherwise = bp
