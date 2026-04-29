{-# LANGUAGE DerivingStrategies, DeriveAnyClass, OverloadedStrings, DeriveGeneric #-}
{-| Pressure detection and principled response selection for adversarial or corrective turns. -}
module QxFx0.Core.PrincipledCore
  ( PressureType(..)
  , PressureSignal(..)
  , PressureState(..)
  , PrincipledMode(..)
  , detectPressure
  , classifyPressure
  , pressureBandFromState
  , principledMode
  , principledToPromptSection
  , pressureDescription
  , PressureBand(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import QxFx0.Types (PressureBand(..))
import QxFx0.Core.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsAnyKeywordPhrase
  )
import QxFx0.Core.Policy.Contracts
  ( correctionMarkers, authorityMarkers, emotionalMarkers
  , newInfoMarkers, insistenceMarkers
  , holdGroundDirective, openToUpdateDirective, acknowledgeAndHoldDirective
  , principledHeader, newInfoTag, pressureForceLabel
  , pressureTypeText
  )
import QxFx0.Types.Text (fmtPct)
import QxFx0.Types.Thresholds
  ( principledAuthorityPressureStrength
  , principledCorrectionPressureWithNewInfo
  , principledCorrectionPressureWithoutNewInfo
  , principledEmotionalPressureStrength
  , principledInsistencePressureStrength
  , principledRepetitionOverlapThreshold
  )

data PressureType
  = DirectCorrection | AuthorityCommand | EmotionalDemand | RepetitiveInsistence
  deriving stock (Show, Eq, Ord, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PressureSignal = PressureSignal
  { psType       :: PressureType
  , psStrength   :: Double
  , psHasNewInfo :: Bool
  } deriving stock (Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PressureState
  = NoPressure
  | ActivePressure
      { pstIsRepeated :: !Bool
      , pstStrength   :: !Double
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PrincipledMode
  = HoldGround | OpenToUpdate | AcknowledgeAndHold
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

detectPressure :: Text -> [Text] -> Maybe PressureSignal
detectPressure raw history =
  let tokens = tokenizeKeywordText raw
      hasCorrection  = anyContains tokens correctionMarkers
      hasAuthority   = anyContains tokens authorityMarkers
      hasEmotional   = anyContains tokens emotionalMarkers
      hasInsistence  = anyContains tokens insistenceMarkers
      hasNewInfo     = anyContains tokens newInfoMarkers
      isRepetitive = case history of
        (prev:_) ->
          let ws1 = tokens
              ws2 = tokenizeKeywordText prev
              overlap = length (filter (`elem` ws2) ws1)
              total   = max 1 (length ws1)
              overlapRatio :: Double
              overlapRatio = fromIntegral overlap / fromIntegral total
          in overlapRatio > principledRepetitionOverlapThreshold && length ws1 > 4
        _ -> False
  in if hasAuthority
     then Just $ PressureSignal AuthorityCommand principledAuthorityPressureStrength False
     else if hasCorrection
          then Just $ PressureSignal
               DirectCorrection
               ( if hasNewInfo
                   then principledCorrectionPressureWithNewInfo
                   else principledCorrectionPressureWithoutNewInfo
               )
               hasNewInfo
          else if hasEmotional
               then Just $ PressureSignal EmotionalDemand principledEmotionalPressureStrength False
               else if hasInsistence || isRepetitive
                    then Just $ PressureSignal RepetitiveInsistence principledInsistencePressureStrength False
                    else Nothing

anyContains :: [Text] -> [Text] -> Bool
anyContains haystack needles = containsAnyKeywordPhrase haystack needles

principledMode :: PressureSignal -> PrincipledMode
principledMode signal
  | psHasNewInfo signal              = OpenToUpdate
  | psType signal == EmotionalDemand = AcknowledgeAndHold
  | otherwise                        = HoldGround

classifyPressure :: Maybe PressureSignal -> [Text] -> PressureState
classifyPressure Nothing _ = NoPressure
classifyPressure (Just sig) _ =
  ActivePressure
    { pstIsRepeated = psType sig `elem` [RepetitiveInsistence, DirectCorrection]
    , pstStrength = psStrength sig
    }

pressureBandFromState :: PressureState -> PressureBand
pressureBandFromState NoPressure = PressNone
pressureBandFromState ActivePressure { pstIsRepeated = True } = PressHeavy
pressureBandFromState ActivePressure {} = PressLight

principledToPromptSection :: PressureSignal -> PrincipledMode -> Text
principledToPromptSection signal mode =
  let pTypeText = case lookup (renderPressureType (psType signal)) pressureTypeText of
                   Just t -> t; Nothing -> renderPressureType (psType signal)
      header = principledHeader <> pTypeText <> "]"
  in T.unlines $ [header, ""] ++ modeDirective mode

modeDirective :: PrincipledMode -> [Text]
modeDirective HoldGround = holdGroundDirective
modeDirective OpenToUpdate = openToUpdateDirective
modeDirective AcknowledgeAndHold = acknowledgeAndHoldDirective

pressureDescription :: PressureSignal -> Text
pressureDescription signal =
  renderPressureType (psType signal) <>
  pressureForceLabel <> fmtPct (psStrength signal) <> ")" <>
  if psHasNewInfo signal then newInfoTag else ""

renderPressureType :: PressureType -> Text
renderPressureType DirectCorrection     = "\1087\1088\1103\1084\1072\1103 \1082\1086\1088\1088\1077\1082\1094\1080\1103"
renderPressureType AuthorityCommand     = "\1072\1074\1090\1086\1088\1080\1090\1072\1088\1085\1072\1103 \1082\1086\1084\1072\1085\1076\1072"
renderPressureType EmotionalDemand      = "\1101\1084\1086\1094\1080\1086\1085\1072\1083\1100\1085\1086\1077 \1076\1072\1074\1083\1077\1085\1080\1077"
renderPressureType RepetitiveInsistence = "\1087\1086\1074\1090\1086\1088\1085\1086\1077 \1085\1072\1089\1090\1072\1080\1074\1072\1085\1080\1077"
